import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';
import 'quickjs.dart';
import 'quickjs_plugin.dart';

/// Lightweight client for one plugin mounted in a [Quickjs] runtime.
final class QuickjsPluginClient {
  const QuickjsPluginClient(this.engine, this.plugin);

  final Quickjs engine;
  final QuickjsPlugin plugin;

  String get pluginId => plugin.manifest.id;

  Future<void> validate({Duration? timeout}) {
    return engine.validatePlugin(plugin, timeout: timeout);
  }

  Future<Object?> init([
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  ]) {
    return engine.initPlugin(plugin, context: context, timeout: timeout);
  }

  Future<Object?> call(String method, List<Object?> args, {Duration? timeout}) {
    return engine.callPlugin(plugin, method, args, timeout: timeout);
  }

  Future<Object?> dispose({Duration? timeout}) {
    return engine.disposePlugin(plugin, timeout: timeout);
  }
}

/// Convenience constructors for plugin packages.
final class QuickjsPluginBundle {
  const QuickjsPluginBundle._();

  /// Creates a plugin package from a manifest asset and a module asset map.
  static Future<QuickjsPlugin> asset({
    required String manifestAsset,
    required Map<String, String> modules,
    AssetBundle? bundle,
  }) async {
    final resolvedBundle = bundle ?? rootBundle;
    final manifestJson = await resolvedBundle.loadString(manifestAsset);
    final manifestValue = jsonDecode(manifestJson);
    if (manifestValue is! Map<String, Object?>) {
      throw const JsValueConversionException(
        'QuickJS plugin manifest asset must be a JSON object',
      );
    }
    return QuickjsPlugin.asset(
      manifest: _manifestFromJson(manifestValue),
      modules: modules,
      bundle: resolvedBundle,
    );
  }
}

/// Registry for calling plugin exports as `pluginId.method` tools.
final class QuickjsToolRegistry {
  QuickjsToolRegistry(this.engine);

  final Quickjs engine;
  final Map<String, QuickjsPlugin> _plugins = <String, QuickjsPlugin>{};

  Iterable<QuickjsPlugin> get plugins => _plugins.values;

  QuickjsToolRegistry register(QuickjsPlugin plugin) {
    final previous = _plugins[plugin.manifest.id];
    if (previous != null && !identical(previous, plugin)) {
      throw JsValueConversionException(
        'QuickJS tool plugin is already registered: ${plugin.manifest.id}',
      );
    }
    _plugins[plugin.manifest.id] = plugin;
    return this;
  }

  QuickjsToolRegistry unregister(String pluginId) {
    _plugins.remove(pluginId);
    return this;
  }

  Future<void> validateAll({Duration? timeout}) async {
    for (final plugin in _plugins.values) {
      await engine.validatePlugin(plugin, timeout: timeout);
    }
  }

  Future<Object?> call(String tool, List<Object?> args, {Duration? timeout}) {
    final separator = tool.lastIndexOf('.');
    if (separator <= 0 || separator == tool.length - 1) {
      throw JsValueConversionException(
        'QuickJS tool name must use pluginId.method: $tool',
      );
    }
    final pluginId = tool.substring(0, separator);
    final method = tool.substring(separator + 1);
    final plugin = _plugins[pluginId];
    if (plugin == null) {
      throw JsValueConversionException(
        'QuickJS tool plugin is not registered: $pluginId',
      );
    }
    return engine.callPlugin(plugin, method, args, timeout: timeout);
  }
}

typedef QuickjsStreamFactory =
    FutureOr<Stream<Object?>> Function(List<Object?> args);

/// Naming helpers for JS sink and Dart stream bindings.
final class QuickjsStreamBridge {
  const QuickjsStreamBridge._();

  /// Binds a JS-side `{ emit, close, error }` sink and returns Dart's stream.
  static Future<Stream<Object?>> bindJsSink(Quickjs engine, String name) {
    return engine.bindSink(name);
  }

  /// Binds a Dart stream factory as a JS async iterable provider.
  static Future<void> bindDartStream(
    Quickjs engine,
    String name,
    QuickjsStreamFactory factory,
  ) {
    return engine.bind(name, factory);
  }
}

QuickjsPluginManifest _manifestFromJson(Map<String, Object?> json) {
  return QuickjsPluginManifest(
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
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be a non-empty string: $key',
  );
}

String? _optionalString(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return null;
  }
  if (value is String && value.isNotEmpty) {
    return value;
  }
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
  if (value == null && !required) {
    return const <String>[];
  }
  if (value is List && value.every((item) => item is String)) {
    return List<String>.unmodifiable(value.cast<String>());
  }
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be a string list: $key',
  );
}

Map<String, Object?> _objectMap(Map<String, Object?> json, String key) {
  final value = json[key];
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is Map) {
    return Map<String, Object?>.unmodifiable(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw JsValueConversionException(
    'QuickJS plugin manifest field must be an object: $key',
  );
}
