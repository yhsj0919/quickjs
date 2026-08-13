import 'dart:convert';
import 'dart:io';

/// Generates the editor configuration for JavaScript UI pages.
///
/// The public TypeScript declarations remain the source of truth. This tool
/// only discovers declaration modules and writes project-side indexes.
Future<void> runQuickjsUiCodegen(List<String> args) async {
  final options = _CodegenOptions.parse(args);
  if (options.help) {
    stdout.write(_CodegenOptions.usage);
    return;
  }

  final root = Directory(options.root);
  if (!root.existsSync()) {
    throw ArgumentError('JS 页面目录不存在: ${root.path}');
  }

  final output = File(options.output);
  final outputDirectory = output.parent;
  final packageRoot = Directory.fromUri(Platform.script).parent.parent;
  final coreTypes = File('${packageRoot.path}/js/quickjs_ui.d.ts');
  if (!coreTypes.existsSync()) {
    throw StateError('找不到 lemon_js_ui 核心类型声明: ${coreTypes.path}');
  }

  final declarationFiles = <File>[coreTypes];
  declarationFiles.addAll(
    root
        .listSync(recursive: true)
        .whereType<File>()
        .where((file) => file.path.toLowerCase().endsWith('.d.ts'))
        .toList()
      ..sort((a, b) => a.path.compareTo(b.path)),
  );
  for (final path in options.extraTypes) {
    final file = File(path);
    if (!file.existsSync()) {
      throw ArgumentError('类型声明不存在: ${file.path}');
    }
    if (!declarationFiles.any(
      (item) => item.absolute.path == file.absolute.path,
    )) {
      declarationFiles.add(file);
    }
  }

  final modules = <String, String>{
    'quickjs_ui': _relativeImport(outputDirectory, coreTypes),
  };
  for (final file in declarationFiles.skip(1)) {
    final source = file.readAsStringSync();
    final matches = RegExp(
      r'''declare\s+module\s+['"]([^'"]+)['"]''',
    ).allMatches(source);
    for (final match in matches) {
      modules[match.group(1)!] = _relativeImport(outputDirectory, file);
    }
  }

  final jsconfig = <String, Object?>{
    r'$schema': 'http://json.schemastore.org/tsconfig',
    'compilerOptions': <String, Object?>{
      'checkJs': true,
      'module': 'ESNext',
      'moduleResolution': 'Bundler',
      'target': 'ES2022',
      'baseUrl': '.',
      'paths': {
        for (final entry in modules.entries) entry.key: [entry.value],
      },
    },
    'include': ['**/*.mjs', '**/*.js'],
  };
  final index = <String, Object?>{
    'version': 1,
    'root': _relativeImport(outputDirectory, root),
    'modules': modules,
  };

  final indexFile = File('${outputDirectory.path}/.quickjs-ui/types.json');
  final files = <File, String>{
    output: const JsonEncoder.withIndent('  ').convert(jsconfig),
    indexFile: const JsonEncoder.withIndent('  ').convert(index),
  };
  for (final entry in files.entries) {
    final expected = '${entry.value}\n';
    if (options.check) {
      if (!entry.key.existsSync() || entry.key.readAsStringSync() != expected) {
        throw StateError('生成文件已过期，请重新运行 codegen: ${entry.key.path}');
      }
    } else {
      entry.key.parent.createSync(recursive: true);
      entry.key.writeAsStringSync(expected);
    }
  }

  stdout.writeln(
    options.check ? '代码提示配置检查通过: ${output.path}' : '已生成代码提示配置: ${output.path}',
  );
  stdout.writeln('已注册模块: ${modules.keys.join(', ')}');
}

String _relativeImport(Directory from, FileSystemEntity target) {
  final relative = _relativePath(from.absolute.path, target.absolute.path);
  return relative.startsWith('.') ? relative : './$relative';
}

String _relativePath(String from, String to) {
  final fromParts = _normalise(from).split('/');
  final toParts = _normalise(to).split('/');
  while (fromParts.isNotEmpty &&
      toParts.isNotEmpty &&
      fromParts.first == toParts.first) {
    fromParts.removeAt(0);
    toParts.removeAt(0);
  }
  return [...List<String>.filled(fromParts.length, '..'), ...toParts].join('/');
}

String _normalise(String value) => value.replaceAll(r'\', '/');

class _CodegenOptions {
  _CodegenOptions({
    required this.root,
    required this.output,
    required this.extraTypes,
    required this.check,
    required this.help,
  });

  final String root;
  final String output;
  final List<String> extraTypes;
  final bool check;
  final bool help;

  static const usage = '''用法:
  dart run lemon_js_ui:codegen --root <JS 页面目录>

选项:
  --root <目录>       JS 页面根目录，默认 assets/quickjs_ui
  --output <文件>     输出 jsconfig.json，默认 <root>/jsconfig.json
  --types <文件>      额外 .d.ts，可重复传入
  --check             只检查生成文件是否最新
  -h, --help          显示帮助
''';

  static _CodegenOptions parse(List<String> args) {
    var root = 'assets/quickjs_ui';
    String? output;
    final extraTypes = <String>[];
    var check = false;
    var help = false;
    for (var i = 0; i < args.length; i++) {
      switch (args[i]) {
        case '--root':
          root = args[++i];
        case '--output':
          output = args[++i];
        case '--types':
          extraTypes.add(args[++i]);
        case '--check':
          check = true;
        case '-h':
        case '--help':
          help = true;
        default:
          throw ArgumentError('未知参数: ${args[i]}');
      }
    }
    return _CodegenOptions(
      root: root,
      output: output ?? '$root/jsconfig.json',
      extraTypes: extraTypes,
      check: check,
      help: help,
    );
  }
}
