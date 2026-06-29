import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';
import 'quickjs_runtime_options.dart';

/// Manifest describing a JavaScript plugin contract.
final class QuickjsPluginManifest {
  const QuickjsPluginManifest({
    required this.id,
    required this.version,
    required this.entry,
    required this.exports,
    this.init,
    this.dispose,
    this.permissions = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  /// Plugin namespace and stable identifier, such as `api1`.
  final String id;

  /// Application-defined plugin version.
  final String version;

  /// Entry ES module specifier, such as `api1/main`.
  final String entry;

  /// Exported function names callable from Dart.
  final List<String> exports;

  /// Optional lifecycle export called by [Quickjs.initPlugin].
  final String? init;

  /// Optional lifecycle export called by [Quickjs.disposePlugin].
  final String? dispose;

  /// Optional application-defined permission labels.
  final List<String> permissions;

  /// Optional application-defined metadata.
  final Map<String, Object?> metadata;
}

/// One ES module inside a [QuickjsPlugin].
final class QuickjsPluginModule {
  const QuickjsPluginModule({required this.specifier, required this.source});

  factory QuickjsPluginModule.bytes({
    required String specifier,
    required Uint8List bytes,
    Encoding encoding = utf8,
  }) {
    return QuickjsPluginModule(
      specifier: specifier,
      source: encoding.decode(bytes),
    );
  }

  final String specifier;
  final String source;
}

/// Explicit plugin package made from a manifest and a module graph.
final class QuickjsPlugin {
  QuickjsPlugin({
    required this.manifest,
    required List<QuickjsPluginModule> modules,
  }) : modules = List<QuickjsPluginModule>.unmodifiable(modules) {
    _validatePlugin();
  }

  factory QuickjsPlugin.singleFile({
    required String id,
    required String version,
    required String source,
    required List<String> exports,
    String? init,
    String? dispose,
    List<String> permissions = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
    String entryName = 'main',
  }) {
    final entry = '$id/$entryName';
    return QuickjsPlugin(
      manifest: QuickjsPluginManifest(
        id: id,
        version: version,
        entry: entry,
        exports: exports,
        init: init,
        dispose: dispose,
        permissions: permissions,
        metadata: metadata,
      ),
      modules: <QuickjsPluginModule>[
        QuickjsPluginModule(specifier: entry, source: source),
      ],
    );
  }

  static Future<QuickjsPlugin> singleFileAsset({
    required String id,
    required String version,
    required String assetKey,
    required List<String> exports,
    String? init,
    String? dispose,
    AssetBundle? bundle,
    List<String> permissions = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
    String entryName = 'main',
  }) async {
    final source = await (bundle ?? rootBundle).loadString(assetKey);
    return QuickjsPlugin.singleFile(
      id: id,
      version: version,
      source: source,
      exports: exports,
      init: init,
      dispose: dispose,
      permissions: permissions,
      metadata: metadata,
      entryName: entryName,
    );
  }

  static Future<QuickjsPlugin> asset({
    required QuickjsPluginManifest manifest,
    required Map<String, String> modules,
    AssetBundle? bundle,
  }) async {
    final resolvedBundle = bundle ?? rootBundle;
    final loadedModules = <QuickjsPluginModule>[];
    for (final entry in modules.entries) {
      loadedModules.add(
        QuickjsPluginModule(
          specifier: entry.key,
          source: await resolvedBundle.loadString(entry.value),
        ),
      );
    }
    return QuickjsPlugin(manifest: manifest, modules: loadedModules);
  }

  final QuickjsPluginManifest manifest;
  final List<QuickjsPluginModule> modules;

  /// Converts this plugin into a normal host mount.
  QuickjsPluginMount asMount({String? name}) {
    return QuickjsPluginMount(
      name: name ?? 'plugin:${manifest.id}',
      plugin: this,
      modules: <QuickjsHostModule>[
        for (final module in modules)
          QuickjsHostModule.esModule(
            specifier: module.specifier,
            source: module.source,
          ),
      ],
    );
  }

  void _validatePlugin() {
    _validateNonEmpty('QuickJS plugin id', manifest.id);
    _validateNonEmpty('QuickJS plugin version', manifest.version);
    _validateNonEmpty('QuickJS plugin entry', manifest.entry);
    if (manifest.id.contains('/')) {
      throw JsValueConversionException(
        'QuickJS plugin id must be a namespace without slash: ${manifest.id}',
      );
    }
    _validateNamespaced(manifest.entry);
    if (manifest.exports.isEmpty) {
      throw JsValueConversionException(
        'QuickJS plugin manifest exports must not be empty: ${manifest.id}',
      );
    }
    final exportNames = <String>{};
    for (final exportName in manifest.exports) {
      _validateNonEmpty('QuickJS plugin export', exportName);
      if (!exportNames.add(exportName)) {
        throw JsValueConversionException(
          'QuickJS plugin export is declared more than once: $exportName',
        );
      }
    }
    final init = manifest.init;
    if (init != null) {
      _validateNonEmpty('QuickJS plugin init export', init);
    }
    final dispose = manifest.dispose;
    if (dispose != null) {
      _validateNonEmpty('QuickJS plugin dispose export', dispose);
    }

    final moduleNames = <String>{};
    var hasEntry = false;
    for (final module in modules) {
      _validateNonEmpty('QuickJS plugin module specifier', module.specifier);
      _validateNamespaced(module.specifier);
      if (!moduleNames.add(module.specifier)) {
        throw JsValueConversionException(
          'QuickJS plugin module is declared more than once: ${module.specifier}',
        );
      }
      if (module.specifier == manifest.entry) {
        hasEntry = true;
      }
    }
    if (!hasEntry) {
      throw JsValueConversionException(
        'QuickJS plugin entry module is missing: ${manifest.entry}',
      );
    }
  }

  void _validateNamespaced(String specifier) {
    if (!specifier.startsWith('${manifest.id}/')) {
      throw JsValueConversionException(
        'QuickJS plugin module must use namespace "${manifest.id}/": $specifier',
      );
    }
    if (specifier.contains('\u0000')) {
      throw JsValueConversionException(
        'QuickJS plugin module specifier must not contain NUL',
      );
    }
  }

  static void _validateNonEmpty(String label, String value) {
    if (value.isEmpty) {
      throw JsValueConversionException('$label must not be empty');
    }
    if (value.contains('\u0000')) {
      throw JsValueConversionException('$label must not contain NUL');
    }
  }
}

/// Host mount that preserves the plugin manifest for runtime-level lookup.
final class QuickjsPluginMount extends QuickjsHostMount {
  const QuickjsPluginMount({
    required super.name,
    required this.plugin,
    super.capabilities,
    super.environmentPatches,
    super.modules,
    super.providers,
  });

  final QuickjsPlugin plugin;
}
