import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

import '../runtime/quickjs_ui_page_plugin.dart';
import 'quickjs_ui_network_loader.dart';
import 'quickjs_ui_resource_resolver.dart';

final class QuickjsUiBundle {
  const QuickjsUiBundle({
    required this.id,
    required this.version,
    required this.entry,
    required this.modules,
  });

  final String id;
  final String version;
  final String entry;
  final Map<String, String> modules;

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
      for (final importPath in _staticImports(source)) {
        if (!_isRelativeImport(importPath)) {
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
  }) async {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'quickjs_ui bundle manifest must be an object',
      );
    }
    final manifest = decoded.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final id = _string(manifest['id'], 'id');
    final version = _string(manifest['version'], 'version');
    final entry = QuickjsUiResourceResolver.normalizePath(
      _string(manifest['entry'], 'entry'),
    );
    final moduleResources = _moduleResources(manifest['modules']);
    if (!moduleResources.containsKey(entry)) {
      throw FormatException(
        'quickjs_ui bundle entry must be listed in modules: $entry',
      );
    }
    final modules = <String, String>{};
    for (final module in moduleResources.entries) {
      modules[module.key] = await resolver.loadString(module.value);
    }
    return QuickjsUiBundle(
      id: id,
      version: version,
      entry: entry,
      modules: Map<String, String>.unmodifiable(modules),
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
        exports: const <String>['render', 'dispatch'],
        init: 'init',
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

String _string(Object? value, String name) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('quickjs_ui bundle manifest "$name" must be a string');
}

Map<String, String> _moduleResources(Object? value) {
  if (value is List) {
    return Map<String, String>.unmodifiable(<String, String>{
      for (final item in value)
        QuickjsUiResourceResolver.normalizePath(_string(item, 'modules[]')):
            QuickjsUiResourceResolver.normalizePath(_string(item, 'modules[]')),
    });
  }
  if (value is Map) {
    return Map<String, String>.unmodifiable(
      value.map((key, value) {
        return MapEntry<String, String>(
          QuickjsUiResourceResolver.normalizePath('$key'),
          QuickjsUiResourceResolver.normalizePath(
            _string(value, 'modules.$key'),
          ),
        );
      }),
    );
  }
  throw const FormatException(
    'quickjs_ui bundle manifest "modules" must be an array or object',
  );
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

bool _isRelativeImport(String specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../');
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

final class _ResolvedAssetPath {
  const _ResolvedAssetPath({required this.root, required this.entry});

  final String root;
  final String entry;
}
