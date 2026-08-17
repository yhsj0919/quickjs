import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:lemon_js/lemon_js.dart';

import '../diagnostics/quickjs_ui_dev_options.dart';
import '../diagnostics/quickjs_ui_error.dart';
import '../diagnostics/quickjs_ui_inspector.dart';
import '../diagnostics/quickjs_ui_load_metrics.dart';
import '../diagnostics/quickjs_ui_page_snapshot.dart';
import '../host/quickjs_ui_permission_policy.dart';
import '../renderer/quickjs_ui_canvas_scene.dart';
import '../resource/quickjs_ui_network_loader.dart';
import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_session.dart';
import 'quickjs_ui_lifecycle.dart';
import 'quickjs_ui_runtime.dart';

/// Loads or rebuilds the JavaScript plugin for a page.
typedef JsUiPluginLoader = Future<JsPlugin> Function();

/// Controller for one quickjs_ui page instance.
///
/// The controller is the Flutter binding layer: it owns loading/error
/// notifications, while [JsUiSession] owns runtime, plugin, state and tree
/// lifecycle.
final class JsUiController extends ChangeNotifier {
  /// Creates a controller backed by an owned engine or shared [runtime].
  JsUiController({
    JsEngine? engine,
    JsUiRuntime? runtime,
    JsConsoleSink? onConsole,
    JsUiDevOptions? devOptions,
    JsUiInspector? inspector,
  }) : devOptions = devOptions ?? JsUiDevOptions.defaults,
       inspector = inspector ?? JsUiInspector(),
       _session = JsUiSession(
         engine: engine,
         runtime: runtime,
         onConsole: onConsole,
       ) {
    _session.inspector = this.inspector;
  }

  final JsUiSession _session;

  /// Development and hot-reload behavior.
  final JsUiDevOptions devOptions;

  /// Diagnostics collector for this page.
  final JsUiInspector inspector;

  /// Canvas scenes retained by the current page revision.
  final JsUiCanvasSceneRegistry canvasSceneRegistry = JsUiCanvasSceneRegistry();
  JsUiError? _error;
  JsUiLoadMetrics? _lastLoadMetrics;
  _JsUiLoadConfig _loadConfig = _JsUiLoadConfig.copy();
  bool _loading = false;
  bool _disposed = false;
  bool _notifierDisposed = false;
  Future<void>? _closeFuture;
  bool _timerPumpRunning = false;
  int _loadRequestId = 0;
  int _pageRevision = 0;
  Timer? _timerPump;

  /// Engine currently executing the page.
  JsEngine? get engine => _session.engine;

  /// Plugin currently loaded by the page.
  JsPlugin? get plugin => _session.plugin;

  /// Host features installed for the current page.
  List<JsFeatures> get features => _session.features;

  /// Current immutable root props.
  Map<String, Object?> get props => _session.props;

  /// Current JavaScript page state.
  Object? get state => _session.state;

  /// Most recently rendered UI tree.
  JsUiNode? get node => _session.node;

  /// Most recent page error.
  JsUiError? get error => _error;

  /// Timing metrics for the most recent successful load.
  JsUiLoadMetrics? get lastLoadMetrics => _lastLoadMetrics;

  /// Monotonically identifies the JS page instance currently owned by this
  /// controller. It changes only after a page replacement succeeds.
  int get pageRevision => _pageRevision;

  void _acceptLoadMetrics(JsUiLoadMetrics? metrics) {
    if (metrics == null) return;
    _lastLoadMetrics = metrics;
  }

  /// Whether the controller currently holds an error.
  bool get hasError => _error != null;

  /// Whether a page load or replacement is in progress.
  bool get isLoading => _loading;

  /// Whether the controller has begun shutdown.
  bool get isDisposed => _disposed;

  /// Loads an already-created page [plugin].
  Future<void> loadPlugin(
    JsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<JsFeatures> features = const <JsFeatures>[],
    Iterable<String> grantedPermissions = const <String>[],
    JsUiPermissionPolicy? permissionPolicy,
    JsUiErrorContext errorContext = const JsUiErrorContext(),
    bool notifyLoading = true,
  }) async {
    _loadConfig = _JsUiLoadConfig.copy(
      plugin: plugin,
      initialProps: initialProps,
      features: features,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
    );
    final requestId = ++_loadRequestId;
    await _loadPlugin(
      plugin,
      requestId: requestId,
      initialProps: initialProps,
      features: features,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
      notifyLoading: notifyLoading,
    );
  }

  /// Loads a page plugin produced asynchronously by [loader].
  Future<void> load(
    JsUiPluginLoader loader, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<JsFeatures> features = const <JsFeatures>[],
    Iterable<String> grantedPermissions = const <String>[],
    JsUiPermissionPolicy? permissionPolicy,
    JsUiErrorContext errorContext = const JsUiErrorContext(),
    bool notifyLoading = true,
  }) async {
    _ensureActive();
    _loadConfig = _JsUiLoadConfig.copy(
      loader: loader,
      initialProps: initialProps,
      features: features,
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
        features: features,
        grantedPermissions: grantedPermissions,
        permissionPolicy: permissionPolicy,
      );
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _acceptPageReplacement();
      final metrics = _session.lastLoadMetrics;
      _acceptLoadMetrics(
        metrics?.withStage('resourceLoad', resourceWatch.elapsed),
      );
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(error, kind: JsUiErrorKind.load, context: errorContext);
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  Future<void> _loadPlugin(
    JsPlugin plugin, {
    required int requestId,
    required Map<String, Object?> initialProps,
    required List<JsFeatures> features,
    required Iterable<String> grantedPermissions,
    required JsUiPermissionPolicy? permissionPolicy,
    required JsUiErrorContext errorContext,
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
        features: features,
        grantedPermissions: grantedPermissions,
        permissionPolicy: permissionPolicy,
      );
      _acceptLoadMetrics(_session.lastLoadMetrics);
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _acceptPageReplacement();
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(error, kind: JsUiErrorKind.load, context: errorContext);
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Dispatches one component [event] and renders any resulting state change.
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
        kind: JsUiErrorKind.dispatch,
        action: '${event['method'] ?? event['action'] ?? 'unknown'}',
      );
      notifyListeners();
    }
  }

  /// Dispatches [events] in one serialized session operation.
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
      _recordError(error, kind: JsUiErrorKind.dispatch);
      notifyListeners();
    }
  }

  /// Merges [patch] into page state and renders the result.
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
      _recordError(error, kind: JsUiErrorKind.state);
      notifyListeners();
    }
  }

  /// Renders the page again without changing its props or state.
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
      _recordError(error, kind: JsUiErrorKind.render);
      notifyListeners();
    }
  }

  /// Sends an application or widget lifecycle event to the page.
  Future<void> lifecycle(
    JsUiLifecycle type, {
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
      _recordError(error, kind: JsUiErrorKind.lifecycle, lifecycle: type.name);
      notifyListeners();
    }
  }

  /// Sends a navigation lifecycle event to the page.
  Future<void> routeLifecycle(
    JsUiLifecycle type, {
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
      _recordError(error, kind: JsUiErrorKind.lifecycle, lifecycle: type.name);
      notifyListeners();
    }
  }

  /// Records an externally detected page [error].
  void reportError(Object error) {
    _ensureActive();
    _recordError(error, kind: JsUiErrorKind.unknown);
    notifyListeners();
  }

  /// Captures the current page state for diagnostics.
  JsUiPageSnapshot exportPageSnapshot() {
    return inspector.buildSnapshot(
      props: props,
      state: state,
      node: node,
      plugin: plugin,
      features: _session.features,
      error: error,
    );
  }

  /// Adds an application lifecycle event to the inspector journal.
  void recordAppLifecycle(String type, {Object? payload}) {
    inspector.recordLifecycle('app', type, payload: payload);
  }

  /// Records [event] when resource logging is enabled.
  void recordNetworkLog(JsUiNetworkLogEvent event) {
    if (devOptions.logResources) {
      inspector.recordNetworkEvent(event);
    }
  }

  /// Restarts execution of the current plugin without fetching it again.
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
          throw StateError('JsUiController has no page to restart');
        }
        await _session.loadPlugin(
          configuredPlugin,
          initialProps: config.initialProps,
          features: config.features,
          grantedPermissions: config.grantedPermissions,
          permissionPolicy: config.permissionPolicy,
        );
      }
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _acceptPageReplacement();
      _startTimerPump();
    } catch (error) {
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _recordError(
        error,
        kind: JsUiErrorKind.load,
        context: _loadConfig.errorContext,
      );
    } finally {
      if (!_disposed && requestId == _loadRequestId) {
        _loading = false;
        notifyListeners();
      }
    }
  }

  /// Reloads the page source and optionally restores its prior state.
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
        features: config.features,
        grantedPermissions: config.grantedPermissions,
        permissionPolicy: config.permissionPolicy,
      );
      if (_disposed || requestId != _loadRequestId) {
        return;
      }
      _acceptPageReplacement();
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
        kind: JsUiErrorKind.load,
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
  /// Starts asynchronous shutdown and releases notifier listeners.
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
    canvasSceneRegistry.clear();
    return _closeFuture = _session.dispose();
  }

  void _acceptPageReplacement() {
    canvasSceneRegistry.clear();
    _pageRevision += 1;
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
      _recordError(error, kind: JsUiErrorKind.runtime);
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
      throw StateError('JsUiController is disposed');
    }
  }

  void _recordError(
    Object error, {
    required JsUiErrorKind kind,
    String? action,
    String? lifecycle,
    JsUiErrorContext context = const JsUiErrorContext(),
  }) {
    final cause = error is JsUiError ? error.cause : error;
    final resolvedKind = switch (cause) {
      JsUiNetworkException() => JsUiErrorKind.network,
      JsUiPermissionException() => JsUiErrorKind.permission,
      FormatException() when kind == JsUiErrorKind.load =>
        JsUiErrorKind.resource,
      _ => kind,
    };
    final unified = JsUiError.wrap(
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

final class _JsUiLoadConfig {
  factory _JsUiLoadConfig.copy({
    JsUiPluginLoader? loader,
    JsPlugin? plugin,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<JsFeatures> features = const <JsFeatures>[],
    Iterable<String> grantedPermissions = const <String>[],
    JsUiPermissionPolicy? permissionPolicy,
    JsUiErrorContext errorContext = const JsUiErrorContext(),
  }) {
    return _JsUiLoadConfig._(
      loader: loader,
      plugin: plugin,
      initialProps: Map<String, Object?>.unmodifiable(initialProps),
      features: List<JsFeatures>.unmodifiable(features),
      grantedPermissions: Set<String>.unmodifiable(grantedPermissions),
      permissionPolicy: permissionPolicy,
      errorContext: errorContext,
    );
  }

  const _JsUiLoadConfig._({
    required this.loader,
    required this.plugin,
    required this.initialProps,
    required this.features,
    required this.grantedPermissions,
    required this.permissionPolicy,
    required this.errorContext,
  });

  final JsUiPluginLoader? loader;
  final JsPlugin? plugin;
  final Map<String, Object?> initialProps;
  final List<JsFeatures> features;
  final Set<String> grantedPermissions;
  final JsUiPermissionPolicy? permissionPolicy;
  final JsUiErrorContext errorContext;
}
