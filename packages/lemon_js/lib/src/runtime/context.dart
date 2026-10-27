import 'dart:async';
import 'dart:convert';

import '../backend/backend.dart';
import '../backend/backend_factory.dart';
import '../diagnostics/exception.dart';
import 'engine.dart';
import 'plugin.dart';
import 'runtime_base.dart';
import 'runtime_options.dart';

/// A long-lived QuickJS runtime that can host isolated JavaScript contexts.
///
/// Native platforms place child contexts in one shared `JSRuntime`. Backends
/// without multi-context support preserve the same isolation contract by
/// creating an independent backend runtime for each context.
final class JsRuntime {
  JsRuntime._(this._backend, this._root, this.options);

  final JsBackend _backend;
  final JsJsRuntimeBase _root;
  final Set<JsContext> _contexts = <JsContext>{};

  /// 创建此 Runtime 时应用的资源与队列限制。
  final JsOptions options;
  bool _closed = false;
  Future<void>? _disposeFuture;
  int _nextCallbackId = 1;

  /// 创建一个可承载多个隔离 Context 的长期 Runtime。
  static Future<JsRuntime> create({
    JsOptions options = const JsOptions(),
  }) async {
    final backend = await createJsBackend();
    final root = await backend.createRuntime(options);
    return JsRuntime._(backend, root, options);
  }

  /// 底层 JavaScript Engine 的版本字符串。
  String get engineVersion => _backend.engineVersion;

  /// Runtime 是否已经进入关闭状态。
  bool get closed => _closed;

  /// Number of live child contexts, primarily useful for capacity diagnostics.
  int get activeContextCount => _contexts.length;

  /// Creates a context with an independent global object and module registry.
  Future<JsContext> createContext({
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsHostMethod> methods = const <JsHostMethod>[],
    List<JsFeatures> features = const <JsFeatures>[],
    List<JsPlugin> plugins = const <JsPlugin>[],

    /// 接收当前 context 的 JavaScript console 事件；未设置时不会向 Dart 转发。
    JsConsoleSink? onConsole,
  }) async {
    _ensureOpen();
    final contextRuntimeOptions = JsOptions(
      memoryLimitBytes: options.memoryLimitBytes,
      stackLimitBytes: options.stackLimitBytes,
      maxPendingTasks: options.maxPendingTasks,
      execution: options.execution,
    );
    late final _JsContextRuntimeAdapter adapter;
    if (_root case final JsMultiContextRuntimeBase multi) {
      final id = await multi.createContext();
      adapter = _JsContextRuntimeAdapter.shared(this, multi, id);
    } else {
      final isolated = await _backend.createRuntime(contextRuntimeOptions);
      adapter = _JsContextRuntimeAdapter.isolated(this, isolated);
    }
    final context = JsContext._(this, adapter);
    _contexts.add(context);
    try {
      context._engine = await createJsContextEngine(
        _backend,
        adapter,
        options: contextRuntimeOptions,
        moduleLoader: moduleLoader,
        scripts: scripts,
        modules: modules,
        methods: methods,
        features: features,
        plugins: plugins,
        onConsole: onConsole,
      );
      context._engineInitialized = true;
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

  /// 关闭所有子 Context 并释放底层 Runtime；重复调用返回同一 Future。
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
  final _JsContextRuntimeAdapter _adapter;
  late final JsEngine _engine;
  bool _engineInitialized = false;
  bool _closed = false;
  Future<void>? _disposeFuture;

  /// Context 是否已经进入关闭状态。
  bool get closed => _closed;

  /// Whether synchronous calls are available in this context.
  bool get supportsSync => _engine.supportsSync;

  /// Evaluates immediately in this context and converts the returned value.
  Object? evalSync(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.evalSync(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// Evaluates immediately and returns the raw bridge string.
  String evalRawSync(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.evalRawSync(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// Calls one global repeatedly through one ordered bridge request.
  Future<List<Object?>> callBatch(
    String method,
    List<List<Object?>> arguments, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callBatch(method, arguments, timeout: timeout);
  }

  /// Calls one global synchronously for a batch of argument lists.
  List<Object?> callBatchSync(
    String method,
    List<List<Object?>> arguments, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callBatchSync(method, arguments, timeout: timeout);
  }

  /// Calls a global function immediately without waiting for a Promise.
  Object? callSync(String method, List<Object?> args, {Duration? timeout}) {
    _ensureOpen();
    return _engine.callSync(method, args, timeout: timeout);
  }

  /// 同步求值 [code] 并将结构化结果转换为 Dart 值。
  Future<Object?> eval(
    String code, {

    /// 从任务入队开始计算的总时限，包含排队和 JavaScript 执行时间。
    Duration? timeout,

    /// 本次执行的源码名称，用于错误堆栈、诊断信息和 source map 匹配。
    String name = '<eval>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.eval(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// 求值 [code]、等待其 Promise 结果并转换为 Dart 值。
  Future<Object?> run(
    String code, {

    /// 从任务入队开始计算的总时限，包含排队、执行和等待 Promise 的时间。
    Duration? timeout,

    /// 本次执行的源码名称，用于错误堆栈、诊断信息和 source map 匹配。
    String name = '<run>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.run(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// 同步求值 [code] 并返回底层 Bridge 的原始字符串。
  Future<String> evalRaw(
    String code, {

    /// 从任务入队开始计算的总时限，包含排队和 JavaScript 执行时间。
    Duration? timeout,

    /// 本次执行的源码名称，用于错误堆栈、诊断信息和 source map 匹配。
    String name = '<eval>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.evalRaw(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// 求值 [code]、等待 Promise 并返回底层 Bridge 的原始字符串。
  Future<String> runRaw(
    String code, {

    /// 从任务入队开始计算的总时限，包含排队、执行和等待 Promise 的时间。
    Duration? timeout,

    /// 本次执行的源码名称，用于错误堆栈、诊断信息和 source map 匹配。
    String name = '<run>',
    Map<String, Object?> tempGlobals = const {},
  }) {
    _ensureOpen();
    return _engine.runRaw(
      code,
      timeout: timeout,
      name: name,
      tempGlobals: tempGlobals,
    );
  }

  /// Calls a function stored on this context's `globalThis`.
  ///
  /// [method] 仅按 `globalThis[method]` 单个属性解析；`app.run` 不会被拆分为
  /// 嵌套路径。[args] 支持结构化值编解码器可转换的 Dart 值。
  Future<Object?> call(String method, List<Object?> args, {Duration? timeout}) {
    _ensureOpen();
    return _engine.call(method, args, timeout: timeout);
  }

  /// Calls a global function and returns the raw QuickJS bridge string.
  ///
  /// [method] 仅按 `globalThis[method]` 单个属性解析；`app.run` 不会被拆分为
  /// 嵌套路径。[args] 支持结构化值编解码器可转换的 Dart 值。
  Future<String> callRaw(
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callRaw(method, args, timeout: timeout);
  }

  /// 以 [name] 为入口模块执行 [source]，并提供额外 [modules]。
  Future<String> runModule(
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

  /// Advances this context's JavaScript event loop once.
  ///
  /// Runs due timers and Promise jobs, then returns the delay until the next
  /// timer. A null result means that no timer is currently scheduled.
  ///
  /// Normal [run] and [call] requests do not need this. It is intended for
  /// long-lived hosts that must keep timers moving while no JavaScript request
  /// is active.
  Future<Duration?> pumpTimers() async {
    _ensureOpen();
    final milliseconds = await _adapter.pumpTimers();
    return milliseconds == null ? null : Duration(milliseconds: milliseconds);
  }

  /// Temporarily injects a Promise-returning Dart function into this context.
  /// Reusing [name] replaces and releases the previous callback. The function
  /// remains available until the context is disposed.
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
  /// It remains available until the context is disposed.
  Future<void> injectStream<T>(String name, Stream<T> stream) {
    _ensureOpen();
    return _engine.injectStream(name, stream);
  }

  /// Binds a JavaScript `{emit, close, error}` sink to a Dart stream.
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
  Future<Object?> callPluginExport(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    _ensureOpen();
    return _engine.callPluginExport(plugin, method, args, timeout: timeout);
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
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) async {
    _ensureOpen();
    await _engine.loadPlugin(
      plugin,
      initialize: initialize,
      context: context,
      timeout: timeout,
    );
  }

  /// 释放 Context 及其回调、插件和模块状态；重复调用返回同一 Future。
  Future<void> dispose() {
    final current = _disposeFuture;
    if (current != null) return current;
    _closed = true;
    _owner._detach(this);
    return _disposeFuture = _dispose();
  }

  Future<void> _dispose() async {
    if (_engineInitialized) {
      await _engine.dispose();
    } else {
      await _adapter.dispose();
    }
  }

  void _ensureOpen() {
    if (_closed || _owner.closed) throw JsRuntimeClosedException();
  }
}

/// Presents one child context through the existing single-runtime contract.
/// Callback ids are remapped because sibling `JsEngine` facades each start their
/// local registry at one while the native worker registry is runtime-wide.
final class _JsContextRuntimeAdapter
    implements
        JsJsRuntimeBase,
        JsInPlaceFeaturesRuntime,
        JsSyncRuntimeBase,
        JsInvocationRuntimeBase {
  _JsContextRuntimeAdapter.shared(this._owner, this._shared, this._contextId)
    : _isolated = null;

  _JsContextRuntimeAdapter.isolated(this._owner, this._isolated)
    : _shared = null,
      _contextId = null;

  final JsRuntime _owner;
  final JsMultiContextRuntimeBase? _shared;
  final int? _contextId;
  final JsJsRuntimeBase? _isolated;
  final Map<int, int> _callbackIds = <int, int>{};
  bool _closed = false;

  @override
  bool get supportsSync =>
      _shared is JsSyncMultiContextRuntimeBase ||
      (_isolated is JsSyncRuntimeBase &&
          (_isolated as JsSyncRuntimeBase).supportsSync);
  @override
  String evaluateSync(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) {
    _ensureOpen();
    if (_shared case final JsSyncMultiContextRuntimeBase sync) {
      return sync.evaluateContextSync(
        _contextId!,
        code,
        timeout: timeout,
        name: name,
      );
    }
    if (_isolated case final JsSyncRuntimeBase sync) {
      return sync.evaluateSync(code, timeout: timeout, name: name);
    }
    throw UnsupportedError(
      'Synchronous calls are not supported by this backend',
    );
  }

  @override
  Future<String> invoke(
    String requestJson, {
    bool awaitResult = false,
    Duration? timeout,
  }) {
    _ensureOpen();
    if (_shared case final JsMultiContextInvocationRuntimeBase calls) {
      return calls.invokeContext(
        _contextId!,
        requestJson,
        awaitResult: awaitResult,
        timeout: timeout,
      );
    }
    if (_isolated case final JsInvocationRuntimeBase calls) {
      return calls.invoke(
        requestJson,
        awaitResult: awaitResult,
        timeout: timeout,
      );
    }
    final code =
        'globalThis.__jsInvoke(${jsonEncode(requestJson)},$awaitResult)';
    return awaitResult
        ? evaluateAsync(code, timeout: timeout)
        : evaluate(code, timeout: timeout);
  }

  @override
  String invokeSync(String requestJson, {Duration? timeout}) {
    _ensureOpen();
    if (_shared case final JsMultiContextInvocationRuntimeBase calls) {
      return calls.invokeContextSync(
        _contextId!,
        requestJson,
        timeout: timeout,
      );
    }
    if (_isolated case final JsInvocationRuntimeBase calls) {
      return calls.invokeSync(requestJson, timeout: timeout);
    }
    return evaluateSync(
      'globalThis.__jsInvoke(${jsonEncode(requestJson)},false)',
      timeout: timeout,
    );
  }

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
    FutureOr<Object?> Function(List<Object?> args) callback,
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
    // A child owns only its context; cancelling it must leave siblings alive.
    await dispose();
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
