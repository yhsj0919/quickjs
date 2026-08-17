import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/exception.dart';
import 'runtime_options.dart';

/// Minimal execution contract shared by standalone engines and child contexts.
abstract interface class JsPluginHost {
  /// Validates the plugin manifest, module graph, and declared exports.
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout});

  /// Calls the plugin's optional initialization export.
  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  });

  /// Calls one export declared by the supplied plugin.
  Future<Object?> callPluginExport(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  });

  /// Calls the plugin's optional disposal export.
  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout});
}

/// Manifest describing a JavaScript plugin contract.
final class JsPluginManifest {
  /// Creates a plugin contract manifest.
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

  /// Optional lifecycle export called by [JsEngine.initPlugin].
  final String? init;

  /// Optional lifecycle export called by [JsEngine.disposePlugin].
  final String? dispose;

  /// Optional application-defined permission labels.
  final List<String> permissions;

  /// Optional application-defined metadata.
  final Map<String, Object?> metadata;
}

/// One ES module inside a [JsPlugin].
final class JsPluginModule {
  /// Creates an inline ES module.
  const JsPluginModule({required this.name, required this.source})
    : path = null,
      bundle = null;

  /// Creates an ES module whose source is loaded from a Flutter asset.
  const JsPluginModule.asset({
    required this.name,
    required this.path,
    this.bundle,
  }) : source = null;

  /// Decodes [bytes] into an inline ES module using [encoding].
  factory JsPluginModule.bytes({
    required String name,
    required Uint8List bytes,
    Encoding encoding = utf8,
  }) {
    return JsPluginModule(name: name, source: encoding.decode(bytes));
  }

  /// Namespaced ES module name used by JavaScript imports.
  final String name;

  /// Inline JavaScript source, or `null` for an asset-backed module.
  final String? source;

  /// Flutter asset path, or `null` for an inline module.
  final String? path;

  /// Optional bundle used to load [path].
  final AssetBundle? bundle;

  /// Converts this plugin module to the runtime's host-module descriptor.
  JsModule toHostModule() {
    final inlineSource = source;
    if (inlineSource != null) {
      return JsModule(name: name, source: inlineSource);
    }
    final key = path;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS plugin module "$name" has no source or path',
      );
    }
    return JsModule.asset(name: name, path: key, bundle: bundle);
  }
}

/// Explicit plugin package made from a manifest and a module graph.
final class JsPlugin {
  /// Creates and validates an explicit plugin module graph.
  JsPlugin({required this.manifest, required List<JsPluginModule> modules})
    : modules = List<JsPluginModule>.unmodifiable(modules) {
    _validatePlugin();
  }

  /// Creates a single-module plugin from inline JavaScript [source].
  factory JsPlugin.source({
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
      modules: <JsPluginModule>[JsPluginModule(name: entry, source: source)],
    );
  }

  /// Creates a single-module plugin from one Flutter asset [path].
  factory JsPlugin.asset({
    required String id,
    required String version,
    required String path,
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
        JsPluginModule.asset(name: entry, path: path, bundle: bundle),
      ],
    );
  }

  /// Creates a multi-module plugin from module-name to asset-path mappings.
  factory JsPlugin.assets({
    required JsPluginManifest manifest,
    required Map<String, String> modules,
    AssetBundle? bundle,
  }) {
    return JsPlugin(
      manifest: manifest,
      modules: <JsPluginModule>[
        for (final entry in modules.entries)
          JsPluginModule.asset(
            name: entry.key,
            path: entry.value,
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
          JsPluginModule(name: entry.key, source: entry.value),
      ],
    );
  }

  /// Loads a manifest JSON asset and its module asset map as one plugin.
  static Future<JsPlugin> manifestAsset({
    required String path,
    required Map<String, String> modules,
    AssetBundle? bundle,
  }) async {
    final resolvedBundle = bundle ?? rootBundle;
    final value = jsonDecode(await resolvedBundle.loadString(path));
    if (value is! Map<String, Object?>) {
      throw const JsValueConversionException(
        'QuickJS plugin manifest asset must be a JSON object',
      );
    }
    return JsPlugin.assets(
      manifest: _manifestFromJson(value),
      modules: modules,
      bundle: resolvedBundle,
    );
  }

  /// Parses a manifest JSON string and inline module sources as one plugin.
  static JsPlugin fromManifest({
    required String source,
    required Map<String, String> modules,
  }) {
    final value = jsonDecode(source);
    if (value is! Map<String, Object?>) {
      throw const JsValueConversionException(
        'QuickJS plugin manifest source must be a JSON object',
      );
    }
    return JsPlugin.sources(
      manifest: _manifestFromJson(value),
      modules: modules,
    );
  }

  /// Validated plugin contract and lifecycle declaration.
  final JsPluginManifest manifest;

  /// Immutable module graph owned by this plugin.
  final List<JsPluginModule> modules;

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
      _validateNonEmpty('QuickJS plugin module name', module.name);
      _validateNamespaced(module.name);
      if (!moduleNames.add(module.name)) {
        throw JsValueConversionException(
          'QuickJS plugin module is declared more than once: ${module.name}',
        );
      }
      if (module.name == manifest.entry) {
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

JsPluginManifest _manifestFromJson(Map<String, Object?> json) {
  return JsPluginManifest(
    id: _requiredString(json, 'id'),
    version: _requiredString(json, 'version'),
    entry: _requiredString(json, 'entry'),
    exports: _stringList(json, 'exports', required: true),
    init: _optionalString(json, 'init'),
    dispose: _optionalString(json, 'dispose'),
    permissions: _stringList(json, 'permissions'),
    metadata: _objectMap(json, 'metadata'),
  );
}

String _requiredString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value is String && value.isNotEmpty) return value;
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be a non-empty string: $key',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return null;
  if (value is String && value.isNotEmpty) return value;
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be a non-empty string: $key',
  );
}

List<String> _stringList(
  Map<String, Object?> json,
  String key, {
  bool required = false,
}) {
  final value = json[key];
  if (value == null && !required) return const <String>[];
  if (value is List && value.every((item) => item is String)) {
    return List<String>.unmodifiable(value.cast<String>());
  }
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be a string list: $key',
  );
}

Map<String, Object?> _objectMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) return const <String, Object?>{};
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be an object: $key',
  );
}

/// Host features that preserves the plugin manifest for runtime-level lookup.
///
/// 此函数仅供运行时组合层使用；常规调用方应将插件交给 Engine 的 `plugins` 或
/// `loadPlugin()` API。
JsFeatures createPluginFeatures(JsPlugin plugin, {String? name}) =>
    JsPluginFeatures(
      name: name ?? 'plugin:${plugin.manifest.id}',
      plugin: plugin,
      modules: <JsModule>[
        for (final module in plugin.modules) module.toHostModule(),
      ],
    );

/// 保留插件清单以供运行时查找的内部 Features 实现。
final class JsPluginFeatures extends JsFeatures {
  /// 创建包含 [plugin] 及其宿主模块的 Features。
  const JsPluginFeatures({
    required super.name,
    required this.plugin,
    super.browserGlobals,
    super.scripts,
    super.modules,
    super.methods,
  });

  /// 此 Features 对应的插件定义。
  final JsPlugin plugin;
}
