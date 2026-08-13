import 'dart:async';

import 'package:lemon_js/lemon_js.dart';

import 'quickjs_ui_helpers.dart';

/// Application-scoped QuickJS runtime shared by dynamic UI page contexts.
///
/// `init()` starts one native worker and one QuickJS `JSRuntime`. Every lease
/// creates a fresh `JSContext`, so pages share startup cost and immutable native
/// runtime infrastructure without sharing globals, modules, callbacks or timers.
final class QuickjsUiRuntime {
  QuickjsUiRuntime({
    this.idleCapacity = 1,
    this.maxCapacity = 2,
    this.runtimeOptions = const JsOptions(),
    this.features = const <JsFeatures>[],
    this.onConsole,
  }) : assert(idleCapacity >= 0),
       assert(maxCapacity > 0);

  /// Retained for source compatibility; contexts are disposed, not pooled.
  final int idleCapacity;
  final int maxCapacity;
  final JsOptions runtimeOptions;
  final List<JsFeatures> features;
  final JsConsoleSink? onConsole;

  final Set<QuickjsUiRuntimeLease> _active = <QuickjsUiRuntimeLease>{};
  Future<JsRuntime>? _initFuture;
  bool _disposed = false;

  bool get isInitialized => _initFuture != null && !_disposed;
  bool get isDisposed => _disposed;
  int get idleCount => 0;
  int get activeCount => _active.length;

  /// Starts the shared worker/runtime. Concurrent calls share one future.
  Future<void> init({int? capacity}) async {
    if (_disposed) throw StateError('QuickjsUiRuntime is disposed');
    await (_initFuture ??= JsRuntime.create(options: runtimeOptions));
  }

  Future<QuickjsUiRuntimeLease> acquire({
    List<JsFeatures> features = const <JsFeatures>[],
    JsPlugin? pagePlugin,
  }) async {
    if (_disposed) throw StateError('QuickjsUiRuntime is disposed');
    if (_active.length >= maxCapacity) {
      throw StateError('QuickjsUiRuntime capacity exhausted');
    }
    await init();
    final runtime = await _initFuture!;
    final context = await runtime.createContext(
      features: <JsFeatures>[
        quickjsUiHelperMount,
        ...this.features,
        ...features,
        if (pagePlugin != null) pagePlugin.asFeatures(name: 'quickjs_ui:page'),
      ],
      onConsole: onConsole,
    );
    final lease = QuickjsUiRuntimeLease._(this, context);
    _active.add(lease);
    return lease;
  }

  Future<void> _release(QuickjsUiRuntimeLease lease) async {
    if (!_active.remove(lease)) return;
    await lease.context.dispose();
  }

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

/// Exclusive page context returned by [QuickjsUiRuntime].
final class QuickjsUiRuntimeLease {
  QuickjsUiRuntimeLease._(this._runtime, this.context);

  final QuickjsUiRuntime _runtime;
  final JsContext context;
  bool _released = false;

  Future<void> release({bool reusable = true}) async {
    if (_released) return;
    _released = true;
    await _runtime._release(this);
  }
}
