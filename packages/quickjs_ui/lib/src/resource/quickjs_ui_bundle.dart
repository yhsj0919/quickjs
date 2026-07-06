import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

import '../runtime/quickjs_ui_page_plugin.dart';
import 'quickjs_ui_manifest.dart';
import 'quickjs_ui_network_cache_store.dart';
import 'quickjs_ui_network_loader.dart';
import 'quickjs_ui_resource.dart';
import 'quickjs_ui_resource_resolver.dart';

final class QuickjsUiBundle {
  const QuickjsUiBundle({
    required this.id,
    required this.version,
    required this.entry,
    required this.modules,
    this.permissions = const <String>[],
    this.resources = const <String, QuickjsUiResourceReference>{},
  });

  final String id;
  final String version;
  final String entry;
  final Map<String, String> modules;
  final List<String> permissions;
  final Map<String, QuickjsUiResourceReference> resources;

  static const String packageEntry = quickjsUiPackageEntry;
  static const String packageManifest = quickjsUiPackageManifest;

  static Future<QuickjsUiBundle> asset({
    required String path,
    String? id,
    String version = '0.2.0',
    String? bundleRoot,
    AssetBundle? bundle,
  }) async {
    final resolved = _resolveAssetPath(path, bundleRoot: bundleRoot);
    final resolver = QuickjsUiResourceResolver.asset(
      bundle: bundle,
      baseAssetKey: '${resolved.root}/',
    );
    return fromEntry(
      id: id ?? _bundleIdFromAssetPath(path),
      version: version,
      entry: resolved.entry,
      resolver: resolver,
    );
  }

  static Future<QuickjsUiBundle> file({
    required String path,
    String? id,
    String version = '0.2.0',
    String? bundleRoot,
  }) async {
    final resolved = _resolveAssetPath(path, bundleRoot: bundleRoot);
    final resolver = QuickjsUiResourceResolver.file(basePath: resolved.root);
    return fromEntry(
      id: id ?? _bundleIdFromAssetPath(path),
      version: version,
      entry: resolved.entry,
      resolver: resolver,
    );
  }

  static Future<QuickjsUiBundle> network({
    required Uri url,
    String? id,
    String version = '0.2.0',
    Uri? bundleRoot,
    QuickjsUiNetworkFetch? fetch,
    QuickjsUiNetworkLogHandler? onLog,
  }) {
    return QuickjsUiNetworkLoader(
      fetch: fetch,
      onLog: onLog,
    ).load(url: url, id: id, version: version, bundleRoot: bundleRoot);
  }

  static Future<QuickjsUiBundle> assetPackage({
    required String root,
    AssetBundle? bundle,
  }) async {
    final resolver = QuickjsUiResourceResolver.asset(
      bundle: bundle,
      baseAssetKey: _packageAssetManifestKey(root),
    );
    final manifestSource = await resolver.loadString(packageManifest);
    return fromManifestSource(
      manifestSource,
      resolver: resolver,
      validatePackageRoot: true,
    );
  }

  static Future<QuickjsUiBundle> filePackage({required String root}) async {
    final resolver = QuickjsUiResourceResolver.file(basePath: root);
    final manifestSource = await resolver.loadString(packageManifest);
    return fromManifestSource(
      manifestSource,
      resolver: resolver,
      validatePackageRoot: true,
    );
  }

  static Future<QuickjsUiBundle> assetZipPackage({
    required String assetKey,
    AssetBundle? bundle,
  }) async {
    final data = await (bundle ?? rootBundle).load(assetKey);
    return zipPackageBytes(data.buffer.asUint8List());
  }

  static Future<QuickjsUiBundle> fileZipPackage({required String path}) async {
    return zipPackageBytes(await File(path).readAsBytes());
  }

  static Future<QuickjsUiBundle> zipPackageBytes(List<int> bytes) async {
    final archive = ZipDecoder().decodeBytes(bytes);
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final normalized = QuickjsUiResourceResolver.normalizePath(file.name);
      files[normalized] = _archiveFileBytes(file);
    }
    final manifestBytes = files[packageManifest];
    if (manifestBytes == null) {
      throw const FormatException(
        'quickjs_ui zip package missing manifest.json',
      );
    }
    final manifest = QuickjsUiManifest.parse(utf8.decode(manifestBytes))
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
    return QuickjsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(modules),
      permissions: manifest.permissions,
      resources: manifest.resources,
    );
  }

  static Future<QuickjsUiBundle> networkPackage({
    required Uri root,
    QuickjsUiNetworkFetch? fetch,
    QuickjsUiNetworkLogHandler? onLog,
    QuickjsUiNetworkCacheStore? cacheStore,
    QuickjsUiNetworkRefreshMode refreshMode =
        QuickjsUiNetworkRefreshMode.conditional,
    QuickjsUiNetworkCacheBuster? cacheBuster,
  }) {
    return QuickjsUiNetworkLoader(
      fetch: fetch,
      onLog: onLog,
      cacheStore: cacheStore,
      cacheBuster: cacheBuster,
    ).loadPackageWithRefresh(root: root, refreshMode: refreshMode);
  }

  static Future<QuickjsUiBundle> fromEntry({
    required String id,
    required String version,
    required String entry,
    required QuickjsUiResourceResolver resolver,
  }) async {
    final normalizedEntry = QuickjsUiResourceResolver.normalizePath(entry);
    final modules = <String, String>{};
    Future<void> visit(String modulePath) async {
      final normalized = QuickjsUiResourceResolver.normalizePath(modulePath);
      if (modules.containsKey(normalized)) {
        return;
      }
      final source = await resolver.loadString(normalized);
      modules[normalized] = source;
      for (final importPath in quickjsUiStaticImports(source)) {
        if (!quickjsUiIsRelativeImport(importPath)) {
          continue;
        }
        await visit(
          QuickjsUiResourceResolver.normalizePath(importPath, from: normalized),
        );
      }
    }

    await visit(normalizedEntry);
    return QuickjsUiBundle(
      id: id,
      version: version,
      entry: normalizedEntry,
      modules: Map<String, String>.unmodifiable(modules),
    );
  }

  static Future<QuickjsUiBundle> manifestAsset({
    required String manifestAsset,
    AssetBundle? bundle,
  }) async {
    final resolver = QuickjsUiResourceResolver.asset(
      bundle: bundle,
      baseAssetKey: manifestAsset,
    );
    final source = await (bundle ?? rootBundle).loadString(manifestAsset);
    return fromManifestSource(source, resolver: resolver);
  }

  static Future<QuickjsUiBundle> fromManifestSource(
    String source, {
    required QuickjsUiResourceResolver resolver,
    bool validatePackageRoot = false,
  }) async {
    final manifest = QuickjsUiManifest.parse(source);
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
    return QuickjsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(modules),
      resources: manifest.resources,
      permissions: manifest.permissions,
    );
  }

  QuickjsPlugin toPlugin() {
    final entrySpecifier = QuickjsUiResourceResolver.moduleSpecifier(id, entry);
    final adapterSpecifier = '$id/__quickjs_ui_adapter__';
    return QuickjsPlugin(
      manifest: QuickjsPluginManifest(
        id: id,
        version: version,
        entry: adapterSpecifier,
        exports: const <String>[
          'mount',
          'handleEvent',
          'commit',
          'setState',
          'lifecycle',
          'snapshot',
          'capabilities',
          'dispose',
        ],
        permissions: permissions,
      ),
      modules: <QuickjsPluginModule>[
        for (final module in modules.entries)
          QuickjsPluginModule(
            specifier: QuickjsUiResourceResolver.moduleSpecifier(
              id,
              module.key,
            ),
            source: module.value,
          ),
        QuickjsPluginModule(
          specifier: adapterSpecifier,
          source: QuickjsUiPagePlugin.adapterSource(entrySpecifier),
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
  return '$prefix${QuickjsUiBundle.packageManifest}';
}

Uint8List _archiveFileBytes(ArchiveFile file) {
  return file.content;
}

final class _ResolvedAssetPath {
  const _ResolvedAssetPath({required this.root, required this.entry});

  final String root;
  final String entry;
}
