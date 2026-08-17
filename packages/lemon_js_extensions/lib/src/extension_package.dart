import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'extension_manifest.dart';
import 'extension_package_file.dart';
import 'extension_package_format.dart';

/// 尚未解析的扩展安装包。
final class JsExtensionPackage {
  /// 使用清单源码以及 Core、UI 模块创建内存安装包。
  JsExtensionPackage({
    required this.manifestSource,
    Map<String, String> serviceModules = const <String, String>{},
    Map<String, String> uiModules = const <String, String>{},
    Map<String, JsUiResourceReference> uiResources =
        const <String, JsUiResourceReference>{},
    Map<String, Uint8List> resourceFiles = const <String, Uint8List>{},
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) : serviceModules = Map<String, String>.unmodifiable(serviceModules),
       uiModules = Map<String, String>.unmodifiable(uiModules),
       uiResources = Map<String, JsUiResourceReference>.unmodifiable(
         uiResources,
       ),
       resourceFiles = Map<String, Uint8List>.unmodifiable({
         for (final entry in resourceFiles.entries)
           entry.key: Uint8List.fromList(entry.value),
       }),
       uiPlugins = List<JsUiPlugin>.unmodifiable(uiPlugins) {
    _validateModulePaths(this.resourceFiles.keys, 'resourceFiles');
  }

  /// 从持久化 Map 恢复扩展包源码。
  factory JsExtensionPackage.fromMap(
    Map<String, Object?> map, {
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) => JsExtensionPackage(
    manifestSource: map['manifestSource']! as String,
    serviceModules: Map<String, String>.from(
      (map['serviceModules']! as Map).cast<String, String>(),
    ),
    uiModules: Map<String, String>.from(
      (map['uiModules']! as Map).cast<String, String>(),
    ),
    uiResources: <String, JsUiResourceReference>{
      for (final entry
          in ((map['uiResources'] as Map?) ?? const <String, Object?>{})
              .entries)
        entry.key as String: JsUiResourceReference.parse(
          entry.value,
          name: 'uiResources.${entry.key}',
        ),
    },
    resourceFiles: <String, Uint8List>{
      for (final entry
          in ((map['resourceFiles'] as Map?) ?? const <String, Object?>{})
              .entries)
        entry.key as String: base64Decode(entry.value! as String),
    },
    uiPlugins: uiPlugins,
  );

  /// 从 Flutter assets 中的统一清单和相邻模块加载扩展包。
  static Future<JsExtensionPackage> asset({
    required String manifestAsset,
    AssetBundle? bundle,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final assets = bundle ?? rootBundle;
    final normalizedManifest = _normalizePath(manifestAsset);
    final root = _dirname(normalizedManifest);
    return _loadDirectoryPackage(
      manifestSource: await assets.loadString(normalizedManifest),
      loadModule: (path) => assets.loadString(_join(root, path)),
      loadResource: (path) async {
        final data = await assets.load(_join(root, path));
        return data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes);
      },
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地目录中的统一清单和相邻模块加载扩展包。
  static Future<JsExtensionPackage> file({
    required String manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final normalizedManifest = _normalizePath(manifestPath);
    final root = _dirname(normalizedManifest);
    return _loadDirectoryPackage(
      manifestSource: await readJsExtensionFileString(normalizedManifest),
      loadModule: (path) => readJsExtensionFileString(_join(root, path)),
      loadResource: (path) => readJsExtensionFileBytes(_join(root, path)),
      uiPlugins: uiPlugins,
    );
  }

  /// 从网络清单和同一目录下的模块加载扩展包。
  static Future<JsExtensionPackage> network({
    required Uri manifestUrl,
    http.Client? client,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    final root = manifestUrl.resolve('.');
    Future<Uint8List> loadBytes(Uri uri) async {
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
      return response.bodyBytes;
    }

    try {
      return await _loadDirectoryPackage(
        manifestSource: utf8.decode(await loadBytes(manifestUrl)),
        loadModule: (path) async =>
            utf8.decode(await loadBytes(root.resolve(path))),
        loadResource: (path) => loadBytes(root.resolve(path)),
        uiPlugins: uiPlugins,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  /// 从 Flutter asset 裸入口递归加载旧 Core 或 JSUI 插件。
  ///
  /// [adapter] 的具体类型决定生成 Core 还是 UI 扩展。
  static Future<JsExtensionPackage> moduleAsset({
    required String path,
    required JsExtensionAdapter adapter,
    AssetBundle? bundle,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final assets = bundle ?? rootBundle;
    final entry = _normalizePath(path);
    final root = _dirname(entry);
    Future<String> loadModule(String path) =>
        assets.loadString(_join(root, path));
    return _loadModuleEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: loadModule,
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地文件裸入口递归加载旧 Core 或 JSUI 插件。
  static Future<JsExtensionPackage> moduleFile({
    required String path,
    required JsExtensionAdapter adapter,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final entry = _normalizePath(path);
    final root = _dirname(entry);
    Future<String> loadModule(String path) =>
        readJsExtensionFileString(_join(root, path));
    return _loadModuleEntry(
      entry: _basename(entry),
      adapter: adapter,
      loadModule: loadModule,
      uiPlugins: uiPlugins,
    );
  }

  /// 从网络裸入口递归加载旧 Core 或 JSUI 插件。
  static Future<JsExtensionPackage> moduleNetwork({
    required Uri url,
    required JsExtensionAdapter adapter,
    http.Client? client,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) => _loadNetworkEntry(
    url: url,
    client: client,
    load: (entry, loader) => _loadModuleEntry(
      entry: entry,
      adapter: adapter,
      loadModule: loader,
      uiPlugins: uiPlugins,
    ),
  );

  /// 从 Flutter asset 加载 ZIP；默认解析统一扩展格式。
  ///
  /// 解析旧 Core 或 UI 格式时，通过 [format] 指定格式并传入对应 adapter。
  static Future<JsExtensionPackage> assetZip({
    required String path,
    AssetBundle? bundle,
    JsExtensionPackageFormat format = JsExtensionPackageFormat.manifest,
    JsExtensionCoreAdapter? coreAdapter,
    JsExtensionUiAdapter? uiAdapter,
    String? manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async {
    final data = await (bundle ?? rootBundle).load(path);
    return zipBytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      format: format,
      coreAdapter: coreAdapter,
      uiAdapter: uiAdapter,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    );
  }

  /// 从本地文件加载 ZIP；默认解析统一扩展格式。
  ///
  /// 解析旧 Core 或 UI 格式时，通过 [format] 指定格式并传入对应 adapter。
  static Future<JsExtensionPackage> fileZip({
    required String path,
    JsExtensionPackageFormat format = JsExtensionPackageFormat.manifest,
    JsExtensionCoreAdapter? coreAdapter,
    JsExtensionUiAdapter? uiAdapter,
    String? manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async => zipBytes(
    await readJsExtensionFileBytes(path),
    format: format,
    coreAdapter: coreAdapter,
    uiAdapter: uiAdapter,
    manifestPath: manifestPath,
    uiPlugins: uiPlugins,
  );

  /// 从网络加载 ZIP；默认解析统一扩展格式。
  ///
  /// 解析旧 Core 或 UI 格式时，通过 [format] 指定格式并传入对应 adapter。
  static Future<JsExtensionPackage> networkZip({
    required Uri url,
    http.Client? client,
    JsExtensionPackageFormat format = JsExtensionPackageFormat.manifest,
    JsExtensionCoreAdapter? coreAdapter,
    JsExtensionUiAdapter? uiAdapter,
    String? manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
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
      return await zipBytes(
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

  /// 从内存字节加载 ZIP；默认解析统一扩展格式。
  ///
  /// 解析旧 Core 或 UI 格式时，通过 [format] 指定格式并传入对应 adapter。
  static Future<JsExtensionPackage> zipBytes(
    Uint8List bytes, {
    JsExtensionPackageFormat format = JsExtensionPackageFormat.manifest,
    JsExtensionCoreAdapter? coreAdapter,
    JsExtensionUiAdapter? uiAdapter,
    String? manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
  }) async => switch (format) {
    JsExtensionPackageFormat.manifest => _loadExtensionZipBytes(
      bytes,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    JsExtensionPackageFormat.core => _fromCorePlugin(
      JsZipPlugin.bytes(bytes, manifestPath: manifestPath),
      coreAdapter ?? (throw ArgumentError.notNull('coreAdapter')),
    ),
    JsExtensionPackageFormat.ui => _fromUiBundle(
      await JsUiBundle.archiveBytes(bytes),
      uiAdapter ?? (throw ArgumentError.notNull('uiAdapter')),
      uiPlugins,
    ),
  };

  static Future<JsExtensionPackage> _loadExtensionZipBytes(
    Uint8List bytes, {
    String? manifestPath,
    List<JsUiPlugin> uiPlugins = const <JsUiPlugin>[],
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
      loadResource: (path) async {
        final resolved = _join(root, path);
        final source = files[resolved];
        if (source == null) {
          throw FormatException('Extension ZIP resource is missing: $resolved');
        }
        return source;
      },
      additionalResources: <String, Uint8List>{
        for (final entry in files.entries)
          if (entry.key != manifestEntry.key &&
              _isWithinPackageRoot(root, entry.key) &&
              !_isJavaScriptPath(_relativeTo(root, entry.key)))
            _relativeTo(root, entry.key): entry.value,
      },
      uiPlugins: uiPlugins,
    );
  }

  /// JSON 格式的统一扩展清单。
  final String manifestSource;

  /// 以包内相对路径索引的 Core 模块源码。
  final Map<String, String> serviceModules;

  /// 以包内相对路径索引的 JSUI 模块源码。
  final Map<String, String> uiModules;

  /// JSUI 包声明的图片、字体等资源引用。
  final Map<String, JsUiResourceReference> uiResources;

  /// 随安装包持久化的非 JavaScript 资源字节，以包内相对路径索引。
  final Map<String, Uint8List> resourceFiles;

  /// JSUI 渲染所需的第三方插件。
  final List<JsUiPlugin> uiPlugins;

  /// 已解析的统一扩展 manifest。
  JsExtensionManifest get manifest => JsExtensionManifest.parse(manifestSource);

  /// 返回可持久化的源码 Map；第三方 UI 插件由宿主恢复时重新注入。
  Map<String, Object?> toMap() => <String, Object?>{
    'manifestSource': manifestSource,
    'serviceModules': serviceModules,
    'uiModules': uiModules,
    if (uiResources.isNotEmpty)
      'uiResources': <String, Object?>{
        for (final entry in uiResources.entries) entry.key: entry.value.toMap(),
      },
    if (resourceFiles.isNotEmpty)
      'resourceFiles': <String, String>{
        for (final entry in resourceFiles.entries)
          entry.key: base64Encode(entry.value),
      },
  };

  /// 复制包并重新注入第三方 JSUI 插件。
  JsExtensionPackage copyWithUiPlugins(List<JsUiPlugin> plugins) =>
      JsExtensionPackage(
        manifestSource: manifestSource,
        serviceModules: serviceModules,
        uiModules: uiModules,
        uiResources: uiResources,
        resourceFiles: resourceFiles,
        uiPlugins: plugins,
      );

  /// 根据清单构建带扩展命名空间的 Core 插件。
  JsPlugin buildServicePlugin(JsExtensionManifest manifest) {
    final service = manifest.service;
    if (service == null) {
      throw StateError('Extension manifest has no service component');
    }
    if (!serviceModules.containsKey(service.entry)) {
      throw FormatException(
        'JS extension service entry is missing: ${service.entry}',
      );
    }
    _validateModulePaths(serviceModules.keys, 'serviceModules');
    final namespacedEntry = '${manifest.id}/${service.entry}';
    return JsPlugin.sources(
      manifest: JsPluginManifest(
        id: manifest.id,
        version: manifest.version,
        entry: namespacedEntry,
        exports: <String>[
          ...service.publicExports,
          ...service.uiExports,
          if (service.storageMigrationExport != null)
            service.storageMigrationExport!,
        ],
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
  JsUiBundle buildUiBundle(JsExtensionManifest manifest) {
    final ui = manifest.ui;
    if (ui == null) {
      throw StateError('Extension manifest has no UI component');
    }
    _validateModulePaths(uiModules.keys, 'uiModules');
    for (final route in ui.routes.entries) {
      if (!uiModules.containsKey(route.value.entry)) {
        throw FormatException(
          'JS extension UI route "${route.key}" entry is missing: '
          '${route.value.entry}',
        );
      }
    }
    return JsUiBundle.sources(
      id: manifest.id,
      version: manifest.version,
      entry: ui.routes.values.first.entry,
      modules: uiModules,
      permissions: manifest.permissions,
      resources: <String, JsUiResourceReference>{
        ...uiResources,
        for (final entry in resourceFiles.entries)
          entry.key: _embeddedResource(entry.key, entry.value),
      },
    );
  }
}

typedef _ModuleLoader = Future<String> Function(String path);
typedef _ResourceLoader = Future<Uint8List> Function(String path);
typedef _EntryPackageLoader =
    Future<JsExtensionPackage> Function(String entry, _ModuleLoader loader);

Future<JsExtensionPackage> _loadModuleEntry({
  required String entry,
  required JsExtensionAdapter adapter,
  required Future<String> Function(String path) loadModule,
  required List<JsUiPlugin> uiPlugins,
}) => switch (adapter) {
  JsExtensionCoreAdapter() => _loadCoreEntry(
    entry: entry,
    adapter: adapter,
    loadModule: loadModule,
  ),
  JsExtensionUiAdapter() => _loadUiEntry(
    entry: entry,
    adapter: adapter,
    loadModule: loadModule,
    uiPlugins: uiPlugins,
  ),
};
Future<JsExtensionPackage> _loadCoreEntry({
  required String entry,
  required JsExtensionCoreAdapter adapter,
  required _ModuleLoader loadModule,
}) async {
  final modules = <String, String>{};
  await _visitModules(entry, modules, loadModule);
  return JsExtensionPackage(
    manifestSource: adapter.buildManifest(entry).toJson(),
    serviceModules: modules,
  );
}

Future<JsExtensionPackage> _loadUiEntry({
  required String entry,
  required JsExtensionUiAdapter adapter,
  required _ModuleLoader loadModule,
  required List<JsUiPlugin> uiPlugins,
}) async {
  final modules = <String, String>{};
  await _visitModules(entry, modules, loadModule);
  return JsExtensionPackage(
    manifestSource: adapter.buildManifest(entry).toJson(),
    uiModules: modules,
    uiPlugins: uiPlugins,
  );
}

Future<JsExtensionPackage> _loadNetworkEntry({
  required Uri url,
  required http.Client? client,
  required _EntryPackageLoader load,
}) async {
  if (url.scheme != 'https' && url.scheme != 'http') {
    throw ArgumentError.value(url, 'url', 'must use HTTP or HTTPS');
  }
  final ownedClient = client == null;
  final resolvedClient = client ?? http.Client();
  final root = url.resolve('.');
  final entry = url.pathSegments.last;
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
  for (final importPath in jsUiStaticImports(source)) {
    if (!jsUiIsRelativeImport(importPath)) continue;
    await _visitModules(
      JsUiResourceResolver.normalizePath(importPath, from: normalized),
      target,
      loadModule,
    );
  }
}

JsExtensionPackage _fromCorePlugin(
  JsPlugin plugin,
  JsExtensionCoreAdapter adapter,
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
    modules[module.name.substring(prefix.length)] = source;
  }
  return JsExtensionPackage(
    manifestSource: adapter.buildManifest(entry).toJson(),
    serviceModules: modules,
  );
}

JsExtensionPackage _fromUiBundle(
  JsUiBundle bundle,
  JsExtensionUiAdapter adapter,
  List<JsUiPlugin> uiPlugins,
) {
  if (bundle.id != adapter.id) {
    throw FormatException(
      'JSUI package id ${bundle.id} does not match adapter ${adapter.id}',
    );
  }
  return JsExtensionPackage(
    manifestSource: adapter.buildManifest(bundle.entry).toJson(),
    uiModules: bundle.modules,
    uiResources: bundle.resources,
    uiPlugins: uiPlugins,
  );
}

Future<JsExtensionPackage> _loadDirectoryPackage({
  required String manifestSource,
  required _ModuleLoader loadModule,
  required _ResourceLoader loadResource,
  Map<String, Uint8List> additionalResources = const <String, Uint8List>{},
  required List<JsUiPlugin> uiPlugins,
}) async {
  final manifest = JsExtensionManifest.parse(manifestSource);
  final serviceModules = <String, String>{};
  final uiModules = <String, String>{};
  final resourceFiles = <String, Uint8List>{...additionalResources};

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
  for (final path in manifest.resources) {
    resourceFiles[path] = await loadResource(path);
  }
  return JsExtensionPackage(
    manifestSource: manifestSource,
    serviceModules: serviceModules,
    uiModules: uiModules,
    resourceFiles: resourceFiles,
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
    JsUiResourceResolver.normalizePath(path.replaceAll(r'\', '/'));

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

String _relativeTo(String root, String path) {
  if (root.isEmpty) return path;
  final prefix = '$root/';
  if (!path.startsWith(prefix)) {
    throw FormatException('Extension ZIP entry escapes package root: $path');
  }
  return path.substring(prefix.length);
}

bool _isWithinPackageRoot(String root, String path) =>
    root.isEmpty || path.startsWith('$root/');

bool _isJavaScriptPath(String path) =>
    path.endsWith('.js') || path.endsWith('.mjs') || path.endsWith('.cjs');

JsUiResourceReference _embeddedResource(String path, Uint8List bytes) {
  final mimeType = _mimeType(path);
  return JsUiResourceReference(
    uri: 'data:$mimeType;base64,${base64Encode(bytes)}',
    kind: JsUiResourceKind.data,
    mimeType: mimeType,
  );
}

String _mimeType(String path) => switch (path.toLowerCase().split('.').last) {
  'png' => 'image/png',
  'jpg' || 'jpeg' => 'image/jpeg',
  'gif' => 'image/gif',
  'webp' => 'image/webp',
  'svg' => 'image/svg+xml',
  'json' => 'application/json',
  'ttf' => 'font/ttf',
  'otf' => 'font/otf',
  'woff' => 'font/woff',
  'woff2' => 'font/woff2',
  'mp3' => 'audio/mpeg',
  'mp4' => 'video/mp4',
  _ => 'application/octet-stream',
};

void _validateModulePaths(Iterable<String> paths, String name) {
  for (final path in paths) {
    if (path.startsWith('/') ||
        path.contains(r'\') ||
        path
            .split('/')
            .any((part) => part.isEmpty || part == '.' || part == '..')) {
      throw FormatException(
        'JS extension $name contains an invalid package path: $path',
      );
    }
  }
}
