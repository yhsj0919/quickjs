import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'quickjs_ui_resource.dart';
import 'quickjs_ui_resource_resolver.dart';

const int quickjsUiManifestSchemaVersion = 1;
const String quickjsUiPackageEntry = 'main.mjs';
const String quickjsUiPackageManifest = 'manifest.json';

final class QuickjsUiManifest {
  const QuickjsUiManifest({
    required this.schemaVersion,
    required this.id,
    required this.version,
    required this.entry,
    required this.modules,
    this.name,
    this.resources = const <String, QuickjsUiResourceReference>{},
    this.permissions = const <String>[],
    this.routes = const <String, QuickjsUiRouteManifest>{},
    this.cache,
    this.metadata = const <String, Object?>{},
  });

  final int schemaVersion;
  final String id;
  final String? name;
  final String version;
  final String entry;
  final Map<String, QuickjsUiModuleManifest> modules;
  final Map<String, QuickjsUiResourceReference> resources;
  final List<String> permissions;
  final Map<String, QuickjsUiRouteManifest> routes;
  final QuickjsUiCacheManifest? cache;
  final Map<String, Object?> metadata;

  factory QuickjsUiManifest.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'quickjs_ui package manifest must be an object',
      );
    }
    return QuickjsUiManifest.fromMap(
      decoded.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }

  factory QuickjsUiManifest.fromMap(Map<String, Object?> manifest) {
    final schemaVersion = _intValue(
      manifest['schemaVersion'],
      'schemaVersion',
      defaultValue: quickjsUiManifestSchemaVersion,
    )!;
    if (schemaVersion != quickjsUiManifestSchemaVersion) {
      throw FormatException(
        'quickjs_ui package manifest schemaVersion is not supported: '
        '$schemaVersion',
      );
    }
    final entry = QuickjsUiResourceResolver.normalizePath(
      _string(manifest['entry'], 'entry'),
    );
    final modules = _modules(manifest['modules']);
    if (!modules.containsKey(entry)) {
      throw FormatException(
        'quickjs_ui package manifest entry must be listed in modules: $entry',
      );
    }
    return QuickjsUiManifest(
      schemaVersion: schemaVersion,
      id: _string(manifest['id'], 'id'),
      name: _optionalString(manifest['name'], 'name'),
      version: _string(manifest['version'], 'version'),
      entry: entry,
      modules: modules,
      resources: _resources(manifest['resources']),
      permissions: _stringList(manifest['permissions'], 'permissions'),
      routes: _routes(manifest['routes']),
      cache: manifest['cache'] == null
          ? null
          : QuickjsUiCacheManifest.fromMap(_map(manifest['cache'], 'cache')),
      metadata: _metadata(manifest['metadata']),
    );
  }

  void validatePackageRoot() {
    if (entry != quickjsUiPackageEntry) {
      throw FormatException(
        'quickjs_ui package manifest entry must be "$quickjsUiPackageEntry"',
      );
    }
    if (!modules.containsKey(quickjsUiPackageEntry)) {
      throw const FormatException(
        'quickjs_ui package modules must contain main.mjs',
      );
    }
  }

  void validateImports(Map<String, String> loadedModules) {
    final declared = modules.keys.toSet();
    for (final module in loadedModules.entries) {
      for (final importPath in quickjsUiStaticImports(module.value)) {
        if (!quickjsUiIsRelativeImport(importPath)) {
          continue;
        }
        final imported = QuickjsUiResourceResolver.normalizePath(
          importPath,
          from: module.key,
        );
        if (!declared.contains(imported)) {
          throw FormatException(
            'quickjs_ui package import is not declared in modules: $imported',
          );
        }
      }
    }
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      if (name != null) 'name': name,
      'version': version,
      'entry': entry,
      'modules': <String, Object?>{
        for (final entry in modules.entries) entry.key: entry.value.toMap(),
      },
      if (resources.isNotEmpty)
        'resources': <String, Object?>{
          for (final entry in resources.entries) entry.key: entry.value.toMap(),
        },
      if (permissions.isNotEmpty) 'permissions': permissions,
      if (routes.isNotEmpty)
        'routes': <String, Object?>{
          for (final entry in routes.entries) entry.key: entry.value.toMap(),
        },
      if (cache != null) 'cache': cache!.toMap(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

final class QuickjsUiModuleManifest {
  const QuickjsUiModuleManifest({
    required this.path,
    this.source,
    this.sha256,
    this.type = 'module',
  });

  final String path;
  final String? source;
  final String? sha256;
  final String type;

  String get loadPath => source ?? path;

  void verifySource(String content) {
    if (sha256 == null) {
      return;
    }
    final actual = quickjsUiSha256Hex(content);
    if (actual != sha256) {
      throw FormatException(
        'quickjs_ui package module checksum mismatch: $path',
      );
    }
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (source != null) 'source': source,
      if (sha256 != null) 'sha256': sha256,
      if (type != 'module') 'type': type,
    };
  }
}

final class QuickjsUiRouteManifest {
  const QuickjsUiRouteManifest({
    required this.entry,
    this.title,
    this.initialProps = const <String, Object?>{},
  });

  final String entry;
  final String? title;
  final Map<String, Object?> initialProps;

  factory QuickjsUiRouteManifest.fromMap(Map<String, Object?> map) {
    return QuickjsUiRouteManifest(
      entry: QuickjsUiResourceResolver.normalizePath(
        _string(map['entry'], 'routes.entry'),
      ),
      title: _optionalString(map['title'], 'routes.title'),
      initialProps: _metadata(map['initialProps']),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'entry': entry,
      if (title != null) 'title': title,
      if (initialProps.isNotEmpty) 'initialProps': initialProps,
    };
  }
}

final class QuickjsUiCacheManifest {
  const QuickjsUiCacheManifest({
    required this.mode,
    this.immutable = false,
    this.maxAgeSeconds,
  });

  final String mode;
  final bool immutable;
  final int? maxAgeSeconds;

  factory QuickjsUiCacheManifest.fromMap(Map<String, Object?> map) {
    return QuickjsUiCacheManifest(
      mode: _optionalString(map['mode'], 'cache.mode') ?? 'versioned',
      immutable: _boolValue(map['immutable'], 'cache.immutable') ?? false,
      maxAgeSeconds: _intValue(map['maxAgeSeconds'], 'cache.maxAgeSeconds'),
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'mode': mode,
      if (immutable) 'immutable': immutable,
      if (maxAgeSeconds != null) 'maxAgeSeconds': maxAgeSeconds,
    };
  }
}

String quickjsUiSha256Hex(String source) {
  return sha256.convert(utf8.encode(source)).toString();
}

Iterable<String> quickjsUiStaticImports(String source) sync* {
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

bool quickjsUiIsRelativeImport(String specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../');
}

Map<String, QuickjsUiModuleManifest> _modules(Object? value) {
  if (value is List) {
    return Map<String, QuickjsUiModuleManifest>.unmodifiable(
      <String, QuickjsUiModuleManifest>{
        for (final item in value)
          QuickjsUiResourceResolver.normalizePath(
            _string(item, 'modules[]'),
          ): QuickjsUiModuleManifest(
            path: QuickjsUiResourceResolver.normalizePath(
              _string(item, 'modules[]'),
            ),
          ),
      },
    );
  }
  if (value is Map) {
    return Map<String, QuickjsUiModuleManifest>.unmodifiable(
      value.map((key, moduleValue) {
        final path = QuickjsUiResourceResolver.normalizePath('$key');
        if (moduleValue is String) {
          return MapEntry<String, QuickjsUiModuleManifest>(
            path,
            QuickjsUiModuleManifest(
              path: path,
              source: QuickjsUiResourceResolver.normalizePath(moduleValue),
            ),
          );
        }
        final map = _map(moduleValue, 'modules.$key');
        return MapEntry<String, QuickjsUiModuleManifest>(
          path,
          QuickjsUiModuleManifest(
            path: path,
            source: map['source'] == null
                ? null
                : QuickjsUiResourceResolver.normalizePath(
                    _string(map['source'], 'modules.$key.source'),
                  ),
            sha256: _sha256(map['sha256'] ?? map['checksum'], 'modules.$key'),
            type: _optionalString(map['type'], 'modules.$key.type') ?? 'module',
          ),
        );
      }),
    );
  }
  throw const FormatException(
    'quickjs_ui package manifest "modules" must be an array or object',
  );
}

Map<String, QuickjsUiResourceReference> _resources(Object? value) {
  if (value == null) {
    return const <String, QuickjsUiResourceReference>{};
  }
  if (value is List) {
    return Map<String, QuickjsUiResourceReference>.unmodifiable(
      <String, QuickjsUiResourceReference>{
        for (final item in value)
          _resourceKey(
            QuickjsUiResourceReference.parse(item, name: 'resources[]'),
          ): QuickjsUiResourceReference.parse(
            item,
            name: 'resources[]',
          ),
      },
    );
  }
  if (value is Map) {
    return Map<String, QuickjsUiResourceReference>.unmodifiable(
      value.map((key, resourceValue) {
        final resource = QuickjsUiResourceReference.parse(
          resourceValue is Map
              ? <String, Object?>{
                  'uri': '$key',
                  ...resourceValue.map(
                    (key, value) => MapEntry<String, Object?>('$key', value),
                  ),
                }
              : resourceValue,
          name: 'resources.$key',
        );
        return MapEntry<String, QuickjsUiResourceReference>('$key', resource);
      }),
    );
  }
  throw const FormatException(
    'quickjs_ui package manifest "resources" must be an array or object',
  );
}

Map<String, QuickjsUiRouteManifest> _routes(Object? value) {
  if (value == null) {
    return const <String, QuickjsUiRouteManifest>{};
  }
  final map = _map(value, 'routes');
  return Map<String, QuickjsUiRouteManifest>.unmodifiable(
    map.map((key, value) {
      return MapEntry<String, QuickjsUiRouteManifest>(
        key,
        QuickjsUiRouteManifest.fromMap(_map(value, 'routes.$key')),
      );
    }),
  );
}

Map<String, Object?> _metadata(Object? value) {
  if (value == null) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(_map(value, 'metadata'));
}

String _resourceKey(QuickjsUiResourceReference resource) {
  if (resource.kind == QuickjsUiResourceKind.asset) {
    return QuickjsUiResourceResolver.normalizePath(resource.location);
  }
  return resource.location;
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is Map) {
    return value.map((key, value) => MapEntry<String, Object?>('$key', value));
  }
  throw FormatException(
    'quickjs_ui package manifest "$name" must be an object',
  );
}

List<String> _stringList(Object? value, String name) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    throw FormatException(
      'quickjs_ui package manifest "$name" must be an array',
    );
  }
  return List<String>.unmodifiable(
    value.map((item) => _string(item, '$name[]')),
  );
}

String _string(Object? value, String name) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be a string');
}

String? _optionalString(Object? value, String name) {
  if (value == null) {
    return null;
  }
  return _string(value, name);
}

String? _sha256(Object? value, String name) {
  final text = _optionalString(value, '$name.sha256');
  if (text == null) {
    return null;
  }
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) {
    throw FormatException(
      'quickjs_ui package manifest "$name.sha256" must be 64 hex chars',
    );
  }
  return text.toLowerCase();
}

int? _intValue(Object? value, String name, {int? defaultValue}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be an int');
}

bool? _boolValue(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be a bool');
}
