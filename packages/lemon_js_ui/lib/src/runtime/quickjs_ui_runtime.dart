import 'dart:async';

import 'package:lemon_js/lemon_js_context.dart';
import 'package:lemon_js/lemon_js_internal.dart';

import 'quickjs_ui_helpers.dart';

/// Application-scoped QuickJS runtime shared by dynamic UI page contexts.
///
/// `init()` starts one native worker and one QuickJS `JSRuntime`. Every lease
/// creates a fresh `JSContext`, so pages share startup cost and immutable native
/// runtime infrastructure without sharing globals, modules, callbacks or timers.
final class JsUiRuntime {
  /// Creates a shared runtime with bounded concurrent page contexts.
  JsUiRuntime({
    this.maxContexts = 2,
    this.options = const JsOptions(),
    this.features = const <JsFeatures>[],
    this.onConsole,
  }) : assert(maxContexts > 0);

  /// Maximum number of page contexts that may be active at the same time.
  final int maxContexts;

  /// Limits applied to the shared JavaScript runtime.
  final JsOptions options;

  /// Host features installed in every acquired page context.
  final List<JsFeatures> features;

  /// Receives console output from every acquired page context.
  final JsConsoleSink? onConsole;

  final Set<JsUiRuntimeLease> _active = <JsUiRuntimeLease>{};
  Future<JsRuntime>? _initFuture;
  bool _disposed = false;

  /// Whether initialization has started and the runtime remains usable.
  bool get isInitialized => _initFuture != null && !_disposed;

  /// Whether this runtime has been disposed.
  bool get isDisposed => _disposed;

  /// Number of currently leased page contexts.
  int get activeCount => _active.length;

  /// Starts the shared worker/runtime. Concurrent calls share one future.
  Future<void> init() async {
    if (_disposed) throw StateError('JsUiRuntime is disposed');
    await (_initFuture ??= JsRuntime.create(options: options));
  }

  /// Acquires a fresh isolated page context.
  Future<JsUiRuntimeLease> acquire({
    List<JsFeatures> features = const <JsFeatures>[],
    JsPlugin? pagePlugin,
  }) async {
    if (_disposed) throw StateError('JsUiRuntime is disposed');
    if (_active.length >= maxContexts) {
      throw StateError('JsUiRuntime capacity exhausted');
    }
    await init();
    final runtime = await _initFuture!;
    final context = await runtime.createContext(
      features: <JsFeatures>[
        jsUiHelperFeatures,
        ...this.features,
        ...features,
        if (pagePlugin != null) pagePlugin.asFeatures(name: 'quickjs_ui:page'),
      ],
      onConsole: onConsole,
    );
    final lease = JsUiRuntimeLease._(this, context);
    _active.add(lease);
    return lease;
  }

  Future<void> _release(JsUiRuntimeLease lease) async {
    if (!_active.remove(lease)) return;
    await lease.context.dispose();
  }

  /// Releases every active context and shuts down the shared runtime.
  Future<void> dispose() async {
    if (_disposed) return;
    _disposed = true;
    final leases = _active.toList(growable: false);
    _active.clear();
    await Future.wait(leases.map((lease) => lease.context.dispose()));
    final initFuture = _initFuture;
    if (initFuture != null) {
      final runtime = await initFuture;
      await runtime.dispose();
    }
  }
}

/// Exclusive page context returned by [JsUiRuntime].
final class JsUiRuntimeLease {
  JsUiRuntimeLease._(this._runtime, this.context);

  final JsUiRuntime _runtime;

  /// Exclusive JavaScript context owned by this lease.
  final JsContext context;
  bool _released = false;

  /// Releases the context; repeated calls have no effect.
  Future<void> release() async {
    if (_released) return;
    _released = true;
    await _runtime._release(this);
  }
}
