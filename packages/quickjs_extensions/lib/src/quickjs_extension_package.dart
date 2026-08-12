import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'quickjs_extension_manifest.dart';
import 'quickjs_extension_package_file.dart';
import 'quickjs_extension_package_format.dart';

/// 尚未解析的扩展安装包。
final class QuickjsExtensionPackage {
  /// 使用清单源码以及 Core、UI 模块创建内存安装包。
  QuickjsExtensionPackage({
    required this.manifestSource,
    Map<String, String> serviceModules = const <String, String>{},
    Map<String, String> uiModules = const <String, String>{},
    Map<String, QuickjsUiResourceReference> uiResources =
        const <String, QuickjsUiResourceReference>{},
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) : serviceModules = Map<String, String>.unmodifiable(serviceModules),
       uiModules = Map<String, String>.unmodifiable(uiModules),
       uiResources = Map<String, QuickjsUiResourceReference>.unmodifiable(
         uiResources,
       ),
       uiPlugins = List<QuickjsUiPlugin>.unmodifiable(uiPlugins);

  /// 从持久化 Map 恢复扩展包源码。
  factory QuickjsExtensionPackage.fromMap(
    Map<String, Object?> map, {
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) => QuickjsExtensionPackage(
    manifestSource: map['manifestSource']! as String,
    serviceModules: Map<String, String>.from(
      (map['serviceModules']! as Map).cast<String, String>(),
    ),
    uiModules: Map<String, String>.from(
      (map['uiModules']! as Map).cast<String, String>(),
    ),
    uiResources: <String, QuickjsUiResourceReference>{
      for (final entry
          in ((map['uiResources'] as Map?) ?? const <String, Object?>{})
              .entries)
        entry.key as String: QuickjsUiResourceReference.parse(
          entry.value,
          name: 'uiResources.${entry.key}',
        ),
    },
    uiPlugins: uiPlugins,
  );

  /// 从 Flutter assets 中的统一清单和相邻模块加载扩展包。
  static Future<QuickjsExtensionPackage> asset({
    required String manifestAsset,
    AssetBundle? bundle,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final assets = bundle ?? rootBundle;
    final normalizedManifest = _normalizePath(manifestAsset);
    final root = _dirname(normalizedManifest);
    return _loadDirectoryPackage(
      manifestSource: await assets.loadString(normalizedManifest),
      loadModule: (path) => assets.loadString(_join(root, path)),
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地目录中的统一清单和相邻模块加载扩展包。
  static Future<QuickjsExtensionPackage> file({
    required String manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final normalizedManifest = _normalizePath(manifestPath);
    final root = _dirname(normalizedManifest);
    return _loadDirectoryPackage(
      manifestSource: await readQuickjsExtensionFileString(normalizedManifest),
      loadModule: (path) => readQuickjsExtensionFileString(_join(root, path)),
      uiPlugins: uiPlugins,
    );
  }

  /// 从网络清单和同一目录下的模块加载扩展包。
  static Future<QuickjsExtensionPackage> network({
    required Uri manifestUrl,
    http.Client? client,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    final root = manifestUrl.resolve('.');
    Future<String> load(Uri uri) async {
      if (!uri.toString().startsWith(root.toString())) {
        throw FormatException('Extension network path escapes root: $uri');
      }
      final response = await resolvedClient.get(uri);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Extension request failed with HTTP ${response.statusCode}',
          uri,
        );
      }
      return utf8.decode(response.bodyBytes);
    }

    try {
      return await _loadDirectoryPackage(
        manifestSource: await load(manifestUrl),
        loadModule: (path) => load(root.resolve(path)),
        uiPlugins: uiPlugins,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  /// 从 Asset 裸入口递归加载旧 Core 插件。
  static Future<QuickjsExtensionPackage> coreAsset({
    required String entryAsset,
    required QuickjsCorePackageAdapter adapter,
    AssetBundle? bundle,
  }) async {
    final assets = bundle ?? rootBundle;
    final entry = _normalizePath(entryAsset);
    final root = _dirname(entry);
    return _loadCoreEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: (path) => assets.loadString(_join(root, path)),
    );
  }

  /// 从本地裸入口递归加载旧 Core 插件。
  static Future<QuickjsExtensionPackage> coreFile({
    required String entryPath,
    required QuickjsCorePackageAdapter adapter,
  }) async {
    final entry = _normalizePath(entryPath);
    final root = _dirname(entry);
    return _loadCoreEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: (path) => readQuickjsExtensionFileString(_join(root, path)),
    );
  }

  /// 从网络裸入口递归加载旧 Core 插件。
  static Future<QuickjsExtensionPackage> coreNetwork({
    required Uri entryUrl,
    required QuickjsCorePackageAdapter adapter,
    http.Client? client,
  }) => _loadNetworkEntry(
    entryUrl: entryUrl,
    client: client,
    load: (entry, loader) =>
        _loadCoreEntry(entry: entry, adapter: adapter, loadModule: loader),
  );

  /// 从 Asset 裸入口递归加载旧 JSUI 插件。
  static Future<QuickjsExtensionPackage> uiAsset({
    required String entryAsset,
    required QuickjsUiPackageAdapter adapter,
    AssetBundle? bundle,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final assets = bundle ?? rootBundle;
    final entry = _normalizePath(entryAsset);
    final root = _dirname(entry);
    return _loadUiEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: (path) => assets.loadString(_join(root, path)),
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地裸入口递归加载旧 JSUI 插件。
  static Future<QuickjsExtensionPackage> uiFile({
    required String entryPath,
    required QuickjsUiPackageAdapter adapter,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final entry = _normalizePath(entryPath);
    final root = _dirname(entry);
    return _loadUiEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: (path) => readQuickjsExtensionFileString(_join(root, path)),
      uiPlugins: uiPlugins,
    );
  }

  /// 从网络裸入口递归加载旧 JSUI 插件。
  static Future<QuickjsExtensionPackage> uiNetwork({
    required Uri entryUrl,
    required QuickjsUiPackageAdapter adapter,
    http.Client? client,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) => _loadNetworkEntry(
    entryUrl: entryUrl,
    client: client,
    load: (entry, loader) => _loadUiEntry(
      entry: entry,
      adapter: adapter,
      loadModule: loader,
      uiPlugins: uiPlugins,
    ),
  );

  /// 从 Flutter asset ZIP 加载完整扩展包。
  static Future<QuickjsExtensionPackage> assetZip({
    required String assetKey,
    AssetBundle? bundle,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final data = await (bundle ?? rootBundle).load(assetKey);
    return zipBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地 ZIP 文件加载完整扩展包。
  static Future<QuickjsExtensionPackage> fileZip({
    required String path,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => zipBytes(
    await readQuickjsExtensionFileBytes(path),
    manifestPath: manifestPath,
    uiPlugins: uiPlugins,
  );

  /// 从网络 ZIP 加载完整扩展包。
  static Future<QuickjsExtensionPackage> networkZip({
    required Uri url,
    http.Client? client,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    try {
      final response = await resolvedClient.get(url);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Extension ZIP request failed with HTTP ${response.statusCode}',
          url,
        );
      }
      return zipBytes(
        response.bodyBytes,
        manifestPath: manifestPath,
        uiPlugins: uiPlugins,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  /// 从内存 ZIP 字节加载完整扩展包。
  static Future<QuickjsExtensionPackage> zipBytes(
    Uint8List bytes, {
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final files = <String, Uint8List>{};
    for (final file in ZipDecoder().decodeBytes(bytes).files) {
      if (!file.isFile) continue;
      files[_normalizePath(file.name)] = file.content;
    }
    final manifestEntry = _findZipManifest(files, manifestPath);
    final root = _dirname(manifestEntry.key);
    return _loadDirectoryPackage(
      manifestSource: utf8.decode(manifestEntry.value),
      loadModule: (path) async {
        final resolved = _join(root, path);
        final source = files[resolved];
        if (source == null) {
          throw FormatException('Extension ZIP module is missing: $resolved');
        }
        return utf8.decode(source);
      },
      uiPlugins: uiPlugins,
    );
  }

  /// 解析指定格式的 ZIP；旧格式必须提供对应适配信息。
  static Future<QuickjsExtensionPackage> formattedZipBytes(
    Uint8List bytes, {
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => switch (format) {
    QuickjsExtensionPackageFormat.extension => zipBytes(
      bytes,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    QuickjsExtensionPackageFormat.core => _fromCorePlugin(
      QuickjsZipPlugin.bytes(bytes, manifestPath: manifestPath),
      coreAdapter ?? (throw ArgumentError.notNull('coreAdapter')),
    ),
    QuickjsExtensionPackageFormat.ui => _fromUiBundle(
      await QuickjsUiBundle.zipPackageBytes(bytes),
      uiAdapter ?? (throw ArgumentError.notNull('uiAdapter')),
      uiPlugins,
    ),
  };

  /// 从 Asset 按显式格式解析 ZIP。
  static Future<QuickjsExtensionPackage> formattedAssetZip({
    required String assetKey,
    AssetBundle? bundle,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final data = await (bundle ?? rootBundle).load(assetKey);
    return formattedZipBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      format: format,
      coreAdapter: coreAdapter,
      uiAdapter: uiAdapter,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地文件按显式格式解析 ZIP。
  static Future<QuickjsExtensionPackage> formattedFileZip({
    required String path,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => formattedZipBytes(
    await readQuickjsExtensionFileBytes(path),
    format: format,
    coreAdapter: coreAdapter,
    uiAdapter: uiAdapter,
    manifestPath: manifestPath,
    uiPlugins: uiPlugins,
  );

  /// 从网络按显式格式下载并解析 ZIP。
  static Future<QuickjsExtensionPackage> formattedNetworkZip({
    required Uri url,
    http.Client? client,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    String? manifestPath,
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async {
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    try {
      final response = await resolvedClient.get(url);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Extension ZIP request failed with HTTP ${response.statusCode}',
          url,
        );
      }
      return formattedZipBytes(
        response.bodyBytes,
        format: format,
        coreAdapter: coreAdapter,
        uiAdapter: uiAdapter,
        manifestPath: manifestPath,
        uiPlugins: uiPlugins,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  /// JSON 格式的统一扩展清单。
  final String manifestSource;

  /// 以包内相对路径索引的 Core 模块源码。
  final Map<String, String> serviceModules;

  /// 以包内相对路径索引的 JSUI 模块源码。
  final Map<String, String> uiModules;

  /// JSUI 包声明的图片、字体等资源引用。
  final Map<String, QuickjsUiResourceReference> uiResources;

  /// JSUI 渲染所需的第三方插件。
  final List<QuickjsUiPlugin> uiPlugins;

  /// 已解析的统一扩展 manifest。
  QuickjsExtensionManifest get manifest =>
      QuickjsExtensionManifest.parse(manifestSource);

  /// 返回可持久化的源码 Map；第三方 UI 插件由宿主恢复时重新注入。
  Map<String, Object?> toMap() => <String, Object?>{
    'manifestSource': manifestSource,
    'serviceModules': serviceModules,
    'uiModules': uiModules,
    if (uiResources.isNotEmpty)
      'uiResources': <String, Object?>{
        for (final entry in uiResources.entries) entry.key: entry.value.toMap(),
      },
  };

  /// 复制包并重新注入第三方 JSUI 插件。
  QuickjsExtensionPackage copyWithUiPlugins(List<QuickjsUiPlugin> plugins) =>
      QuickjsExtensionPackage(
        manifestSource: manifestSource,
        serviceModules: serviceModules,
        uiModules: uiModules,
        uiResources: uiResources,
        uiPlugins: plugins,
      );

  /// 根据清单构建带扩展命名空间的 Core 插件。
  QuickjsPlugin buildServicePlugin(QuickjsExtensionManifest manifest) {
    final service = manifest.service;
    if (service == null) {
      throw StateError('Extension manifest has no service component');
    }
    if (!serviceModules.containsKey(service.entry)) {
      throw FormatException(
        'QuickJS extension service entry is missing: ${service.entry}',
      );
    }
    _validateModulePaths(serviceModules.keys, 'serviceModules');
    final namespacedEntry = '${manifest.id}/${service.entry}';
    return QuickjsPlugin.sources(
      manifest: QuickjsPluginManifest(
        id: manifest.id,
        version: manifest.version,
        entry: namespacedEntry,
        exports: <String>[...service.publicExports, ...service.uiExports],
        permissions: manifest.permissions,
        metadata: service.metadata,
      ),
      modules: <String, String>{
        for (final module in serviceModules.entries)
          '${manifest.id}/${module.key}': module.value,
      },
    );
  }

  /// 根据清单构建 JSUI 模块包。
  QuickjsUiBundle buildUiBundle(QuickjsExtensionManifest manifest) {
    final ui = manifest.ui;
    if (ui == null) {
      throw StateError('Extension manifest has no UI component');
    }
    _validateModulePaths(uiModules.keys, 'uiModules');
    for (final route in ui.routes.entries) {
      if (!uiModules.containsKey(route.value.entry)) {
        throw FormatException(
          'QuickJS extension UI route "${route.key}" entry is missing: '
          '${route.value.entry}',
        );
      }
    }
    return QuickjsUiBundle.compiled(
      id: manifest.id,
      version: manifest.version,
      entry: ui.routes.values.first.entry,
      modules: uiModules,
      permissions: manifest.permissions,
      resources: uiResources,
    );
  }
}

typedef _ModuleLoader = Future<String> Function(String path);
typedef _EntryPackageLoader =
    Future<QuickjsExtensionPackage> Function(
      String entry,
      _ModuleLoader loader,
    );

Future<QuickjsExtensionPackage> _loadCoreEntry({
  required String entry,
  required QuickjsCorePackageAdapter adapter,
  required _ModuleLoader loadModule,
}) async {
  final modules = <String, String>{};
  await _visitModules(entry, modules, loadModule);
  return QuickjsExtensionPackage(
    manifestSource: quickjsCoreAdapterManifest(adapter, entry).toJson(),
    serviceModules: modules,
  );
}

Future<QuickjsExtensionPackage> _loadUiEntry({
  required String entry,
  required QuickjsUiPackageAdapter adapter,
  required _ModuleLoader loadModule,
  required List<QuickjsUiPlugin> uiPlugins,
}) async {
  final modules = <String, String>{};
  await _visitModules(entry, modules, loadModule);
  return QuickjsExtensionPackage(
    manifestSource: quickjsUiAdapterManifest(adapter, entry).toJson(),
    uiModules: modules,
    uiPlugins: uiPlugins,
  );
}

Future<QuickjsExtensionPackage> _loadNetworkEntry({
  required Uri entryUrl,
  required http.Client? client,
  required _EntryPackageLoader load,
}) async {
  if (entryUrl.scheme != 'https' && entryUrl.scheme != 'http') {
    throw ArgumentError.value(entryUrl, 'entryUrl', 'must use HTTP or HTTPS');
  }
  final ownedClient = client == null;
  final resolvedClient = client ?? http.Client();
  final root = entryUrl.resolve('.');
  final entry = entryUrl.pathSegments.last;
  Future<String> loadModule(String path) async {
    final uri = root.resolve(path);
    if (!_isWithinNetworkRoot(root, uri)) {
      throw FormatException('Extension network path escapes root: $uri');
    }
    final response = await resolvedClient.get(uri);
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw http.ClientException(
        'Extension request failed with HTTP ${response.statusCode}',
        uri,
      );
    }
    return utf8.decode(response.bodyBytes);
  }

  try {
    return await load(entry, loadModule);
  } finally {
    if (ownedClient) resolvedClient.close();
  }
}

Future<void> _visitModules(
  String path,
  Map<String, String> target,
  _ModuleLoader loadModule,
) async {
  final normalized = _normalizePath(path);
  if (target.containsKey(normalized)) return;
  final source = await loadModule(normalized);
  target[normalized] = source;
  for (final importPath in quickjsUiStaticImports(source)) {
    if (!quickjsUiIsRelativeImport(importPath)) continue;
    await _visitModules(
      QuickjsUiResourceResolver.normalizePath(importPath, from: normalized),
      target,
      loadModule,
    );
  }
}

QuickjsExtensionPackage _fromCorePlugin(
  QuickjsPlugin plugin,
  QuickjsCorePackageAdapter adapter,
) {
  if (plugin.manifest.id != adapter.id) {
    throw FormatException(
      'Core ZIP id ${plugin.manifest.id} does not match adapter ${adapter.id}',
    );
  }
  final missingExports = <String>{
    ...adapter.publicExports,
    ...adapter.uiExports,
  }.difference(plugin.manifest.exports.toSet());
  if (missingExports.isNotEmpty) {
    throw FormatException(
      'Core ZIP does not export adapter methods: ${missingExports.join(', ')}',
    );
  }
  final prefix = '${plugin.manifest.id}/';
  final entry = plugin.manifest.entry.substring(prefix.length);
  final modules = <String, String>{};
  for (final module in plugin.modules) {
    final source = module.source;
    if (source == null) {
      throw const FormatException(
        'Core ZIP adapter requires decoded inline module sources',
      );
    }
    modules[module.specifier.substring(prefix.length)] = source;
  }
  return QuickjsExtensionPackage(
    manifestSource: quickjsCoreAdapterManifest(adapter, entry).toJson(),
    serviceModules: modules,
  );
}

QuickjsExtensionPackage _fromUiBundle(
  QuickjsUiBundle bundle,
  QuickjsUiPackageAdapter adapter,
  List<QuickjsUiPlugin> uiPlugins,
) {
  if (bundle.id != adapter.id) {
    throw FormatException(
      'JSUI package id ${bundle.id} does not match adapter ${adapter.id}',
    );
  }
  return QuickjsExtensionPackage(
    manifestSource: quickjsUiAdapterManifest(adapter, bundle.entry).toJson(),
    uiModules: bundle.modules,
    uiResources: bundle.resources,
    uiPlugins: uiPlugins,
  );
}

Future<QuickjsExtensionPackage> _loadDirectoryPackage({
  required String manifestSource,
  required _ModuleLoader loadModule,
  required List<QuickjsUiPlugin> uiPlugins,
}) async {
  final manifest = QuickjsExtensionManifest.parse(manifestSource);
  final serviceModules = <String, String>{};
  final uiModules = <String, String>{};

  Future<void> visit(String path, Map<String, String> target) async {
    await _visitModules(path, target, loadModule);
  }

  final service = manifest.service;
  if (service != null) await visit(service.entry, serviceModules);
  final ui = manifest.ui;
  if (ui != null) {
    for (final route in ui.routes.values) {
      await visit(route.entry, uiModules);
    }
  }
  return QuickjsExtensionPackage(
    manifestSource: manifestSource,
    serviceModules: serviceModules,
    uiModules: uiModules,
    uiPlugins: uiPlugins,
  );
}

MapEntry<String, Uint8List> _findZipManifest(
  Map<String, Uint8List> files,
  String? manifestPath,
) {
  if (manifestPath != null) {
    final normalized = _normalizePath(manifestPath);
    final bytes = files[normalized];
    if (bytes == null) {
      throw FormatException('Extension ZIP manifest is missing: $normalized');
    }
    return MapEntry<String, Uint8List>(normalized, bytes);
  }
  final candidates =
      files.entries
          .where((entry) => entry.key.split('/').last == 'manifest.json')
          .toList()
        ..sort((left, right) {
          final depth = left.key
              .split('/')
              .length
              .compareTo(right.key.split('/').length);
          return depth == 0 ? left.key.compareTo(right.key) : depth;
        });
  if (candidates.isEmpty) {
    throw const FormatException('Extension ZIP must contain manifest.json');
  }
  return candidates.first;
}

String _normalizePath(String path) =>
    QuickjsUiResourceResolver.normalizePath(path.replaceAll(r'\', '/'));

String _dirname(String path) {
  final slash = path.lastIndexOf('/');
  return slash < 0 ? '' : path.substring(0, slash);
}

String _basename(String path) => path.split('/').last;

bool _isWithinNetworkRoot(Uri root, Uri candidate) =>
    root.scheme == candidate.scheme &&
    root.host == candidate.host &&
    root.port == candidate.port &&
    candidate.path.startsWith(
      root.path.endsWith('/') ? root.path : '${root.path}/',
    );

String _join(String root, String path) =>
    root.isEmpty ? _normalizePath(path) : _normalizePath('$root/$path');

void _validateModulePaths(Iterable<String> paths, String name) {
  for (final path in paths) {
    if (path.startsWith('/') ||
        path.contains(r'\') ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException(
        'QuickJS extension $name contains an invalid package path: $path',
      );
    }
  }
}
