import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';
import 'quickjs_runtime_options.dart';

/// Minimal execution contract shared by standalone engines and child contexts.
abstract interface class JsPluginHost {
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout});

  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  });

  Future<Object?> callPlugin(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  });

  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout});
}

/// Manifest describing a JavaScript plugin contract.
final class JsPluginManifest {
  const JsPluginManifest({
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

/// One ES module inside a [JsPlugin].
final class JsPluginModule {
  const JsPluginModule({required this.specifier, required this.source})
    : assetKey = null,
      bundle = null;

  const JsPluginModule.asset({
    required this.specifier,
    required this.assetKey,
    this.bundle,
  }) : source = null;

  factory JsPluginModule.bytes({
    required String specifier,
    required Uint8List bytes,
    Encoding encoding = utf8,
  }) {
    return JsPluginModule(specifier: specifier, source: encoding.decode(bytes));
  }

  final String specifier;
  final String? source;
  final String? assetKey;
  final AssetBundle? bundle;

  JsModule toHostModule() {
    final inlineSource = source;
    if (inlineSource != null) {
      return JsModule.esModule(specifier: specifier, source: inlineSource);
    }
    final key = assetKey;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS plugin module "$specifier" has no source or assetKey',
      );
    }
    return JsModule.esModuleAsset(
      specifier: specifier,
      assetKey: key,
      bundle: bundle,
    );
  }
}

/// Explicit plugin package made from a manifest and a module graph.
final class JsPlugin {
  JsPlugin({required this.manifest, required List<JsPluginModule> modules})
    : modules = List<JsPluginModule>.unmodifiable(modules) {
    _validatePlugin();
  }

  factory JsPlugin.singleFile({
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
    return JsPlugin(
      manifest: JsPluginManifest(
        id: id,
        version: version,
        entry: entry,
        exports: exports,
        init: init,
        dispose: dispose,
        permissions: permissions,
        metadata: metadata,
      ),
      modules: <JsPluginModule>[
        JsPluginModule(specifier: entry, source: source),
      ],
    );
  }

  factory JsPlugin.singleFileAsset({
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
  }) {
    final entry = '$id/$entryName';
    return JsPlugin(
      manifest: JsPluginManifest(
        id: id,
        version: version,
        entry: entry,
        exports: exports,
        init: init,
        dispose: dispose,
        permissions: permissions,
        metadata: metadata,
      ),
      modules: <JsPluginModule>[
        JsPluginModule.asset(
          specifier: entry,
          assetKey: assetKey,
          bundle: bundle,
        ),
      ],
    );
  }

  factory JsPlugin.asset({
    required JsPluginManifest manifest,
    required Map<String, String> modules,
    AssetBundle? bundle,
  }) {
    return JsPlugin(
      manifest: manifest,
      modules: <JsPluginModule>[
        for (final entry in modules.entries)
          JsPluginModule.asset(
            specifier: entry.key,
            assetKey: entry.value,
            bundle: bundle,
          ),
      ],
    );
  }

  /// Creates a multi-module plugin from inline JavaScript sources.
  ///
  /// The [modules] map uses module specifiers as keys and JavaScript source
  /// values.
  factory JsPlugin.sources({
    required JsPluginManifest manifest,
    required Map<String, String> modules,
  }) {
    return JsPlugin(
      manifest: manifest,
      modules: <JsPluginModule>[
        for (final entry in modules.entries)
          JsPluginModule(specifier: entry.key, source: entry.value),
      ],
    );
  }

  final JsPluginManifest manifest;
  final List<JsPluginModule> modules;

  /// Converts this plugin into a normal host features.
  JsPluginFeatures asFeatures({String? name}) {
    return JsPluginFeatures(
      name: name ?? 'plugin:${manifest.id}',
      plugin: this,
      modules: <JsModule>[for (final module in modules) module.toHostModule()],
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

/// Host features that preserves the plugin manifest for runtime-level lookup.
final class JsPluginFeatures extends JsFeatures {
  const JsPluginFeatures({
    required super.name,
    required this.plugin,
    super.browserGlobals,
    super.scripts,
    super.modules,
    super.providers,
  });

  final JsPlugin plugin;
}
