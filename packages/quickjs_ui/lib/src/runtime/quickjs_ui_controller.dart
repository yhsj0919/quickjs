import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:quickjs/quickjs.dart';

import '../diagnostics/quickjs_ui_dev_options.dart';
import '../diagnostics/quickjs_ui_error.dart';
import '../diagnostics/quickjs_ui_inspector.dart';
import '../diagnostics/quickjs_ui_load_metrics.dart';
import '../diagnostics/quickjs_ui_page_snapshot.dart';
import '../diagnostics/quickjs_ui_network_journal.dart';
import '../host/quickjs_ui_host_capabilities.dart';
import '../host/quickjs_ui_permission_policy.dart';
import '../resource/quickjs_ui_network_loader.dart';
import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_session.dart';
import 'quickjs_ui_runtime.dart';

typedef QuickjsUiPluginLoader = Future<QuickjsPlugin> Function();

/// Controller for one quickjs_ui page instance.
///
/// The controller is the Flutter binding layer: it owns loading/error
/// notifications, while [QuickjsUiSession] owns runtime, plugin, state and tree
/// lifecycle.
final class QuickjsUiController extends ChangeNotifier {
  QuickjsUiController({
    Quickjs? engine,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    QuickjsUiDevOptions? devOptions,
    QuickjsUiInspector? inspector,
  }) : devOptions = devOptions ?? QuickjsUiDevOptions.defaults,
       inspector = inspector ?? QuickjsUiInspector(),
       _session = QuickjsUiSession(
         engine: engine,
         runtime: runtime,
         onConsole: onConsole,
       ) {
    _session.inspector = this.inspector;
  }

  final QuickjsUiSession _session;
  final QuickjsUiDevOptions devOptions;
  final QuickjsUiInspector inspector;
  QuickjsUiError? _error;
  QuickjsUiLoadMetrics? _lastLoadMetrics;
  _QuickjsUiLoadConfig _loadConfig = _QuickjsUiLoadConfig.copy();
  bool _loading = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  Future<void>? _closeFuture;
  bool _timerPumpRunning = false;
  int _loadRequestId = 0;
  Timer? _timerPump;

  QuickjsUiSession get session => _session;
  Quickjs? get engine => _session.engine;
  QuickjsPlugin? get plugin => _session.plugin;
  Map<String, Object?> get props => _session.props;
  Object? get state => _session.state;
  QuickjsUiNode? get node => _session.node;
  QuickjsUiError? get error => _error;
  QuickjsUiLoadMetrics? get lastLoadMetrics => _lastLoadMetrics;

  void _acceptLoadMetrics(QuickjsUiLoadMetrics? metrics) {
    if (metrics == null) return;
    _lastLoadMetrics = metrics;
  }

  bool get hasError => _error != null;
  bool get isLoading => _loading;
  bool get isDisposed => _disposed;

  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiErrorContext errorContext = const QuickjsUiErrorContext(),
    bool notifyLoading = true,
  }) async {
    _loadConfig = _QuickjsUiLoadConfig.copy(
      plugin: plugin,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
    );
    final requestId = ++_loadRequestId;
    await _loadPlugin(
      plugin,
      requestId: requestId,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
      notifyLoading: notifyLoading,
    );
  }

  Future<void> load(
    QuickjsUiPluginLoader loader, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiErrorContext errorContext = const QuickjsUiErrorContext(),
    bool notifyLoading = true,
  }) async {
    _ensureActive();
    _loadConfig = _QuickjsUiLoadConfig.copy(
      loader: loader,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
    );
    final requestId = ++_loadRequestId;
    _loading = true;
    _error = null;
    if (notifyLoading) {
      notifyListeners();
    }

    try {
      final resourceWatch = Stopwatch()..start();
      final plugin = await loader();
      resourceWatch.stop();
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _stopTimerPump();
      await _session.loadPlugin(
        plugin,
        initialProps: initialProps,
        mounts: mounts,
        grantedPermissions: grantedPermissions,
        permissionPolicy: permissionPolicy,
      );
      final metrics = _session.lastLoadMetrics;
      _acceptLoadMetrics(
        metrics?.withStage('resourceLoad', resourceWatch.elapsed),
      );
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.load, context: errorContext);
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadPlugin(
    QuickjsPlugin plugin, {
    required int requestId,
    required Map<String, Object?> initialProps,
    required List<QuickjsHostMount> mounts,
    required Iterable<String> grantedPermissions,
    required QuickjsUiPermissionPolicy? permissionPolicy,
    required QuickjsUiErrorContext errorContext,
    required bool notifyLoading,
  }) async {
    _ensureActive();
    _loading = true;
    _error = null;
    if (notifyLoading) {
      notifyListeners();
    }

    try {
      _stopTimerPump();
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      await _session.loadPlugin(
        plugin,
        initialProps: initialProps,
        mounts: mounts,
        grantedPermissions: grantedPermissions,
        permissionPolicy: permissionPolicy,
      );
      _acceptLoadMetrics(_session.lastLoadMetrics);
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.load, context: errorContext);
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    _ensureActive();
    _error = null;
    try {
      await _session.dispatch(event);
      if (_disposed) {
        return;
      }
      _startTimerPump();
      notifyListeners();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(
        error,
        kind: QuickjsUiErrorKind.dispatch,
        action: '${event['method'] ?? event['action'] ?? 'unknown'}',
      );
      notifyListeners();
    }
  }

  Future<void> dispatchBatch(Iterable<Map<String, Object?>> events) async {
    _ensureActive();
    _error = null;
    try {
      await _session.dispatchBatch(events);
      if (_disposed) return;
      _startTimerPump();
      notifyListeners();
    } catch (error) {
      if (_disposed) return;
      _recordError(error, kind: QuickjsUiErrorKind.dispatch);
      notifyListeners();
    }
  }

  Future<void> setState(Map<String, Object?> patch) async {
    _ensureActive();
    _error = null;
    try {
      await _session.setState(patch);
      if (_disposed) {
        return;
      }
      _startTimerPump();
      notifyListeners();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.state);
      notifyListeners();
    }
  }

  Future<void> refresh() async {
    _ensureActive();
    _error = null;
    try {
      await _session.refresh();
      if (_disposed) {
        return;
      }
      _startTimerPump();
      notifyListeners();
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.render);
      notifyListeners();
    }
  }

  Future<void> lifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) async {
    _ensureActive();
    _error = null;
    try {
      final changed = await _session.lifecycle(
        type,
        payload: payload,
        render: render,
      );
      if (_disposed) {
        return;
      }
      _startTimerPump();
      if (changed) {
        notifyListeners();
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.lifecycle, lifecycle: type);
      notifyListeners();
    }
  }

  Future<void> routeLifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) async {
    _ensureActive();
    _error = null;
    try {
      final changed = await _session.routeLifecycle(
        type,
        payload: payload,
        render: render,
      );
      if (_disposed) {
        return;
      }
      _startTimerPump();
      if (changed) {
        notifyListeners();
      }
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.lifecycle, lifecycle: type);
      notifyListeners();
    }
  }

  void attach(Quickjs engine) {
    _ensureActive();
    _session.attach(engine);
    _error = null;
    notifyListeners();
  }

  void reportError(Object error) {
    _ensureActive();
    _recordError(error, kind: QuickjsUiErrorKind.unknown);
    notifyListeners();
  }

  QuickjsUiPageSnapshot exportPageSnapshot() {
    return inspector.buildSnapshot(
      props: props,
      state: state,
      node: node,
      plugin: plugin,
      mounts: _session.mounts,
      error: error,
    );
  }

  Map<String, Object?> exportPageSnapshotMap() {
    return exportPageSnapshot().toMap();
  }

  void recordAppLifecycle(String type, {Object? payload}) {
    inspector.recordLifecycle('app', type, payload: payload);
  }

  void recordResourceLog(String message) {
    if (devOptions.logResources) {
      inspector.recordResource(message);
    }
  }

  void recordNetworkLog(QuickjsUiNetworkLogEvent event) {
    if (devOptions.logResources) {
      inspector.recordNetworkEvent(event);
    }
  }

  QuickjsUiHostApiHandlers instrumentHostHandlers(
    QuickjsUiHostApiHandlers handlers,
  ) {
    if (!devOptions.logResources) {
      return handlers;
    }
    return instrumentHostNetworkLogging(handlers, inspector.networkJournal);
  }

  Future<void> restart() async {
    _ensureActive();
    final config = _loadConfig;
    final requestId = ++_loadRequestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      _stopTimerPump();
      final currentPlugin = _session.plugin;
      if (currentPlugin != null) {
        await _session.reload();
      } else {
        final configuredPlugin = config.plugin;
        if (configuredPlugin == null) {
          throw StateError('QuickjsUiController has no page to restart');
        }
        await _session.loadPlugin(
          configuredPlugin,
          initialProps: config.initialProps,
          mounts: config.mounts,
          grantedPermissions: config.grantedPermissions,
          permissionPolicy: config.permissionPolicy,
        );
      }
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(
        error,
        kind: QuickjsUiErrorKind.load,
        context: _loadConfig.errorContext,
      );
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> reload() async {
    _ensureActive();
    final config = _loadConfig;
    final loader = config.loader;
    if (loader == null) {
      await restart();
      return;
    }
    final savedState = devOptions.preserveStateOnReload ? state : null;
    final requestId = ++_loadRequestId;
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final plugin = await loader();
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _stopTimerPump();
      await _session.loadPlugin(
        plugin,
        initialProps: config.initialProps,
        mounts: config.mounts,
        grantedPermissions: config.grantedPermissions,
        permissionPolicy: config.permissionPolicy,
      );
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _startTimerPump();
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      if (savedState is Map) {
        await setState(
          Map<String, Object?>.from(
            savedState.map((key, value) => MapEntry('$key', value)),
          ),
        );
      }
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(
        error,
        kind: QuickjsUiErrorKind.load,
        context: config.errorContext,
      );
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  @override
  void dispose() {
    if (_notifierDisposed) {
      return;
    }
    _notifierDisposed = true;
    unawaited(close());
    super.dispose();
  }

  /// Stops this controller and waits until its QuickJS session is cleaned up.
  ///
  /// Call this before replacing a controller that uses an attached engine.
  /// Flutter's synchronous [dispose] delegates here but cannot await it.
  Future<void> close() {
    final currentClose = _closeFuture;
    if (currentClose != null) {
      return currentClose;
    }
    _disposed = true;
    _stopTimerPump();
    return _closeFuture = _session.dispose();
  }

  void _startTimerPump() {
    _scheduleTimerPump(Duration.zero);
  }

  void _scheduleTimerPump(Duration? delay) {
    _timerPump?.cancel();
    _timerPump = null;
    if (_disposed || delay == null) return;
    _timerPump = Timer(delay, () => unawaited(_pumpTimers()));
  }

  void _stopTimerPump() {
    _timerPump?.cancel();
    _timerPump = null;
    _timerPumpRunning = false;
  }

  Future<void> _pumpTimers() async {
    if (_disposed || _loading || _timerPumpRunning || _session.plugin == null) {
      return;
    }
    _timerPumpRunning = true;
    try {
      final result = await _session.pumpTimers();
      if (_disposed) {
        return;
      }
      if (result.changed) {
        notifyListeners();
      }
      _scheduleTimerPump(result.nextDelay);
    } catch (error) {
      if (_disposed) {
        return;
      }
      _recordError(error, kind: QuickjsUiErrorKind.runtime);
      _stopTimerPump();
      notifyListeners();
    } finally {
      if (!_disposed) {
        _timerPumpRunning = false;
      }
    }
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiController is disposed');
    }
  }

  void _recordError(
    Object error, {
    required QuickjsUiErrorKind kind,
    String? action,
    String? lifecycle,
    QuickjsUiErrorContext context = const QuickjsUiErrorContext(),
  }) {
    final cause = error is QuickjsUiError ? error.cause : error;
    final resolvedKind = switch (cause) {
      QuickjsUiNetworkException() => QuickjsUiErrorKind.network,
      QuickjsUiPermissionException() => QuickjsUiErrorKind.permission,
      FormatException() when kind == QuickjsUiErrorKind.load =>
        QuickjsUiErrorKind.resource,
      _ => kind,
    };
    final unified = QuickjsUiError.wrap(
      error,
      kind: resolvedKind,
      action: action,
      lifecycle: lifecycle,
      context: context,
    );
    _error = unified;
    inspector.recordError(unified);
  }
}

final class _QuickjsUiLoadConfig {
  factory _QuickjsUiLoadConfig.copy({
    QuickjsUiPluginLoader? loader,
    QuickjsPlugin? plugin,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiErrorContext errorContext = const QuickjsUiErrorContext(),
  }) {
    return _QuickjsUiLoadConfig._(
      loader: loader,
      plugin: plugin,
      initialProps: Map<String, Object?>.unmodifiable(initialProps),
      mounts: List<QuickjsHostMount>.unmodifiable(mounts),
      grantedPermissions: Set<String>.unmodifiable(grantedPermissions),
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
    );
  }

  const _QuickjsUiLoadConfig._({
    required this.loader,
    required this.plugin,
    required this.initialProps,
    required this.mounts,
    required this.grantedPermissions,
    required this.permissionPolicy,
    required this.errorContext,
  });

  final QuickjsUiPluginLoader? loader;
  final QuickjsPlugin? plugin;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;
  final Set<String> grantedPermissions;
  final QuickjsUiPermissionPolicy? permissionPolicy;
  final QuickjsUiErrorContext errorContext;
}
