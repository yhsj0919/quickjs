import 'dart:async';
import '../diagnostics/diag.dart';
import '../diagnostics/exception.dart';
import 'engine.dart';
import 'plugin.dart';

/// Lightweight client for one plugin mounted in a [JsPluginHost].
final class JsPluginClient {
  /// 创建绑定到 [engine] 与 [plugin] 的轻量调用客户端。
  const JsPluginClient(this.engine, this.plugin);

  static int _nextCallId = 0;
  static DateTime? _lastCoreCallEndedAt;

  /// 执行插件调用的宿主 Engine 或子 Context。
  final JsPluginHost engine;

  /// 此客户端绑定的插件定义。
  final JsPlugin plugin;

  /// 插件清单中的稳定标识符。
  String get pluginId => plugin.manifest.id;

  /// 验证插件清单、模块图与导出声明。
  Future<void> validate({Duration? timeout}) async {
    await _traceCoreCall<void>(
      phase: 'validate',
      method: '<validate>',
      args: const <Object?>[],
      timeout: timeout,
      action: () => engine.validatePlugin(plugin, timeout: timeout),
    );
  }

  /// 调用插件的可选初始化导出并传入 [context]。
  Future<Object?> init({
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) {
    return _traceCoreCall<Object?>(
      phase: 'init',
      method: plugin.manifest.init ?? '<init>',
      args: <Object?>[context],
      timeout: timeout,
      action: () =>
          engine.initPlugin(plugin, context: context, timeout: timeout),
    );
  }

  /// 调用插件声明的 [method] 导出。
  Future<Object?> call(String method, List<Object?> args, {Duration? timeout}) {
    return _traceCoreCall<Object?>(
      phase: 'call',
      method: method,
      args: args,
      timeout: timeout,
      action: () =>
          engine.callPluginExport(plugin, method, args, timeout: timeout),
    );
  }

  /// 调用插件的可选释放导出。
  Future<Object?> dispose({Duration? timeout}) {
    return _traceCoreCall<Object?>(
      phase: 'dispose',
      method: plugin.manifest.dispose ?? '<dispose>',
      args: const <Object?>[],
      timeout: timeout,
      action: () => engine.disposePlugin(plugin, timeout: timeout),
    );
  }

  Future<T> _traceCoreCall<T>({
    required String phase,
    required String method,
    required List<Object?> args,
    required Duration? timeout,
    required Future<T> Function() action,
  }) async {
    final id = ++_nextCallId;
    final startedAt = DateTime.now();
    final idleMs = _lastCoreCallEndedAt == null
        ? null
        : startedAt.difference(_lastCoreCallEndedAt!).inMilliseconds;
    final detail =
        'id=$id plugin=$pluginId phase=$phase method=$method '
        'idleMs=$idleMs args=${_argsSummary(args)} '
        'timeoutMs=${timeout?.inMilliseconds}';
    JsDiag.count('plugin.call', detail: detail);
    JsDiag.log('plugin.call', 'start $detail');
    try {
      final result = await action();
      JsDiag.log(
        'plugin.call',
        'done id=$id plugin=$pluginId phase=$phase method=$method '
            'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} '
            'result=${_valueSummary(result)}',
      );
      _lastCoreCallEndedAt = DateTime.now();
      return result;
    } catch (error, stackTrace) {
      JsDiag.log(
        'plugin.call',
        'FAILED id=$id plugin=$pluginId phase=$phase method=$method '
            'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds} '
            'idleMs=$idleMs '
            'error=${_errorSummary(error)}',
      );
      JsDiag.log('plugin.call', '$stackTrace');
      _lastCoreCallEndedAt = DateTime.now();
      rethrow;
    }
  }
}

/// Registry for calling plugin exports through `pluginId.method` names.
final class JsPluginRegistry {
  /// 创建通过 [engine] 执行已注册插件的 Registry。
  JsPluginRegistry(this.engine);

  /// Registry 用于验证和调用插件的 Engine。
  final JsEngine engine;
  final Map<String, JsPlugin> _plugins = <String, JsPlugin>{};

  /// 当前已注册插件的只读视图。
  Iterable<JsPlugin> get plugins => _plugins.values;

  /// 注册 [plugin] 并返回当前 Registry 以支持链式配置。
  JsPluginRegistry register(JsPlugin plugin) {
    final previous = _plugins[plugin.manifest.id];
    if (previous != null && !identical(previous, plugin)) {
      throw JsValueConversionException(
        'QuickJS plugin is already registered: ${plugin.manifest.id}',
      );
    }
    _plugins[plugin.manifest.id] = plugin;
    return this;
  }

  /// 注销 [pluginId] 对应的插件并返回当前 Registry。
  JsPluginRegistry unregister(String pluginId) {
    _plugins.remove(pluginId);
    return this;
  }

  /// 依次验证所有已注册插件。
  Future<void> validateAll({Duration? timeout}) async {
    for (final plugin in _plugins.values) {
      await engine.validatePlugin(plugin, timeout: timeout);
    }
  }

  /// 调用 [pluginId] 插件声明的 [method] 导出。
  Future<Object?> call(
    String pluginId,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    final plugin = _plugins[pluginId];
    if (plugin == null) {
      throw JsValueConversionException(
        'QuickJS plugin is not registered: $pluginId',
      );
    }
    return engine.callPluginExport(plugin, method, args, timeout: timeout);
  }
}

String _argsSummary(List<Object?> args) {
  if (args.isEmpty) {
    return '[]';
  }
  return '[${args.take(4).map(_valueSummary).join(',')}${args.length > 4 ? ',+${args.length - 4}' : ''}]';
}

String _valueSummary(Object? value) {
  if (value == null) {
    return 'null';
  }
  if (value is Map) {
    final keys = value.keys.take(8).join(',');
    final suffix = value.length > 8 ? ',+${value.length - 8}' : '';
    return 'Map(len=${value.length} keys=$keys$suffix)';
  }
  if (value is List) {
    return 'List(len=${value.length})';
  }
  if (value is String) {
    final text = value.length <= 48 ? value : '${value.substring(0, 48)}...';
    return 'String(len=${value.length} "$text")';
  }
  if (value is num || value is bool) {
    return '$value';
  }
  return value.runtimeType.toString();
}

String _errorSummary(Object error) {
  if (error is JsThrownException) {
    return 'JsThrownException name=${error.name ?? 'unknown'} message=${error.message}';
  }
  if (error is JsException) {
    return '${error.runtimeType} message=${error.message}';
  }
  return '$error';
}
