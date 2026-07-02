import 'dart:async';

// ignore_for_file: prefer_initializing_formals

import 'package:quickjs/quickjs.dart';

import '../host/quickjs_ui_permission_policy.dart';
import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_helpers.dart';

final class QuickjsUiSession {
  // Keep the public constructor parameters named `engine` and `onConsole`.
  QuickjsUiSession({Quickjs? engine, QuickjsConsoleSink? onConsole})
    : _engine = engine,
      _onConsole = onConsole;

  Quickjs? _engine;
  final QuickjsConsoleSink? _onConsole;
  QuickjsPlugin? _plugin;
  QuickjsPluginClient? _client;
  Map<String, Object?> _props = const <String, Object?>{};
  List<QuickjsHostMount> _mounts = const <QuickjsHostMount>[];
  Set<String> _grantedPermissions = const <String>{};
  QuickjsUiPermissionPolicy? _permissionPolicy;
  Object? _state;
  QuickjsUiNode? _node;
  bool _ownsEngine = false;
  bool _disposed = false;
  bool _disposeLifecycleSent = false;
  int _activeCalls = 0;
  Future<void> _operationTail = Future<void>.value();

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
      final initialState = plugin.manifest.init == null
          ? <String, Object?>{}
          : await _client!.init(_props);
      if (_disposed) {
        return;
      }
      _state = initialState;
      await _refreshImpl();
    });
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    return _enqueue(() async {
      _ensureActive();
      final nextState = await _clientCall('dispatch', <Object?>[
        _state,
        event,
        _props,
      ]);
      if (_disposed) {
        return;
      }
      if (nextState != null) {
        _state = nextState;
      }
      await _refreshImpl();
    });
  }

  Future<void> setState(Map<String, Object?> patch) async {
    return _enqueue(() async {
      _ensureActive();
      final current = _state;
      if (current is Map) {
        _state = <String, Object?>{
          ...current.map(
            (key, value) => MapEntry<String, Object?>('$key', value),
          ),
          ...patch,
        };
      } else {
        _state = Map<String, Object?>.of(patch);
      }
      await _refreshImpl();
    });
  }

  Future<void> lifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) async {
    return _enqueue(() async {
      _ensureActive();
      final plugin = _plugin;
      if (plugin == null || !plugin.manifest.exports.contains('lifecycle')) {
        return;
      }
      if (type == 'dispose') {
        if (_disposeLifecycleSent) {
          return;
        }
        _disposeLifecycleSent = true;
      }
      final event = <String, Object?>{'type': type};
      if (payload != null) {
        event['payload'] = payload;
      }
      final nextState = await _clientCall('lifecycle', <Object?>[
        _state,
        event,
        _props,
      ]);
      if (_disposed) {
        return;
      }
      final didUpdateState = nextState != null;
      if (didUpdateState) {
        _state = nextState;
      }
      if (render && didUpdateState) {
        await _refreshImpl();
      }
    });
  }

  Future<void> refresh() {
    return _enqueue(_refreshImpl);
  }

  Future<void> _refreshImpl() async {
    _ensureActive();
    final rendered = await _clientCall('render', <Object?>[_state, _props]);
    if (_disposed) {
      return;
    }
    if (rendered is! Map) {
      throw const FormatException(
        'quickjs_ui render() must return a UI node object',
      );
    }
    _node = QuickjsUiNode.fromMap(
      rendered.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
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
    unawaited(
      disposeLifecycle.then((_) async {
        if (client != null && plugin?.manifest.dispose != null) {
          await client.dispose().catchError((_) => null);
        }
        if (ownsEngine) {
          await (engine?.dispose() ?? Future<void>.value());
        }
      }),
    );
  }

  Future<void> _sendDisposeLifecycle(
    QuickjsPluginClient? client,
    QuickjsPlugin? plugin,
  ) async {
    if (_disposeLifecycleSent ||
        client == null ||
        plugin == null ||
        !plugin.manifest.exports.contains('lifecycle')) {
      return;
    }
    _disposeLifecycleSent = true;
    await _clientCallWith(client, 'lifecycle', <Object?>[
      _state,
      const <String, Object?>{'type': 'dispose'},
      _props,
    ]).catchError((_) => null);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    final result = _operationTail.then((_) => action());
    _operationTail = result.then((_) {}, onError: (_) {});
    return result;
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

  Future<Object?> _clientCallWith(
    QuickjsPluginClient client,
    String name,
    List<Object?> args,
  ) async {
    _activeCalls += 1;
    try {
      return await client.call(name, args);
    } finally {
      _activeCalls -= 1;
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiSession is disposed');
    }
  }
}

Future<void> _ensureHelperModuleMounted(Quickjs engine) async {
  final snapshot = await engine.debugInspect();
  if (snapshot.moduleNames.contains(quickjsUiHelperModuleSpecifier)) {
    return;
  }
  await engine.mount(quickjsUiHelperMount);
}
