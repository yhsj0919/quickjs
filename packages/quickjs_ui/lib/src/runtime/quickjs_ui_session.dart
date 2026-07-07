import 'dart:async';
import 'dart:collection';

// ignore_for_file: prefer_initializing_formals

import 'package:quickjs/quickjs.dart';

import '../diagnostics/quickjs_ui_inspector.dart';
import '../host/quickjs_ui_permission_policy.dart';
import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_helpers.dart';

const int _quickjsUiStackLimitBytes = 1024 * 1024;
const int _minimumSupportedQuickjsUiSchemaVersion = 1;
const int _maximumSupportedQuickjsUiSchemaVersion = quickjsUiSchemaVersion;
const int _currentQuickjsUiRuntimeVersion = 1;

final class QuickjsUiSession {
  // Keep the public constructor parameters named `engine` and `onConsole`.
  QuickjsUiSession({
    Quickjs? engine,
    QuickjsConsoleSink? onConsole,
    QuickjsUiInspector? inspector,
  }) : _engine = engine,
       _onConsole = onConsole,
       inspector = inspector;

  Quickjs? _engine;
  final QuickjsConsoleSink? _onConsole;
  QuickjsUiInspector? inspector;
  QuickjsPlugin? _plugin;
  QuickjsPluginClient? _client;
  Map<String, Object?> _props = const <String, Object?>{};
  Set<String> _lifecycleTypes = const <String>{};
  List<QuickjsHostMount> _mounts = const <QuickjsHostMount>[];
  Set<String> _grantedPermissions = const <String>{};
  QuickjsUiPermissionPolicy? _permissionPolicy;
  Object? _state;
  QuickjsUiNode? _node;
  bool _ownsEngine = false;
  bool _disposed = false;
  bool _disposeLifecycleSent = false;
  int _activeCalls = 0;
  final Queue<_QueuedSessionOperation<Object?>> _operationQueue =
      Queue<_QueuedSessionOperation<Object?>>();
  final Queue<_QueuedSessionOperation<Object?>> _routeLifecycleQueue =
      Queue<_QueuedSessionOperation<Object?>>();
  bool _drainingOperationQueue = false;
  bool _drainingRouteLifecycleQueue = false;

  Quickjs? get engine => _engine;
  QuickjsPlugin? get plugin => _plugin;
  Map<String, Object?> get props => _props;
  List<QuickjsHostMount> get mounts => _mounts;
  Set<String> get grantedPermissions => _grantedPermissions;
  QuickjsUiPermissionPolicy? get permissionPolicy => _permissionPolicy;
  Object? get state => _state;
  QuickjsUiNode? get node => _node;
  bool get isDisposed => _disposed;

  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
  }) async {
    return _enqueue(() async {
      _ensureActive();
      permissionPolicy?.validate(
        plugin: plugin,
        grantedPermissions: grantedPermissions,
      );
      final ownsCreatedEngine = _engine == null;
      final engine =
          _engine ??
          await Quickjs.create(
            onConsole: _onConsole,
            options: QuickjsRuntimeOptions(
              stackLimitBytes: _quickjsUiStackLimitBytes,
              mounts: <QuickjsHostMount>[quickjsUiHelperMount, ...mounts],
            ),
          );
      if (_disposed) {
        if (ownsCreatedEngine) {
          unawaited(engine.dispose());
        }
        return;
      }
      _ownsEngine = ownsCreatedEngine;
      _engine = engine;
      if (!_ownsEngine) {
        await _ensureHelperModuleMounted(engine);
        if (_disposed) {
          return;
        }
      }
      await engine.mount(
        plugin.asMount(name: 'quickjs_ui:page:${plugin.manifest.id}'),
        conflictPolicy: QuickjsHostMountConflictPolicy.replace,
      );
      if (_disposed) {
        return;
      }
      _plugin = plugin;
      _props = Map<String, Object?>.unmodifiable(initialProps);
      _mounts = List<QuickjsHostMount>.unmodifiable(mounts);
      _grantedPermissions = Set<String>.unmodifiable(grantedPermissions);
      _permissionPolicy = permissionPolicy;
      _client = QuickjsPluginClient(engine, plugin);
      await _client!.validate();
      if (_disposed) {
        return;
      }
      _lifecycleTypes = await _loadLifecycleTypes(_client!, plugin);
      if (_disposed) {
        return;
      }
      final initialSnapshot = await _clientCall('mount', <Object?>[_props]);
      if (_disposed) {
        return;
      }
      _applySnapshot(initialSnapshot);
      inspector?.recordLifecycle('widget', 'load');
      await _refreshImpl();
    });
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    return _enqueue(() async {
      _ensureActive();
      inspector?.recordAction(event);
      final result = await _clientCall('handleEvent', <Object?>[event]);
      if (_disposed) {
        return;
      }
      if (_resultChanged(result)) {
        await _syncStateFromJs();
        await _refreshImpl();
      }
    });
  }

  Future<void> setState(Map<String, Object?> patch) async {
    return _enqueue(() async {
      _ensureActive();
      final result = await _clientCall('setState', <Object?>[patch]);
      if (_disposed) {
        return;
      }
      if (_resultChanged(result)) {
        await _syncStateFromJs();
        await _refreshImpl();
      }
    });
  }

  Future<bool> lifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) async {
    return _enqueue(() async {
      return _lifecycleImpl(type, payload: payload, render: render);
    });
  }

  Future<bool> routeLifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) {
    return _enqueueRouteLifecycle(() async {
      return _lifecycleImpl(
        type,
        payload: payload,
        render: render,
        phase: 'route',
      );
    });
  }

  Future<void> refresh() {
    return _enqueue(_refreshImpl);
  }

  Future<void> pumpTimers() {
    return _enqueue(() async {
      _ensureActive();
      final engine = _engine;
      if (engine == null || _plugin == null) {
        return;
      }
      await engine.evalAsync(
        'await new Promise((resolve) => setTimeout(resolve, 0)); return null;',
        name: '<quickjs_ui_timer_pump>',
        timeout: const Duration(milliseconds: 250),
      );
      if (_disposed) {
        return;
      }
      await _syncStateFromJs();
      await _refreshImpl();
    });
  }

  Future<void> _refreshImpl() async {
    _ensureActive();
    final result = await _clientCall('commit', const <Object?>[]);
    if (_disposed) {
      return;
    }
    if (result is Map && result['changed'] == false) {
      return;
    }
    final rendered = result is Map ? result['node'] : result;
    if (rendered is! Map) {
      throw const FormatException(
        'quickjs_ui commit() must return a UI node object',
      );
    }
    _node = QuickjsUiNode.fromMap(
      rendered.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
    inspector?.recordSchema(_node!.toMap());
  }

  Future<void> reload() async {
    _ensureActive();
    final plugin = _plugin;
    if (plugin == null) {
      return;
    }
    await loadPlugin(
      plugin,
      initialProps: _props,
      mounts: _mounts,
      grantedPermissions: _grantedPermissions,
      permissionPolicy: _permissionPolicy,
    );
  }

  void attach(Quickjs engine) {
    _ensureActive();
    _engine = engine;
    _ownsEngine = false;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    final client = _client;
    final plugin = _plugin;
    final engine = _engine;
    final ownsEngine = _ownsEngine;
    final hasActiveCalls = _activeCalls > 0;
    final disposeLifecycle = hasActiveCalls
        ? Future<void>.value()
        : _sendDisposeLifecycle(client, plugin);
    _disposed = true;
    _client = null;
    _engine = null;
    _plugin = null;
    _lifecycleTypes = const <String>{};
    unawaited(
      disposeLifecycle
          .then((_) async {
            if (client != null && plugin != null) {
              await _clientCallWith(
                client,
                'dispose',
                const <Object?>[],
              ).catchError((_) => null);
            }
            if (client != null && plugin?.manifest.dispose != null) {
              await client.dispose().catchError((_) => null);
            }
            if (ownsEngine) {
              await (engine?.dispose() ?? Future<void>.value());
            }
          })
          .catchError((_) => null),
    );
  }

  Future<void> _sendDisposeLifecycle(
    QuickjsPluginClient? client,
    QuickjsPlugin? plugin,
  ) async {
    if (_disposeLifecycleSent ||
        client == null ||
        plugin == null ||
        !_supportsLifecycle(plugin, 'dispose')) {
      return;
    }
    _disposeLifecycleSent = true;
    final event = const <String, Object?>{'type': 'dispose'};
    await _clientCallWith(client, 'lifecycle', <Object?>[
      event,
    ]).catchError((_) => null);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final operation = _QueuedSessionOperation<T>(action: action);
    _operationQueue.add(operation);
    if (!_drainingOperationQueue) {
      unawaited(_drainOperationQueue());
    }
    return operation.future;
  }

  Future<T> _enqueueRouteLifecycle<T>(Future<T> Function() action) {
    final operation = _QueuedSessionOperation<T>(action: action);
    _routeLifecycleQueue.add(operation);
    if (!_drainingRouteLifecycleQueue) {
      unawaited(_drainRouteLifecycleQueue());
    }
    return operation.future;
  }

  Future<void> _drainOperationQueue() async {
    if (_drainingOperationQueue) {
      return;
    }
    _drainingOperationQueue = true;
    try {
      while (_operationQueue.isNotEmpty) {
        final operation = _operationQueue.removeFirst();
        await operation.run();
      }
    } finally {
      _drainingOperationQueue = false;
      if (_operationQueue.isNotEmpty) {
        unawaited(_drainOperationQueue());
      }
    }
  }

  Future<void> _drainRouteLifecycleQueue() async {
    if (_drainingRouteLifecycleQueue) {
      return;
    }
    _drainingRouteLifecycleQueue = true;
    try {
      while (_routeLifecycleQueue.isNotEmpty) {
        final operation = _routeLifecycleQueue.removeFirst();
        await operation.run();
      }
    } finally {
      _drainingRouteLifecycleQueue = false;
      if (_routeLifecycleQueue.isNotEmpty) {
        unawaited(_drainRouteLifecycleQueue());
      }
    }
  }

  Future<bool> _lifecycleImpl(
    String type, {
    Object? payload,
    bool render = true,
    String phase = 'widget',
  }) async {
    _ensureActive();
    final plugin = _plugin;
    if (plugin == null || !_supportsLifecycle(plugin, type)) {
      inspector?.recordLifecycle(phase, type, payload: payload);
      return false;
    }
    if (type == 'dispose') {
      if (_disposeLifecycleSent) {
        return false;
      }
      _disposeLifecycleSent = true;
    }
    final event = <String, Object?>{'type': type};
    if (payload != null) {
      event['payload'] = payload;
    }
    inspector?.recordLifecycle(phase, type, payload: payload);
    final result = await _clientCall('lifecycle', <Object?>[event]);
    if (_disposed) {
      return false;
    }
    final didUpdateState = _resultChanged(result);
    if (didUpdateState) {
      await _syncStateFromJs();
    }
    if (render && didUpdateState) {
      await _refreshImpl();
    }
    return didUpdateState;
  }

  bool _supportsLifecycle(QuickjsPlugin plugin, String type) {
    return plugin.manifest.exports.contains('lifecycle') &&
        _lifecycleTypes.contains(type);
  }

  QuickjsPluginClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('QuickjsUiSession has no loaded page');
    }
    return client;
  }

  Future<Object?> _clientCall(String name, List<Object?> args) {
    return _clientCallWith(_requireClient(), name, args);
  }

  Future<Set<String>> _loadLifecycleTypes(
    QuickjsPluginClient client,
    QuickjsPlugin plugin,
  ) async {
    final exports = plugin.manifest.exports;
    const requiredExports = <String>{
      'mount',
      'handleEvent',
      'commit',
      'setState',
      'lifecycle',
      'snapshot',
      'capabilities',
      'dispose',
    };
    final missing = requiredExports.where((name) => !exports.contains(name));
    if (missing.isNotEmpty) {
      throw StateError(
        'quickjs_ui plugin does not implement runtime v1 exports: '
        '${missing.join(', ')}',
      );
    }
    final value = await _clientCallWith(
      client,
      'capabilities',
      const <Object?>[],
    );
    if (value is! Map) {
      return const <String>{};
    }
    final protocol = value['protocol'];
    if (protocol != quickjsUiRuntimeProtocol) {
      throw StateError('quickjs_ui unsupported runtime protocol: $protocol');
    }
    _validateCompatibility(value);
    final lifecycle = value['lifecycle'];
    if (lifecycle is! List) {
      return const <String>{};
    }
    return Set<String>.unmodifiable(lifecycle.whereType<String>());
  }

  void _validateCompatibility(Map<Object?, Object?> capabilities) {
    final schemaVersion = _intCapability(
      capabilities,
      'schemaVersion',
      fallback: 1,
    );
    if (schemaVersion < _minimumSupportedQuickjsUiSchemaVersion ||
        schemaVersion > _maximumSupportedQuickjsUiSchemaVersion) {
      throw StateError(
        'quickjs_ui unsupported schema version: $schemaVersion '
        '(supported $_minimumSupportedQuickjsUiSchemaVersion'
        '-$_maximumSupportedQuickjsUiSchemaVersion)',
      );
    }

    final helperVersion = _intCapability(
      capabilities,
      'helperVersion',
      fallback: 1,
    );
    if (helperVersion > quickjsUiHelperVersion) {
      throw StateError(
        'quickjs_ui helper version is newer than runtime: $helperVersion '
        '(runtime $quickjsUiHelperVersion)',
      );
    }

    final minimumRuntime = _intCapability(
      capabilities,
      'minimumQuickjsUiVersion',
      fallback: 1,
    );
    if (minimumRuntime > _currentQuickjsUiRuntimeVersion) {
      throw StateError(
        'quickjs_ui page requires runtime version $minimumRuntime '
        'but current runtime is $_currentQuickjsUiRuntimeVersion',
      );
    }

    final unknownProps = capabilities['unknownProps'];
    if (unknownProps != null &&
        unknownProps != 'ignore' &&
        unknownProps != 'warn' &&
        unknownProps != 'error') {
      throw StateError(
        'quickjs_ui unsupported unknownProps strategy: $unknownProps',
      );
    }

    final deprecatedProps = capabilities['deprecatedProps'];
    if (deprecatedProps != null && deprecatedProps is! Map) {
      throw StateError('quickjs_ui deprecatedProps must be an object');
    }
  }

  int _intCapability(
    Map<Object?, Object?> capabilities,
    String name, {
    required int fallback,
  }) {
    final value = capabilities[name];
    if (value == null) {
      return fallback;
    }
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    throw StateError('quickjs_ui capability "$name" must be a number');
  }

  Future<void> _syncStateFromJs() async {
    _applySnapshot(await _clientCall('snapshot', const <Object?>[]));
  }

  void _applySnapshot(Object? snapshot) {
    if (snapshot is Map) {
      _state = snapshot['state'];
      return;
    }
    _state = snapshot;
  }

  bool _resultChanged(Object? result) {
    if (result is Map) {
      return result['changed'] == true;
    }
    return result == true;
  }

  Future<Object?> _clientCallWith(
    QuickjsPluginClient client,
    String name,
    List<Object?> args,
  ) async {
    _activeCalls += 1;
    final logicalName = _logicalCallName(name);
    final detail = _callDetail(logicalName, args);
    try {
      return await client.call(name, args);
    } catch (error) {
      throw QuickjsUiRuntimeException(
        call: logicalName,
        detail: detail,
        cause: error,
      );
    } finally {
      _activeCalls -= 1;
    }
  }

  String _logicalCallName(String name) {
    return switch (name) {
      'handleEvent' => 'dispatch',
      'commit' => 'render',
      'snapshot' => 'state',
      _ => name,
    };
  }

  String _callDetail(String logicalName, List<Object?> args) {
    return switch (logicalName) {
      'dispatch' => _dispatchDetail(args),
      'render' => 'build',
      'lifecycle' => 'lifecycle',
      'setState' => 'patch',
      'state' => 'snapshot',
      _ => logicalName,
    };
  }

  String _dispatchDetail(List<Object?> args) {
    if (args.isEmpty) {
      return 'unknown';
    }
    final event = args.length == 1 ? args[0] : args[1];
    if (event is! Map) {
      return 'non-object-event';
    }
    final method = event['method'] ?? event['action'];
    final type = event['type'];
    final positionMs = event['positionMs'];
    final isPlaying = event['isPlaying'];
    final payload = event['payload'];
    final playing =
        event['playing'] ?? (payload is Map ? payload['playing'] : null);
    final durationMs = event['durationMs'];
    final value = event['value'] ?? (payload is Map ? payload['value'] : null);
    final buffer = StringBuffer('method=$method');
    if (type != null) {
      buffer.write(' type=$type');
    }
    if (positionMs != null) {
      buffer.write(' positionMs=$positionMs');
    }
    if (value != null) {
      buffer.write(' value=$value');
    }
    if (durationMs != null) {
      buffer.write(' durationMs=$durationMs');
    }
    if (playing != null) {
      buffer.write(' playing=$playing');
    }
    if (isPlaying != null) {
      buffer.write(' isPlaying=$isPlaying');
    }
    return buffer.toString();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiSession is disposed');
    }
  }
}

final class _QueuedSessionOperation<T> {
  _QueuedSessionOperation({required Future<T> Function() action})
    : _action = action;

  final Future<T> Function() _action;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  Future<void> run() async {
    if (_completer.isCompleted) {
      return;
    }
    try {
      _completer.complete(await _action());
    } catch (error, stackTrace) {
      _completer.completeError(error, stackTrace);
    }
  }
}

final class QuickjsUiRuntimeException implements Exception {
  const QuickjsUiRuntimeException({
    required this.call,
    required this.detail,
    required this.cause,
  });

  final String call;
  final String detail;
  final Object cause;

  @override
  String toString() {
    final buffer = StringBuffer('quickjs_ui runtime call failed')
      ..write(' call=$call')
      ..write(' detail=$detail');
    final cause = this.cause;
    if (cause is JsException) {
      buffer
        ..write(' jsName=${cause.name ?? 'unknown'}')
        ..write(' jsMessage=${cause.message}');
      final stack = cause.stack;
      if (stack != null && stack.isNotEmpty) {
        buffer.write(' jsStack=$stack');
      }
    } else if (cause is QuickjsException) {
      buffer.write(' quickjsMessage=${cause.message}');
    } else {
      buffer.write(' cause=$cause');
    }
    return buffer.toString();
  }
}

Future<void> _ensureHelperModuleMounted(Quickjs engine) async {
  final snapshot = await engine.debugInspect();
  if (snapshot.moduleNames.contains(quickjsUiHelperModuleSpecifier)) {
    return;
  }
  await engine.mount(quickjsUiHelperMount);
}
