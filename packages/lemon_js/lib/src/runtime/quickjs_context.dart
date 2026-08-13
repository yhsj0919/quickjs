import 'dart:async';

import '../backend/quickjs_backend.dart';
import '../backend/quickjs_backend_factory.dart';
import '../diagnostics/quickjs_exception.dart';
import 'quickjs.dart';
import 'quickjs_plugin.dart';
import 'quickjs_runtime_base.dart';
import 'quickjs_runtime_options.dart';

/// A long-lived QuickJS runtime that can host isolated JavaScript contexts.
///
/// Native platforms place child contexts in one shared `JSRuntime`. Backends
/// without multi-context support preserve the same isolation contract by
/// creating an independent backend runtime for each context.
final class JsRuntime {
  JsRuntime._(this._backend, this._root, this.options);

  final QuickjsBackend _backend;
  final QuickjsJsRuntimeBase _root;
  final Set<JsContext> _contexts = <JsContext>{};
  final JsOptions options;
  bool _closed = false;
  Future<void>? _disposeFuture;
  int _nextCallbackId = 1;

  static Future<JsRuntime> create({
    JsOptions options = const JsOptions(),
  }) async {
    final backend = await createQuickjsBackend();
    final root = await backend.createRuntime(options);
    return JsRuntime._(backend, root, options);
  }

  String get quickjsVersion => _backend.quickjsVersion;
  bool get closed => _closed;

  /// Number of live child contexts, primarily useful for capacity diagnostics.
  int get activeContextCount => _contexts.length;

  /// Creates a context with an independent global object and module registry.
  Future<JsContext> createContext({
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsProvider> providers = const <JsProvider>[],
    List<JsFeatures> features = const <JsFeatures>[],
    List<JsPlugin> plugins = const <JsPlugin>[],
    JsConsoleSink? onConsole,
  }) async {
    _ensureOpen();
    final contextRuntimeOptions = JsOptions(
      memoryLimitBytes: options.memoryLimitBytes,
      stackLimitBytes: options.stackLimitBytes,
      maxPendingTasks: options.maxPendingTasks,
    );
    late final _QuickjsContextRuntimeAdapter adapter;
    if (_root case final QuickjsMultiContextRuntimeBase multi) {
      final id = await multi.createContext();
      adapter = _QuickjsContextRuntimeAdapter.shared(this, multi, id);
    } else {
      final isolated = await _backend.createRuntime(contextRuntimeOptions);
      adapter = _QuickjsContextRuntimeAdapter.isolated(this, isolated);
    }
    final context = JsContext._(this, adapter);
    _contexts.add(context);
    try {
      context._engine = await Quickjs.attachContext(
        _backend,
        adapter,
        options: contextRuntimeOptions,
        moduleLoader: moduleLoader,
        scripts: scripts,
        modules: modules,
        providers: providers,
        features: features,
        plugins: plugins,
        onConsole: onConsole,
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

  void _detach(JsContext context) => _contexts.remove(context);

  int _allocateCallbackId() => _nextCallbackId++;

  void _ensureOpen() {
    if (_closed) throw JsRuntimeClosedException();
  }
}

/// An isolated JavaScript global and module namespace owned by a runtime.
final class JsContext implements JsPluginHost {
  JsContext._(this._owner, this._adapter);

  final JsRuntime _owner;
  final _QuickjsContextRuntimeAdapter _adapter;
  late final Quickjs _engine;
  bool _closed = false;
  Future<void>? _disposeFuture;

  bool get closed => _closed;

  Future<Object?> eval(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) {
    _ensureOpen();
    return _engine.eval(code, timeout: timeout, name: name, globals: globals);
  }

  Future<Object?> run(
    String code, {
    Duration? timeout,
    String name = '<run>',
    Map<String, Object?> globals = const {},
  }) {
    _ensureOpen();
    return _engine.run(code, timeout: timeout, name: name, globals: globals);
  }

  Future<String> evalRaw(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) {
    _ensureOpen();
    return _engine.evalRaw(
      code,
      timeout: timeout,
      name: name,
      globals: globals,
    );
  }

  Future<String> runRaw(
    String code, {
    Duration? timeout,
    String name = '<run>',
    Map<String, Object?> globals = const {},
  }) {
    _ensureOpen();
    return _engine.runRaw(code, timeout: timeout, name: name, globals: globals);
  }

  /// Calls a function stored on this context's `globalThis`.
  Future<Object?> call(String method, List<Object?> args, {Duration? timeout}) {
    _ensureOpen();
    return _engine.call(method, args, timeout: timeout);
  }

  /// Calls a global function and returns the raw QuickJS bridge string.
  Future<String> callRaw(
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callRaw(method, args, timeout: timeout);
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
  Future<void> injectFunction(
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
    await _engine.injectFunction(name, callback);
  }

  /// Injects a Dart stream as a JavaScript async iterable in this context.
  Future<void> injectStream<T>(String name, Stream<T> stream) {
    _ensureOpen();
    return _engine.injectStream(name, stream);
  }

  /// Installs a JavaScript `{emit, close, error}` sink in this context.
  Future<Stream<Object?>> bindStream(String name) {
    _ensureOpen();
    if (!RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name)) {
      throw ArgumentError.value(
        name,
        'name',
        'must be a JavaScript identifier',
      );
    }
    return _engine.bindStream(name);
  }

  @override
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout}) {
    _ensureOpen();
    return _engine.validatePlugin(plugin, timeout: timeout);
  }

  @override
  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.initPlugin(plugin, context: context, timeout: timeout);
  }

  @override
  Future<Object?> callPlugin(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callPlugin(plugin, method, args, timeout: timeout);
  }

  @override
  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout}) {
    _ensureOpen();
    return _engine.disposePlugin(plugin, timeout: timeout);
  }

  /// Installs a capability bundle directly into this context.
  Future<void> loadFeatures(
    JsFeatures features, {
    JsFeaturesConflictPolicy conflictPolicy = JsFeaturesConflictPolicy.reject,
  }) {
    _ensureOpen();
    return _engine.loadFeatures(features, conflictPolicy: conflictPolicy);
  }

  /// Features, validates and optionally initializes a dynamic plugin in place.
  Future<void> loadPlugin(
    JsPlugin plugin, {
    bool initialize = true,
    Map<String, Object?> initContext = const <String, Object?>{},
    Duration? timeout,
  }) async {
    _ensureOpen();
    await loadFeatures(plugin.asFeatures());
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

  final JsRuntime _owner;
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
    String name = '<run>',
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
