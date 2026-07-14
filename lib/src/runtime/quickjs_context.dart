import 'dart:async';

import '../backend/quickjs_backend.dart';
import '../backend/quickjs_backend_factory.dart';
import '../diagnostics/quickjs_exception.dart';
import 'quickjs.dart';
import 'quickjs_plugin.dart';
import 'quickjs_runtime_base.dart';
import 'quickjs_runtime_options.dart';

/// Capabilities and plugins installed only in one [QuickjsContext].
final class QuickjsContextOptions {
  const QuickjsContextOptions({
    this.moduleLoader,
    this.hostCapabilities = QuickjsHostCapabilities.none,
    this.environmentPatches = const <QuickjsHostScript>[],
    this.modules = const <QuickjsHostModule>[],
    this.providers = const <QuickjsHostProvider>[],
    this.mounts = const <QuickjsHostMount>[],
    this.plugins = const <QuickjsPlugin>[],
    this.onConsole,
  });

  final QuickjsModuleLoader? moduleLoader;
  final QuickjsHostCapabilities hostCapabilities;
  final List<QuickjsHostScript> environmentPatches;
  final List<QuickjsHostModule> modules;
  final List<QuickjsHostProvider> providers;
  final List<QuickjsHostMount> mounts;
  final List<QuickjsPlugin> plugins;
  final QuickjsConsoleSink? onConsole;

  QuickjsRuntimeOptions _runtimeOptions(QuickjsRuntimeOptions runtime) {
    return QuickjsRuntimeOptions(
      memoryLimitBytes: runtime.memoryLimitBytes,
      stackLimitBytes: runtime.stackLimitBytes,
      moduleLoader: moduleLoader,
      hostCapabilities: hostCapabilities,
      environmentPatches: environmentPatches,
      modules: modules,
      providers: providers,
      mounts: <QuickjsHostMount>[
        ...mounts,
        for (final plugin in plugins) plugin.asMount(),
      ],
    );
  }
}

/// A long-lived QuickJS runtime that can host isolated JavaScript contexts.
///
/// Native platforms place child contexts in one shared `JSRuntime`. Backends
/// without multi-context support preserve the same isolation contract by
/// creating an independent backend runtime for each context.
final class QuickjsRuntime {
  QuickjsRuntime._(this._backend, this._root, this.options);

  final QuickjsBackend _backend;
  final QuickjsJsRuntimeBase _root;
  final Set<QuickjsContext> _contexts = <QuickjsContext>{};
  final QuickjsRuntimeOptions options;
  bool _closed = false;
  Future<void>? _disposeFuture;
  int _nextCallbackId = 1;

  static Future<QuickjsRuntime> create({
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
  }) async {
    final backend = await createQuickjsBackend();
    final root = await backend.createRuntime(options);
    return QuickjsRuntime._(backend, root, options);
  }

  String get quickjsVersion => _backend.quickjsVersion;
  bool get closed => _closed;

  /// Number of live child contexts, primarily useful for capacity diagnostics.
  int get activeContextCount => _contexts.length;

  /// Creates a context with an independent global object and module registry.
  Future<QuickjsContext> createContext({
    QuickjsContextOptions options = const QuickjsContextOptions(),
  }) async {
    _ensureOpen();
    final contextRuntimeOptions = options._runtimeOptions(this.options);
    late final _QuickjsContextRuntimeAdapter adapter;
    if (_root case final QuickjsMultiContextRuntimeBase multi) {
      final id = await multi.createContext();
      adapter = _QuickjsContextRuntimeAdapter.shared(this, multi, id);
    } else {
      final isolated = await _backend.createRuntime(contextRuntimeOptions);
      adapter = _QuickjsContextRuntimeAdapter.isolated(this, isolated);
    }
    final context = QuickjsContext._(this, adapter);
    _contexts.add(context);
    try {
      context._engine = await Quickjs.attachContext(
        _backend,
        adapter,
        options: contextRuntimeOptions,
        onConsole: options.onConsole,
      );
    } catch (_) {
      _contexts.remove(context);
      rethrow;
    }
    if (_closed) {
      await context.dispose();
      throw JsRuntimeClosedException();
    }
    return context;
  }

  Future<void> dispose() {
    final current = _disposeFuture;
    if (current != null) return current;
    _closed = true;
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    final contexts = _contexts.toList(growable: false);
    for (final context in contexts) {
      await context.dispose();
    }
    await _root.dispose();
  }

  void _detach(QuickjsContext context) => _contexts.remove(context);

  int _allocateCallbackId() => _nextCallbackId++;

  void _ensureOpen() {
    if (_closed) throw JsRuntimeClosedException();
  }
}

/// An isolated JavaScript global and module namespace owned by a runtime.
final class QuickjsContext implements QuickjsPluginHost {
  QuickjsContext._(this._owner, this._adapter);

  final QuickjsRuntime _owner;
  final _QuickjsContextRuntimeAdapter _adapter;
  late final Quickjs _engine;
  bool _closed = false;
  Future<void>? _disposeFuture;

  bool get closed => _closed;

  Future<String> eval(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) {
    _ensureOpen();
    return _adapter.evaluate(code, timeout: timeout, name: name);
  }

  /// Evaluates code and awaits its Promise result while pumping timers/jobs.
  Future<String> evalAsync(
    String code, {
    Duration? timeout,
    String name = '<evalAsync>',
  }) {
    _ensureOpen();
    return _adapter.evaluateAsync(code, timeout: timeout, name: name);
  }

  Future<String> evalModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  }) {
    _ensureOpen();
    return _adapter.evaluateModule(
      source,
      name: name,
      modules: modules,
      timeout: timeout,
    );
  }

  /// Runs due native timers/jobs and reports when this context next needs work.
  /// Null means no timer is scheduled. Backends without native deadline
  /// inspection retain a bounded 500ms compatibility poll.
  Future<Duration?> pumpTimers() async {
    _ensureOpen();
    final milliseconds = await _adapter.pumpTimers();
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  /// Installs a Promise-returning Dart callback on this context's global object.
  Future<void> bindCallback(
    String name,
    FutureOr<Object?> Function(List<Object?> args) callback,
  ) async {
    _ensureOpen();
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'must be a JavaScript identifier',
      );
    }
    await _engine.bind(name, callback);
  }

  /// Installs a JavaScript `{emit, close, error}` sink in this context.
  Future<Stream<Object?>> bindJsSink(String name) {
    _ensureOpen();
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'must be a JavaScript identifier',
      );
    }
    return _engine.bindSink(name);
  }

  @override
  Future<void> validatePlugin(QuickjsPlugin plugin, {Duration? timeout}) {
    _ensureOpen();
    return _engine.validatePlugin(plugin, timeout: timeout);
  }

  @override
  Future<Object?> initPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.initPlugin(plugin, context: context, timeout: timeout);
  }

  @override
  Future<Object?> callPlugin(
    QuickjsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callPlugin(plugin, method, args, timeout: timeout);
  }

  @override
  Future<Object?> disposePlugin(QuickjsPlugin plugin, {Duration? timeout}) {
    _ensureOpen();
    return _engine.disposePlugin(plugin, timeout: timeout);
  }

  /// Installs a capability bundle directly into this context.
  Future<void> mount(
    QuickjsHostMount mount, {
    QuickjsHostMountConflictPolicy conflictPolicy =
        QuickjsHostMountConflictPolicy.reject,
  }) {
    _ensureOpen();
    return _engine.mount(mount, conflictPolicy: conflictPolicy);
  }

  /// Mounts, validates and optionally initializes a dynamic plugin in place.
  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    bool initialize = true,
    Map<String, Object?> initContext = const <String, Object?>{},
    Duration? timeout,
  }) async {
    _ensureOpen();
    await mount(plugin.asMount());
    await validatePlugin(plugin, timeout: timeout);
    if (initialize) {
      await initPlugin(plugin, context: initContext, timeout: timeout);
    }
  }

  Future<void> dispose() {
    final current = _disposeFuture;
    if (current != null) return current;
    _closed = true;
    _owner._detach(this);
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    await _engine.dispose();
  }

  void _ensureOpen() {
    if (_closed || _owner.closed) throw JsRuntimeClosedException();
  }
}

/// Presents one child context through the existing single-runtime contract.
/// Callback ids are remapped because sibling `Quickjs` facades each start their
/// local registry at one while the native worker registry is runtime-wide.
final class _QuickjsContextRuntimeAdapter
    implements QuickjsJsRuntimeBase, QuickjsInPlaceMountRuntime {
  _QuickjsContextRuntimeAdapter.shared(
    this._owner,
    this._shared,
    this._contextId,
  ) : _isolated = null;

  _QuickjsContextRuntimeAdapter.isolated(this._owner, this._isolated)
    : _shared = null,
      _contextId = null;

  final QuickjsRuntime _owner;
  final QuickjsMultiContextRuntimeBase? _shared;
  final int? _contextId;
  final QuickjsJsRuntimeBase? _isolated;
  final Map<int, int> _callbackIds = <int, int>{};
  bool _closed = false;

  @override
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) {
    _ensureOpen();
    final shared = _shared;
    return shared != null
        ? shared.evaluateContext(
            _contextId!,
            code,
            timeout: timeout,
            name: name,
          )
        : _isolated!.evaluate(code, timeout: timeout, name: name);
  }

  @override
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    String name = '<evalAsync>',
  }) {
    _ensureOpen();
    final shared = _shared;
    return shared != null
        ? shared.evaluateContextAsync(
            _contextId!,
            code,
            timeout: timeout,
            name: name,
          )
        : _isolated!.evaluateAsync(code, timeout: timeout, name: name);
  }

  @override
  Future<String> evaluateModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  }) {
    _ensureOpen();
    final shared = _shared;
    return shared != null
        ? shared.evaluateModuleContext(
            _contextId!,
            source,
            name: name,
            modules: modules,
          )
        : _isolated!.evaluateModule(
            source,
            name: name,
            modules: modules,
            timeout: timeout,
          );
  }

  Future<int?> pumpTimers() async {
    _ensureOpen();
    final shared = _shared;
    if (shared != null) {
      return shared.pumpContextTimers(_contextId!);
    }
    await _isolated!.evaluateAsync(
      'new Promise((resolve) => setTimeout(resolve, 0))',
      name: '<quickjs:timer-pump>',
    );
    return 500;
  }

  @override
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) async {
    _ensureOpen();
    final shared = _shared;
    if (shared == null) {
      await _isolated!.bindCallback(callbackId, name, callback);
      return;
    }
    final runtimeCallbackId = _owner._allocateCallbackId();
    await shared.bindContextCallback(
      _contextId!,
      runtimeCallbackId,
      name,
      callback,
    );
    _callbackIds[callbackId] = runtimeCallbackId;
  }

  @override
  Future<void> unbindCallback(int callbackId) async {
    final shared = _shared;
    if (shared == null) {
      await _isolated!.unbindCallback(callbackId);
      return;
    }
    final runtimeCallbackId = _callbackIds.remove(callbackId);
    if (runtimeCallbackId != null) {
      await shared.unbindContextCallback(_contextId!, runtimeCallbackId);
    }
  }

  @override
  Future<Stream<Object?>> bindJsSink(String name) {
    _ensureOpen();
    final shared = _shared;
    return shared != null
        ? shared.bindContextJsSink(_contextId!, name)
        : _isolated!.bindJsSink(name);
  }

  @override
  Future<void> stop() async {
    throw UnsupportedError(
      'Stopping one shared QuickJS context is not supported; dispose it instead',
    );
  }

  @override
  Future<void> dispose() async {
    if (_closed) return;
    _closed = true;
    final shared = _shared;
    if (shared != null) {
      for (final callbackId in _callbackIds.values) {
        await shared.unbindContextCallback(_contextId!, callbackId);
      }
      _callbackIds.clear();
      await shared.disposeContext(_contextId!);
    } else {
      await _isolated!.dispose();
    }
  }

  void _ensureOpen() {
    if (_closed || _owner.closed) throw JsRuntimeClosedException();
  }
}
