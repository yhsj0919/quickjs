import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

const _manifestFileName = 'manifest.json';
const _packageEntry = 'main.mjs';

Future<void> runJsUiManifestTool(List<String> args) async {
  final options = _ManifestToolOptions.parse(args);
  if (options.help) {
    stdout.writeln(_usage);
    return;
  }

  try {
    final result = await _generateManifest(options);
    if (options.check) {
      if (result.changed) {
        stderr.writeln(
          'manifest.json is out of date. Run: '
          'dart run quickjs_ui:manifest --root ${options.root.path}',
        );
        exitCode = 1;
        return;
      }
      stdout.writeln('manifest.json is up to date: ${result.manifest.path}');
      return;
    }
    stdout.writeln(
      '${result.created ? 'created' : 'updated'} ${result.manifest.path}',
    );
  } on Object catch (error) {
    stderr.writeln(error);
    exitCode = 64;
  }
}

Future<_ManifestToolResult> _generateManifest(
  _ManifestToolOptions options,
) async {
  final root = Directory(options.root.absolute.path);
  if (!await root.exists()) {
    throw ArgumentError('package root does not exist: ${root.path}');
  }
  final entry = File(_join(root.path, _packageEntry));
  if (!await entry.exists()) {
    throw ArgumentError(
      'package root must contain $_packageEntry: ${root.path}',
    );
  }

  final manifestFile = File(_join(root.path, _manifestFileName));
  final existing = await _readExistingManifest(manifestFile);
  final modules = await _scanModules(root);
  _validateRelativeImports(modules);

  final id = options.id ?? existing['id'] as String? ?? _idFromDirectory(root);
  final version = options.version ?? existing['version'] as String? ?? '0.1.0';
  final name = options.name ?? existing['name'] as String?;
  final manifest = _orderedManifest(
    existing: existing,
    id: id,
    name: name,
    version: version,
    modules: modules,
  );
  final encoded = const JsonEncoder.withIndent('  ').convert(manifest);
  final output = '$encoded\n';
  final oldOutput = await manifestFile.exists()
      ? await manifestFile.readAsString()
      : null;
  final changed = oldOutput != output;
  if (!options.check && changed) {
    await manifestFile.writeAsString(output);
  }
  return _ManifestToolResult(
    manifest: manifestFile,
    created: oldOutput == null,
    changed: changed,
  );
}

Future<Map<String, Object?>> _readExistingManifest(File manifestFile) async {
  if (!await manifestFile.exists()) {
    return <String, Object?>{};
  }
  final decoded = jsonDecode(await manifestFile.readAsString());
  if (decoded is! Map) {
    throw const FormatException('manifest.json must be a JSON object');
  }
  return decoded.map((key, value) => MapEntry<String, Object?>('$key', value));
}

Future<Map<String, _ModuleInfo>> _scanModules(Directory root) async {
  final modules = <String, _ModuleInfo>{};
  await for (final entity in root.list(recursive: true, followLinks: false)) {
    if (entity is! File || !entity.path.endsWith('.mjs')) {
      continue;
    }
    final relative = _relativePath(root, entity);
    final source = await entity.readAsString();
    modules[relative] = _ModuleInfo(path: relative, source: source);
  }
  if (!modules.containsKey(_packageEntry)) {
    throw const FormatException('manifest modules must contain main.mjs');
  }
  return Map<String, _ModuleInfo>.fromEntries(
    modules.entries.toList()..sort(_compareModuleEntries),
  );
}

int _compareModuleEntries(
  MapEntry<String, _ModuleInfo> a,
  MapEntry<String, _ModuleInfo> b,
) {
  if (a.key == _packageEntry) {
    return -1;
  }
  if (b.key == _packageEntry) {
    return 1;
  }
  return a.key.compareTo(b.key);
}

void _validateRelativeImports(Map<String, _ModuleInfo> modules) {
  final declared = modules.keys.toSet();
  for (final module in modules.entries) {
    for (final importPath in _staticImports(module.value.source)) {
      if (!_isRelativeImport(importPath)) {
        continue;
      }
      final resolved = _normalizeRelativeImport(module.key, importPath);
      if (!declared.contains(resolved)) {
        throw FormatException(
          'relative import is not declared or missing: '
          '${module.key} -> $importPath ($resolved)',
        );
      }
    }
  }
}

Map<String, Object?> _orderedManifest({
  required Map<String, Object?> existing,
  required String id,
  required String? name,
  required String version,
  required Map<String, _ModuleInfo> modules,
}) {
  return <String, Object?>{
    'schemaVersion': existing['schemaVersion'] ?? 1,
    'id': id,
    if (name != null && name.isNotEmpty) 'name': name,
    'version': version,
    'entry': _packageEntry,
    'modules': <String, Object?>{
      for (final module in modules.entries)
        module.key: <String, Object?>{
          'sha256': _sha256Hex(module.value.source),
        },
    },
    if (existing['resources'] != null) 'resources': existing['resources'],
    if (existing['permissions'] != null) 'permissions': existing['permissions'],
    if (existing['routes'] != null) 'routes': existing['routes'],
    if (existing['cache'] != null) 'cache': existing['cache'],
    if (existing['metadata'] != null) 'metadata': existing['metadata'],
  };
}

Iterable<String> _staticImports(String source) sync* {
  final patterns = <RegExp>[
    RegExp(
      r'''import\s+(?:[^'"]*?\s+from\s+)?["']([^"']+)["']''',
      multiLine: true,
    ),
    RegExp(r'''export\s+[^'"]*?\s+from\s+["']([^"']+)["']''', multiLine: true),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(source)) {
      final specifier = match.group(1);
      if (specifier != null && specifier.isNotEmpty) {
        yield specifier;
      }
    }
  }
}

String _normalizeRelativeImport(String from, String importPath) {
  final fromParts = from.split('/')..removeLast();
  final parts = <String>[...fromParts];
  for (final segment in importPath.split('/')) {
    if (segment.isEmpty || segment == '.') {
      continue;
    }
    if (segment == '..') {
      if (parts.isEmpty) {
        throw FormatException(
          'relative import escapes package root: $from -> $importPath',
        );
      }
      parts.removeLast();
      continue;
    }
    parts.add(segment);
  }
  return parts.join('/');
}

bool _isRelativeImport(String specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../');
}

String _sha256Hex(String source) {
  return sha256.convert(utf8.encode(source)).toString();
}

String _relativePath(Directory root, File file) {
  final rootPath = root.absolute.path.endsWith(Platform.pathSeparator)
      ? root.absolute.path
      : '${root.absolute.path}${Platform.pathSeparator}';
  final filePath = file.absolute.path;
  if (!filePath.startsWith(rootPath)) {
    throw ArgumentError('file is outside package root: $filePath');
  }
  return filePath.substring(rootPath.length).replaceAll('\\', '/');
}

String _idFromDirectory(Directory root) {
  final name = root.uri.pathSegments
      .where((segment) => segment.isNotEmpty)
      .lastOrNull;
  final source = name == null || name.isEmpty ? 'quickjs_ui_package' : name;
  return source
      .replaceAll(RegExp(r'[^a-zA-Z0-9_.-]'), '_')
      .replaceAll(RegExp(r'_+'), '_');
}

String _join(String base, String child) {
  if (base.endsWith(Platform.pathSeparator)) {
    return '$base$child';
  }
  return '$base${Platform.pathSeparator}$child';
}

final class _ModuleInfo {
  const _ModuleInfo({required this.path, required this.source});

  final String path;
  final String source;
}

final class _ManifestToolResult {
  const _ManifestToolResult({
    required this.manifest,
    required this.created,
    required this.changed,
  });

  final File manifest;
  final bool created;
  final bool changed;
}

final class _ManifestToolOptions {
  const _ManifestToolOptions({
    required this.root,
    this.id,
    this.name,
    this.version,
    this.check = false,
    this.help = false,
  });

  final Directory root;
  final String? id;
  final String? name;
  final String? version;
  final bool check;
  final bool help;

  factory _ManifestToolOptions.parse(List<String> args) {
    var root = Directory.current;
    String? id;
    String? name;
    String? version;
    var check = false;
    var help = false;

    for (var index = 0; index < args.length; index += 1) {
      final arg = args[index];
      switch (arg) {
        case '--root':
          root = Directory(_requiredValue(args, ++index, arg));
        case '--id':
          id = _requiredValue(args, ++index, arg);
        case '--name':
          name = _requiredValue(args, ++index, arg);
        case '--version':
          version = _requiredValue(args, ++index, arg);
        case '--check':
          check = true;
        case '--help':
        case '-h':
          help = true;
        default:
          throw ArgumentError('unknown option: $arg\n\n$_usage');
      }
    }

    return _ManifestToolOptions(
      root: root,
      id: id,
      name: name,
      version: version,
      check: check,
      help: help,
    );
  }
}

String _requiredValue(List<String> args, int index, String option) {
  if (index >= args.length || args[index].startsWith('--')) {
    throw ArgumentError('$option requires a value');
  }
  return args[index];
}

const _usage = '''
Generate or update a quickjs_ui package manifest.

Usage:
  dart run quickjs_ui:manifest --root <package-root> [options]

Options:
  --root <dir>       Package root containing main.mjs.
  --id <id>          Package id. Defaults to existing manifest id or directory name.
  --name <name>      Package display name. Defaults to existing manifest name.
  --version <ver>    Package version. Defaults to existing manifest version or 0.1.0.
  --check            Do not write. Exit 1 when manifest.json is out of date.
  -h, --help         Show this help.
''';
