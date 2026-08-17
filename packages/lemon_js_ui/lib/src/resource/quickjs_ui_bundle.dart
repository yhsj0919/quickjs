import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:lemon_js/lemon_js.dart';

import '../runtime/quickjs_ui_page_plugin.dart';
import 'quickjs_ui_file_bytes.dart';
import 'quickjs_ui_manifest.dart';
import 'quickjs_ui_network_cache_store.dart';
import 'quickjs_ui_network_loader.dart';
import 'quickjs_ui_resource.dart';
import 'quickjs_ui_resource_resolver.dart';

/// A validated set of JavaScript modules and resources for one JSUI page.
final class JsUiBundle {
  /// Creates a bundle from validated module sources.
  const JsUiBundle({
    required this.id,
    required this.version,
    required this.entry,
    required this.modules,
    this.permissions = const <String>[],
    this.resources = const <String, JsUiResourceReference>{},
  });

  /// Stable bundle or plugin identifier.
  final String id;

  /// Bundle version exposed through the generated plugin manifest.
  final String version;

  /// Normalized entry-module path.
  final String entry;

  /// JavaScript source keyed by normalized module path.
  final Map<String, String> modules;

  /// Host permissions requested by the bundle.
  final List<String> permissions;

  /// Non-module resources declared by the bundle.
  final Map<String, JsUiResourceReference> resources;

  /// Required entry path for manifest packages.
  static const String packageEntry = jsUiPackageEntry;

  /// Conventional manifest file name for packages.
  static const String packageManifest = jsUiPackageManifest;

  /// Recursively loads an entry and relative imports from Flutter assets.
  static Future<JsUiBundle> asset({
    required String path,
    String? id,
    String version = '0.2.0',
    String? bundleRoot,
    AssetBundle? bundle,
  }) async {
    final resolved = _resolveAssetPath(path, bundleRoot: bundleRoot);
    final resolver = JsUiResourceResolver.asset(
      bundle: bundle,
      basePath: '${resolved.root}/',
    );
    return loadEntry(
      id: id ?? _bundleIdFromAssetPath(path),
      version: version,
      entry: resolved.entry,
      resolver: resolver,
    );
  }

  /// Creates a bundle from module sources already available in Dart.
  ///
  /// This is the synchronous counterpart for build-generated bundles. The
  /// [modules] map uses normalized bundle-relative module paths as keys and
  /// JavaScript source as values.
  static JsUiBundle sources({
    required String id,
    required String version,
    required String entry,
    required Map<String, String> modules,
    List<String> permissions = const <String>[],
    Map<String, JsUiResourceReference> resources =
        const <String, JsUiResourceReference>{},
  }) {
    final normalizedEntry = JsUiResourceResolver.normalizePath(entry);
    final normalizedModules = <String, String>{
      for (final module in modules.entries)
        JsUiResourceResolver.normalizePath(module.key): module.value,
    };
    if (!normalizedModules.containsKey(normalizedEntry)) {
      throw FormatException(
        'quickjs_ui compiled bundle entry is missing: $normalizedEntry',
      );
    }
    return JsUiBundle(
      id: id,
      version: version,
      entry: normalizedEntry,
      modules: Map<String, String>.unmodifiable(normalizedModules),
      permissions: permissions,
      resources: resources,
    );
  }

  /// Recursively loads an entry and relative imports from local files.
  static Future<JsUiBundle> file({
    required String path,
    String? id,
    String version = '0.2.0',
    String? bundleRoot,
  }) async {
    final resolved = _resolveAssetPath(path, bundleRoot: bundleRoot);
    final resolver = JsUiResourceResolver.file(basePath: resolved.root);
    return loadEntry(
      id: id ?? _bundleIdFromAssetPath(path),
      version: version,
      entry: resolved.entry,
      resolver: resolver,
    );
  }

  /// Recursively loads an entry and relative imports over the network.
  static Future<JsUiBundle> network({
    required Uri url,
    String? id,
    String version = '0.2.0',
    Uri? bundleRoot,
    JsUiNetworkFetch? fetch,
    JsUiNetworkLogHandler? onLog,
  }) {
    return JsUiNetworkLoader(
      fetch: fetch,
      onLog: onLog,
    ).load(url: url, id: id, version: version, bundleRoot: bundleRoot);
  }

  /// Loads a manifest package from a Flutter asset directory.
  static Future<JsUiBundle> packageAsset({
    required String root,
    AssetBundle? bundle,
  }) async {
    final resolver = JsUiResourceResolver.asset(
      bundle: bundle,
      basePath: _packageAssetManifestKey(root),
    );
    final manifestSource = await resolver.loadString(packageManifest);
    return loadManifest(
      manifestSource,
      resolver: resolver,
      validatePackageRoot: true,
    );
  }

  /// Loads a manifest package from a local directory.
  static Future<JsUiBundle> packageFile({required String root}) async {
    final resolver = JsUiResourceResolver.file(basePath: root);
    final manifestSource = await resolver.loadString(packageManifest);
    return loadManifest(
      manifestSource,
      resolver: resolver,
      validatePackageRoot: true,
    );
  }

  /// Loads a ZIP package from a Flutter asset.
  static Future<JsUiBundle> archiveAsset({
    required String path,
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).load(path);
    return archiveBytes(data.buffer.asUint8List());
  }

  /// Loads a ZIP package from a local file.
  static Future<JsUiBundle> archiveFile({required String path}) async {
    return archiveBytes(await readJsUiFileBytes(path));
  }

  /// Loads a ZIP package from in-memory bytes.
  static Future<JsUiBundle> archiveBytes(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final normalized = JsUiResourceResolver.normalizePath(file.name);
      files[normalized] = _archiveFileBytes(file);
    }
    final manifestBytes = files[packageManifest];
    if (manifestBytes == null) {
      throw const FormatException(
        'quickjs_ui zip package missing manifest.json',
      );
    }
    final manifest = JsUiManifest.parse(utf8.decode(manifestBytes))
      ..validatePackageRoot();
    final modules = <String, String>{};
    for (final module in manifest.modules.entries) {
      final moduleBytes = files[module.value.loadPath];
      if (moduleBytes == null) {
        throw FormatException(
          'quickjs_ui zip package missing module: ${module.value.loadPath}',
        );
      }
      final moduleSource = utf8.decode(moduleBytes);
      module.value.verifySource(moduleSource);
      modules[module.key] = moduleSource;
    }
    manifest.validateImports(modules);
    return JsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(modules),
      permissions: manifest.permissions,
      resources: manifest.resources,
    );
  }

  /// Loads a manifest package from a network directory.
  static Future<JsUiBundle> packageNetwork({
    required Uri root,
    JsUiNetworkFetch? fetch,
    JsUiNetworkLogHandler? onLog,
    JsUiNetworkCacheStore? cacheStore,
    JsUiNetworkRefreshMode refreshMode = JsUiNetworkRefreshMode.conditional,
    JsUiNetworkCacheBuster? cacheBuster,
  }) {
    return JsUiNetworkLoader(
      fetch: fetch,
      onLog: onLog,
      cacheStore: cacheStore,
      cacheBuster: cacheBuster,
    ).loadPackage(root: root, refreshMode: refreshMode);
  }

  /// Recursively loads an entry module and its relative imports.
  static Future<JsUiBundle> loadEntry({
    required String id,
    required String version,
    required String entry,
    required JsUiResourceResolver resolver,
  }) async {
    final normalizedEntry = JsUiResourceResolver.normalizePath(entry);
    final modules = <String, String>{};
    Future<void> visit(String modulePath) async {
      final normalized = JsUiResourceResolver.normalizePath(modulePath);
      if (modules.containsKey(normalized)) {
        return;
      }
      final source = await resolver.loadString(normalized);
      modules[normalized] = source;
      for (final importPath in jsUiStaticImports(source)) {
        if (!jsUiIsRelativeImport(importPath)) {
          continue;
        }
        await visit(
          JsUiResourceResolver.normalizePath(importPath, from: normalized),
        );
      }
    }

    await visit(normalizedEntry);
    return JsUiBundle(
      id: id,
      version: version,
      entry: normalizedEntry,
      modules: Map<String, String>.unmodifiable(modules),
    );
  }

  /// Loads a manifest file and its declared modules from Flutter assets.
  static Future<JsUiBundle> manifestAsset({
    required String path,
    AssetBundle? bundle,
  }) async {
    final resolver = JsUiResourceResolver.asset(bundle: bundle, basePath: path);
    final source = await (bundle ?? rootBundle).loadString(path);
    return loadManifest(source, resolver: resolver);
  }

  /// Parses [source] and loads its declared modules through [resolver].
  static Future<JsUiBundle> loadManifest(
    String source, {
    required JsUiResourceResolver resolver,
    bool validatePackageRoot = false,
  }) async {
    final manifest = JsUiManifest.parse(source);
    if (validatePackageRoot) {
      manifest.validatePackageRoot();
    }
    final modules = <String, String>{};
    for (final module in manifest.modules.entries) {
      final moduleSource = await resolver.loadString(module.value.loadPath);
      module.value.verifySource(moduleSource);
      modules[module.key] = moduleSource;
    }
    manifest.validateImports(modules);
    return JsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(modules),
      resources: manifest.resources,
      permissions: manifest.permissions,
    );
  }

  /// Creates a package bundle from a manifest and module sources in Dart.
  ///
  /// [modules] may be keyed by manifest module path or by its `source` load
  /// path. All manifest modules must be present.
  static JsUiBundle fromManifest({
    required String manifestSource,
    required Map<String, String> modules,
    bool validatePackageRoot = false,
  }) {
    final manifest = JsUiManifest.parse(manifestSource);
    if (validatePackageRoot) {
      manifest.validatePackageRoot();
    }
    final normalizedSources = <String, String>{
      for (final module in modules.entries)
        JsUiResourceResolver.normalizePath(module.key): module.value,
    };
    final loadedModules = <String, String>{};
    for (final module in manifest.modules.entries) {
      final source =
          normalizedSources[module.key] ??
          normalizedSources[module.value.loadPath];
      if (source == null) {
        throw FormatException(
          'quickjs_ui compiled package missing module: ${module.key}',
        );
      }
      module.value.verifySource(source);
      loadedModules[module.key] = source;
    }
    manifest.validateImports(loadedModules);
    return JsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(loadedModules),
      resources: manifest.resources,
      permissions: manifest.permissions,
    );
  }

  /// Converts this bundle into an installable Lemon JS page plugin.
  JsPlugin toPlugin() {
    final entrySpecifier = JsUiResourceResolver.moduleSpecifier(id, entry);
    final adapterSpecifier = '$id/__js_ui_adapter__';
    return JsPlugin(
      manifest: JsPluginManifest(
        id: id,
        version: version,
        entry: adapterSpecifier,
        exports: jsUiPagePluginExports,
        permissions: permissions,
      ),
      modules: <JsPluginModule>[
        for (final module in modules.entries)
          JsPluginModule(
            name: JsUiResourceResolver.moduleSpecifier(id, module.key),
            source: module.value,
          ),
        JsPluginModule(
          name: adapterSpecifier,
          source: JsUiPagePlugin.adapterSource(entrySpecifier),
        ),
      ],
    );
  }
}

_ResolvedAssetPath _resolveAssetPath(String path, {String? bundleRoot}) {
  final normalizedPath = path.replaceAll('\\', '/');
  final root =
      bundleRoot?.replaceAll('\\', '/') ?? _inferBundleRoot(normalizedPath);
  if (root.isEmpty) {
    return _ResolvedAssetPath(root: '', entry: normalizedPath);
  }
  final prefix = root.endsWith('/') ? root : '$root/';
  if (!normalizedPath.startsWith(prefix)) {
    throw FormatException(
      'quickjs_ui asset path must be inside bundleRoot: $path',
    );
  }
  return _ResolvedAssetPath(
    root: root,
    entry: normalizedPath.substring(prefix.length),
  );
}

String _inferBundleRoot(String path) {
  final pagesIndex = path.lastIndexOf('/pages/');
  if (pagesIndex > 0) {
    return path.substring(0, pagesIndex);
  }
  final index = path.lastIndexOf('/');
  if (index == -1) {
    return '';
  }
  return path.substring(0, index);
}

String _bundleIdFromAssetPath(String path) {
  final sanitized = path
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return 'quickjs_ui_$sanitized';
}

String _packageAssetManifestKey(String root) {
  final normalized = root.replaceAll('\\', '/');
  final prefix = normalized.isEmpty || normalized.endsWith('/')
      ? normalized
      : '$normalized/';
  return '$prefix${JsUiBundle.packageManifest}';
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  return file.content;
}

final class _ResolvedAssetPath {
  const _ResolvedAssetPath({required this.root, required this.entry});

  final String root;
  final String entry;
}
