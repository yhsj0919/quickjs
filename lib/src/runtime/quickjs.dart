import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../backend/quickjs_backend.dart';
import '../backend/quickjs_backend_factory.dart';
import '../diagnostics/quickjs_exception.dart';
import 'quickjs_runtime_base.dart';
import 'quickjs_runtime_options.dart';
import '../diagnostics/quickjs_source_map.dart';
import 'quickjs_value.dart';

typedef QuickjsCallback = FutureOr<Object?> Function(List<Object?> args);
typedef QuickjsConsoleSink = FutureOr<void> Function(QuickjsConsoleEvent event);
typedef QuickjsObjectGetter = FutureOr<Object?> Function();
typedef QuickjsObjectSetter = FutureOr<void> Function(Object? value);
typedef QuickjsClassConstructor<T extends Object> =
    FutureOr<T> Function(List<Object?> args);
typedef QuickjsInstanceGetter<T extends Object> =
    FutureOr<Object?> Function(T instance);
typedef QuickjsInstanceSetter<T extends Object> =
    FutureOr<void> Function(T instance, Object? value);
typedef QuickjsInstanceMethod<T extends Object> =
    FutureOr<Object?> Function(T instance, List<Object?> args);

/// JavaScript console method severity.
enum QuickjsConsoleLevel { log, warn, error }

/// A single JavaScript `console.*` event emitted by one [Quickjs] runtime.
final class QuickjsConsoleEvent {
  const QuickjsConsoleEvent({
    required this.level,
    required this.text,
    required this.args,
    required this.timestamp,
  });

  final QuickjsConsoleLevel level;
  final String text;
  final List<Object?> args;
  final DateTime timestamp;
}

/// Explicit getter / setter descriptor for a Dart object proxy property.
final class QuickjsObjectAccessor {
  const QuickjsObjectAccessor({this.get, this.set});

  /// Called when JS reads the property. JS receives a Promise.
  final QuickjsObjectGetter? get;

  /// Called when JS writes the property.
  ///
  /// JavaScript setter syntax cannot return a Promise to the assignment
  /// expression, so async setter errors are not awaitable through `obj.prop = x`.
  final QuickjsObjectSetter? set;
}

/// Explicit descriptor for a Dart object exposed to JavaScript.
///
/// This first proxy slice intentionally avoids Dart reflection. Properties are
/// exposed as readonly enumerable JS properties, accessors as dynamic JS properties,
/// and methods as JS functions that return Promises through the existing
/// callback bridge.
final class QuickjsObjectProxy {
  const QuickjsObjectProxy({
    this.properties = const <String, Object?>{},
    this.accessors = const <String, QuickjsObjectAccessor>{},
    this.methods = const <String, QuickjsCallback>{},
  });

  final Map<String, Object?> properties;
  final Map<String, QuickjsObjectAccessor> accessors;
  final Map<String, QuickjsCallback> methods;
}

/// Explicit getter / setter descriptor for a Dart class instance property.
final class QuickjsInstanceAccessor<T extends Object> {
  const QuickjsInstanceAccessor({this.get, this.set});

  /// Called when JS reads the property. JS receives a Promise.
  final QuickjsInstanceGetter<T>? get;

  /// Called when JS writes the property.
  ///
  /// JavaScript setter syntax cannot return a Promise to the assignment
  /// expression, so async setter errors are not awaitable through `obj.prop = x`.
  final QuickjsInstanceSetter<T>? set;
}

/// Explicit descriptor for a Dart class exposed as a JavaScript constructor.
///
/// The constructor returns a JS instance synchronously, while the Dart instance
/// is created through the Promise callback bridge. Instance getters and methods
/// wait for that constructor Promise before touching the Dart instance.
final class QuickjsClass<T extends Object> {
  const QuickjsClass({
    required this.constructor,
    this.accessors = const {},
    this.methods = const {},
  });

  final QuickjsClassConstructor<T> constructor;
  final Map<String, QuickjsInstanceAccessor<T>> accessors;
  final Map<String, QuickjsInstanceMethod<T>> methods;
}

/// Runtime-owned handle to a JavaScript constructor binding.
final class QuickjsClassHandle {
  QuickjsClassHandle._(
    this._owner,
    this.name,
    this._classId,
    this._callbackNames,
    this._callbackIds,
  );

  final Quickjs _owner;
  final int _classId;
  final List<String> _callbackNames;
  final List<int> _callbackIds;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Global constructor name used in the owning runtime.
  final String name;

  /// Releases the JS constructor, hidden callbacks, and Dart instance table.
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }
    _disposed = true;
    return _disposeFuture = _owner._releaseClassBinding(
      name,
      _classId,
      _callbackNames,
      _callbackIds,
    );
  }

  /// Whether this Dart handle has been explicitly disposed.
  bool get disposed => _disposed;
}

/// Runtime-owned handle to a JavaScript object proxy.
final class QuickjsObjectHandle {
  QuickjsObjectHandle._(
    this._owner,
    this.name,
    this._stateName,
    this._callbackNames,
    this._callbackIds,
  );

  final Quickjs _owner;
  final String _stateName;
  final List<String> _callbackNames;
  final List<int> _callbackIds;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Global name used by the object proxy in the owning runtime.
  final String name;

  /// Releases the JS global proxy, hidden method callback globals, and runtime
  /// callback registry entries.
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }
    _disposed = true;
    return _disposeFuture = _owner._releaseObjectProxy(
      name,
      _stateName,
      _callbackNames,
      _callbackIds,
    );
  }

  /// Whether this Dart handle has been explicitly disposed.
  bool get disposed => _disposed;
}

/// Runtime-owned handle to a JavaScript function.
///
/// The Dart side only stores an opaque id. The actual function remains inside
/// the owning [Quickjs] runtime and is released when that runtime is disposed.
final class QuickjsFunctionHandle {
  QuickjsFunctionHandle._(this._owner, this.id);

  final Quickjs _owner;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Opaque handle id, unique within the owning runtime.
  final int id;

  /// Calls the referenced JavaScript function with [args].
  ///
  /// This path preserves synchronous interrupt semantics for long-running
  /// JavaScript. Use [callAsync] when the function returns a Promise.
  Future<String> call(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<String>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._callFunctionHandle(id, args, timeout: timeout);
  }

  /// Calls the referenced JavaScript function and awaits its result.
  ///
  /// This accepts both synchronous and Promise-returning JavaScript functions.
  /// The [timeout] covers the awaited Promise lifecycle. If the function may do
  /// long synchronous work before returning a Promise or reaching its first
  /// `await`, prefer [call] so the synchronous interrupt path can stop it.
  Future<String> callAsync(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<String>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._callFunctionHandleAsync(id, args, timeout: timeout);
  }

  /// Releases the JavaScript function from the owning runtime registry.
  ///
  /// Disposing a handle is idempotent. Disposing the owning runtime still
  /// releases all handles in bulk, so this is only needed for long-lived
  /// runtimes that create many short-lived handles.
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }
    _disposed = true;
    return _disposeFuture = _owner._releaseFunctionHandle(id);
  }

  /// Cancels the current runtime operation, matching [Quickjs.stop] semantics.
  Future<void> cancel() {
    return _owner.stop();
  }
}

/// `Quickjs` 实例当前可观察的生命周期状态。
enum QuickjsRuntimeState {
  /// Runtime 正在创建中。
  creating,

  /// Runtime 可接受并执行新的请求。
  ready,

  /// Runtime 正在执行一个 eval 请求。
  running,

  /// Runtime 正在停止当前请求并恢复可用状态。
  stopping,

  /// Runtime 已被 dispose，不能再使用。
  closed,

  /// Runtime worker 已崩溃或进入不可恢复失败状态。
  failed,
}

/// Conflict handling for [Quickjs.mount].
enum QuickjsHostMountConflictPolicy {
  /// Reject duplicate mount names or capability declarations.
  reject,

  /// Replace an existing runtime-installed mount with the same name.
  ///
  /// Mounts supplied through [QuickjsRuntimeOptions.mounts] remain immutable,
  /// and conflicts with other mounts are still rejected.
  replace,
}

/// Structured host-provider metadata exposed by the inspector prototype.
final class QuickjsHostProviderDebugInfo {
  const QuickjsHostProviderDebugInfo({
    required this.name,
    required this.debugName,
    required this.implementation,
  });

  final String name;
  final String debugName;
  final QuickjsHostProviderImplementation implementation;
}

/// Runtime debug snapshot exposed by the inspector prototype.
final class QuickjsInspectorSnapshot {
  const QuickjsInspectorSnapshot({
    required this.state,
    required this.quickjsVersion,
    required this.running,
    required this.pendingEvaluations,
    required this.registeredCallbacks,
    required this.registeredProviders,
    this.providerDetails = const <QuickjsHostProviderDebugInfo>[],
    required this.registeredMounts,
    required this.moduleNames,
    required this.sourceMapNames,
    required this.memoryLimitBytes,
    required this.stackLimitBytes,
    this.globals,
  });

  final QuickjsRuntimeState state;
  final String quickjsVersion;
  final bool running;
  final int pendingEvaluations;
  final List<String> registeredCallbacks;
  final List<String> registeredProviders;
  final List<QuickjsHostProviderDebugInfo> providerDetails;
  final List<String> registeredMounts;
  final List<String> moduleNames;
  final List<String> sourceMapNames;
  final int? memoryLimitBytes;
  final int? stackLimitBytes;
  final List<String>? globals;
}

/// QuickJS 的公开 Dart 入口。
///
/// 这个类只负责管理请求队列和 runtime 生命周期；真正的执行发生在平台 backend
/// 里，native 侧是 Dart isolate + FFI，web 侧是 Web Worker + WASM。
class Quickjs {
  Quickjs._(this._backend, this._runtime, this._options, this._onConsole);

  /// Creates a [Quickjs] wrapper around a supplied backend/runtime pair.
  ///
  /// This is intended for package tests that need deterministic control over
  /// runtime lifecycle transitions without depending on a real QuickJS worker.
  Quickjs.test(
    QuickjsBackend backend,
    QuickjsJsRuntimeBase runtime, {
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
    QuickjsConsoleSink? onConsole,
  }) : this._(backend, runtime, options, onConsole);

  final QuickjsBackend _backend;
  QuickjsJsRuntimeBase _runtime;
  final QuickjsRuntimeOptions _options;
  final QuickjsConsoleSink? _onConsole;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  QuickjsRuntimeState _state = QuickjsRuntimeState.ready;
  Object? _failure;
  Future<void>? _running;
  _QueuedEval? _runningRequest;
  Future<void>? _disposeFuture;
  Future<void>? _stopFuture;
  int _nextCallbackId = 1;
  int _nextObjectProxyId = 1;
  int _nextClassBindingId = 1;
  final Map<String, QuickjsSourceMap> _sourceMaps =
      <String, QuickjsSourceMap>{};
  final Map<int, String> _callbackDebugNames = <int, String>{};
  final Set<String> _moduleDebugNames = <String>{};
  final List<QuickjsHostMount> _runtimeMounts = <QuickjsHostMount>[];
  final Map<int, Map<int, Object>> _classInstances = <int, Map<int, Object>>{};
  final Set<QuickjsHostProviderContext> _pendingHostProviderCalls =
      <QuickjsHostProviderContext>{};

  /// 为当前平台创建一个独立的 QuickJS runtime。
  static Future<Quickjs> create({
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
    QuickjsConsoleSink? onConsole,
  }) async {
    final backend = await createQuickjsBackend();
    final runtime = await backend.createRuntime(options);
    final engine = Quickjs._(backend, runtime, options, onConsole);
    try {
      await engine._installConsoleOnCurrentRuntime();
      await engine._installHostEnvironmentOnCurrentRuntime();
    } catch (_) {
      await runtime.dispose();
      rethrow;
    }
    return engine;
  }

  /// 当前打包进插件的 QuickJS 版本号。
  String get quickjsVersion => _backend.quickjsVersion;

  /// 当前 runtime 生命周期状态。
  QuickjsRuntimeState get state => _state;

  /// Mounts a capability bundle and rebuilds the current runtime.
  ///
  /// The first runtime-mounting implementation is intentionally atomic: the
  /// runtime must be idle, the mount is validated against all existing static
  /// and runtime mounts, then the runtime is rebuilt. Existing JavaScript
  /// globals, module cache, bound callbacks, and handles are not preserved.
  /// Successfully mounted bundles are reinstalled by later [stop] rebuilds.
  /// [QuickjsHostMountConflictPolicy.replace] replaces only a same-name mount
  /// previously installed through this method; initialization mounts remain
  /// immutable and unrelated capability conflicts are still rejected.
  Future<void> mount(
    QuickjsHostMount mount, {
    QuickjsHostMountConflictPolicy conflictPolicy =
        QuickjsHostMountConflictPolicy.reject,
  }) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      throw terminalError;
    }
    if (_state != QuickjsRuntimeState.ready ||
        _running != null ||
        _queue.isNotEmpty ||
        _stopFuture != null) {
      throw StateError('QuickJS host mounts can only be installed while idle');
    }

    final mountName = _validateHostMountName(mount.name);
    final previousMounts = List<QuickjsHostMount>.of(_runtimeMounts);
    final staticMountExists = _options.mounts.any(
      (candidate) => _validateHostMountName(candidate.name) == mountName,
    );
    final runtimeMountIndex = _runtimeMounts.indexWhere(
      (candidate) => _validateHostMountName(candidate.name) == mountName,
    );
    if (conflictPolicy == QuickjsHostMountConflictPolicy.replace &&
        staticMountExists) {
      throw JsValueConversionException(
        'QuickJS initialization mount cannot be replaced at runtime: $mountName',
      );
    }
    final replacedMount =
        conflictPolicy == QuickjsHostMountConflictPolicy.replace &&
            runtimeMountIndex >= 0
        ? _runtimeMounts[runtimeMountIndex]
        : null;
    _validateMountAgainstLoadedModules(mount, replacedMount: replacedMount);
    if (conflictPolicy == QuickjsHostMountConflictPolicy.replace &&
        runtimeMountIndex >= 0) {
      _runtimeMounts[runtimeMountIndex] = mount;
    } else {
      _runtimeMounts.add(mount);
    }
    try {
      _validateStaticHostConfiguration();
    } catch (_) {
      _runtimeMounts
        ..clear()
        ..addAll(previousMounts);
      rethrow;
    }

    _state = QuickjsRuntimeState.stopping;
    final previousRuntime = _runtime;
    try {
      await previousRuntime.dispose();
      await _replaceCurrentRuntime();
      _state = QuickjsRuntimeState.ready;
    } catch (error, stackTrace) {
      try {
        await _runtime.dispose();
      } catch (_) {}
      _runtimeMounts
        ..clear()
        ..addAll(previousMounts);
      try {
        await _replaceCurrentRuntime();
        _state = QuickjsRuntimeState.ready;
      } catch (recoveryError) {
        try {
          await _runtime.dispose();
        } catch (_) {}
        _failure = recoveryError;
        _state = QuickjsRuntimeState.failed;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Registers a source map for generated JavaScript [sourceName].
  ///
  /// The [sourceName] should match the `name:` passed to eval/evaluate APIs or
  /// the module name used for module evaluation. The current registry phase
  /// attaches matching source maps to [JsException.sourceMap]; actual stack
  /// rewriting is handled by the later stack remap phase.
  void registerSourceMap(String sourceName, QuickjsSourceMap sourceMap) {
    _sourceMaps[_validateSourceName(sourceName)] = sourceMap;
  }

  /// Removes the source map registered for [sourceName].
  void unregisterSourceMap(String sourceName) {
    _sourceMaps.remove(_validateSourceName(sourceName));
  }

  /// Returns the source map registered for [sourceName], if any.
  QuickjsSourceMap? sourceMapFor(String sourceName) {
    return _sourceMaps[_validateSourceName(sourceName)];
  }

  /// Removes all source maps registered on this runtime wrapper.
  void clearSourceMaps() {
    _sourceMaps.clear();
  }

  /// Captures a lightweight inspector snapshot.
  ///
  /// When [includeGlobals] is true this queues a short JavaScript expression to
  /// read `globalThis` property names. Otherwise the snapshot is produced from
  /// Dart-side runtime metadata only.
  Future<QuickjsInspectorSnapshot> debugInspect({
    bool includeGlobals = false,
  }) async {
    final globals = includeGlobals
        ? await debugEvaluateValue(
            'Object.getOwnPropertyNames(globalThis).sort()',
            name: '<inspector:globals>',
          )
        : null;
    return QuickjsInspectorSnapshot(
      state: state,
      quickjsVersion: quickjsVersion,
      running: _running != null,
      pendingEvaluations: _queue.length,
      registeredCallbacks: List<String>.unmodifiable(
        _callbackDebugNames.values.toList()..sort(),
      ),
      registeredProviders: List<String>.unmodifiable(_debugProviderNames()),
      providerDetails: List<QuickjsHostProviderDebugInfo>.unmodifiable(
        _debugProviderDetails(),
      ),
      registeredMounts: List<String>.unmodifiable(_debugMountNames()),
      moduleNames: List<String>.unmodifiable(_debugModuleNames()),
      sourceMapNames: List<String>.unmodifiable(
        _sourceMaps.keys.toList()..sort(),
      ),
      memoryLimitBytes: _options.memoryLimitBytes,
      stackLimitBytes: _options.stackLimitBytes,
      globals: globals is List
          ? List<String>.unmodifiable(globals.map((value) => '$value'))
          : null,
    );
  }

  /// Evaluates a debug expression and converts its result to Dart values.
  ///
  /// This is the inspector's manual expression entry point. It uses the same
  /// queue, timeout, and conversion semantics as [evaluateValue].
  Future<Object?> debugEvaluateValue(
    String expression, {
    Duration? timeout,
    String name = '<inspector>',
  }) {
    return evaluateValue(expression, timeout: timeout, name: name);
  }

  /// 在当前 runtime 中执行 [code]。
  ///
  /// 调用只会入队，不会在 Flutter UI isolate 中同步执行 JS。
  /// [globals] 会在本次执行期间临时注入到 JS `globalThis`，执行结束后恢复。
  Future<String> eval(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) {
    final validName = _validateSourceName(name);
    return _enqueue(
      _wrapWithGlobals(code, globals, name: validName),
      timeout: timeout,
      name: validName,
    );
  }

  /// [eval] 的兼容别名，保留给更自然的调用命名。
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) {
    return eval(code, timeout: timeout, name: name, globals: globals);
  }

  /// 在当前 runtime 中执行异步 JavaScript 函数体，并等待返回的 Promise。
  ///
  /// [code] 会包裹在 `async () => { ... }` 中执行；需要返回值时使用 `return`。
  Future<String> evalAsync(
    String code, {
    Duration? timeout,
    String name = '<evalAsync>',
    Map<String, Object?> globals = const {},
  }) {
    final validName = _validateSourceName(name);
    return _enqueue(
      _wrapWithGlobals(_wrapAsyncFunctionBody(code), globals, name: validName),
      timeout: timeout,
      name: validName,
      async: true,
    );
  }

  /// [evalAsync] 的兼容别名。
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    String name = '<evalAsync>',
    Map<String, Object?> globals = const {},
  }) {
    return evalAsync(code, timeout: timeout, name: name, globals: globals);
  }

  /// 在当前 runtime 中执行 ES module [source]。
  ///
  /// 当前阶段只支持单个 module source 的 parse / evaluate，不解析静态 import。
  Future<String> evalModule(
    String source, {
    String name = '<module>',
    Duration? timeout,
  }) async {
    final validName = _validateModuleName(name);
    final modules = await _buildModuleGraph(
      source,
      validName,
      _esModuleSpecifiers,
      QuickjsHostModuleFormat.esModule,
    );
    _moduleDebugNames.addAll(modules.keys);
    return _enqueueModule(
      source,
      name: validName,
      modules: modules,
      timeout: timeout,
    );
  }

  /// [evalModule] 的兼容别名。
  Future<String> evaluateModule(
    String source, {
    String name = '<module>',
    Duration? timeout,
  }) {
    return evalModule(source, name: name, timeout: timeout);
  }

  /// Executes a minimal CommonJS module in the current runtime.
  ///
  /// This compatibility layer supports `require()`, `module.exports`, `exports`,
  /// relative path resolution, and a runtime-scoped CommonJS module cache. It is
  /// intentionally not a full Node/npm resolver.
  Future<String> evalCommonJs(
    String source, {
    String name = '<commonjs>',
    Duration? timeout,
  }) async {
    final validName = _validateModuleName(name);
    final modules = await _buildModuleGraph(
      source,
      validName,
      _commonJsSpecifiers,
      QuickjsHostModuleFormat.commonJs,
    );
    _moduleDebugNames.addAll(modules.keys);
    return _enqueue(
      _wrapCommonJsModule(source, validName, modules),
      timeout: timeout,
      name: validName,
    );
  }

  /// [evalCommonJs] 的兼容别名。
  Future<String> evaluateCommonJs(
    String source, {
    String name = '<commonjs>',
    Duration? timeout,
  }) {
    return evalCommonJs(source, name: name, timeout: timeout);
  }

  /// Evaluates [code] and stores the resulting JavaScript function as a handle.
  Future<QuickjsFunctionHandle> evaluateHandle(
    String code, {
    Duration? timeout,
    String name = '<handle>',
  }) async {
    final validName = _validateSourceName(name);
    final payloadJson = await _enqueue(
      _wrapEvaluateFunctionHandle(code, name: validName),
      timeout: timeout,
      name: validName,
    );
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
    if (payload['ok'] != true) {
      throw JsValueConversionException(payload['message']! as String);
    }
    return QuickjsFunctionHandle._(this, payload['id']! as int);
  }

  /// [evaluateHandle] 的兼容别名。
  Future<QuickjsFunctionHandle> evalHandle(
    String code, {
    Duration? timeout,
    String name = '<handle>',
  }) {
    return evaluateHandle(code, timeout: timeout, name: name);
  }

  /// 在 JS `globalThis` 上绑定一个 Promise-based Dart callback。
  ///
  /// JS 侧调用绑定函数时会得到 Promise；Dart callback 的返回值会 resolve 该 Promise，
  /// Dart callback 抛错会 reject 该 Promise。
  Future<void> bind(String name, QuickjsCallback callback) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<void>.error(terminalError);
    }
    final callbackId = _nextCallbackId++;
    final validName = _validateGlobalName(name);
    return _bindRuntimeCallback(callbackId, validName, (args) async {
      return callback(args);
    });
  }

  /// 在 JS `globalThis` 上绑定 `{ emit, close, error }`，并返回 Dart [Stream]。
  ///
  /// JS 侧每次 `await sink.emit(value)` 会等待 Dart 侧确认，用于串行 backpressure。
  /// Binds an explicit Dart object proxy on JS `globalThis`.
  ///
  /// [proxy.properties] become readonly enumerable properties.
  /// [proxy.accessors] become dynamic getter / setter descriptors.
  /// [proxy.methods] become JS functions that return Promises and route calls
  /// through the same callback bridge used by [bind].
  Future<QuickjsObjectHandle> bindObject(
    String name,
    QuickjsObjectProxy proxy,
  ) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<QuickjsObjectHandle>.error(terminalError);
    }
    final validName = _validateGlobalName(name);
    final propertyPayload = <String, Object>{};
    final propertyNames = <String>{};
    for (final entry in proxy.properties.entries) {
      final propertyName = _validateObjectProxyMemberName(entry.key);
      propertyNames.add(propertyName);
      propertyPayload[propertyName] = _encodeDartValue(
        entry.value,
        Set<Object>.identity(),
      );
    }

    final proxyId = _nextObjectProxyId++;
    final stateName = '__quickjsObjectProxy_${proxyId}_state';
    final accessors = <Map<String, String?>>[];
    final accessorNames = <String>{};
    final methods = <Map<String, String>>[];
    final methodNames = <String>{};
    final callbackNames = <String>[];
    final callbackIds = <int>[];
    var methodIndex = 1;
    for (final entry in proxy.accessors.entries) {
      final accessorName = _validateObjectProxyMemberName(entry.key);
      if (propertyNames.contains(accessorName)) {
        throw JsValueConversionException(
          'QuickJS object proxy member is defined more than once: $accessorName',
        );
      }
      if (!accessorNames.add(accessorName)) {
        throw JsValueConversionException(
          'QuickJS object proxy member is defined more than once: $accessorName',
        );
      }
      final descriptor = entry.value;
      if (descriptor.get == null && descriptor.set == null) {
        throw JsValueConversionException(
          'QuickJS object proxy accessor must define get or set: $accessorName',
        );
      }
      String? getCallbackName;
      final getter = descriptor.get;
      if (getter != null) {
        final callbackId = _nextCallbackId++;
        callbackIds.add(callbackId);
        getCallbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
        callbackNames.add(getCallbackName);
        await _bindRuntimeCallback(callbackId, getCallbackName, (_) async {
          return getter();
        });
      }
      String? setCallbackName;
      final setter = descriptor.set;
      if (setter != null) {
        final callbackId = _nextCallbackId++;
        callbackIds.add(callbackId);
        setCallbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
        callbackNames.add(setCallbackName);
        await _bindRuntimeCallback(callbackId, setCallbackName, (args) async {
          await setter(args.isEmpty ? null : args.first);
          return null;
        });
      }
      accessors.add({
        'name': accessorName,
        'getCallback': getCallbackName,
        'setCallback': setCallbackName,
      });
    }
    for (final entry in proxy.methods.entries) {
      final methodName = _validateObjectProxyMemberName(entry.key);
      if (propertyNames.contains(methodName) ||
          accessorNames.contains(methodName)) {
        throw JsValueConversionException(
          'QuickJS object proxy member is defined more than once: $methodName',
        );
      }
      if (!methodNames.add(methodName)) {
        throw JsValueConversionException(
          'QuickJS object proxy member is defined more than once: $methodName',
        );
      }
      final callbackId = _nextCallbackId++;
      callbackIds.add(callbackId);
      final callbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
      callbackNames.add(callbackName);
      await _bindRuntimeCallback(callbackId, callbackName, (args) async {
        return entry.value(args);
      });
      methods.add({'name': methodName, 'callback': callbackName});
    }

    await _enqueue(
      _wrapBindObjectProxy(
        validName,
        stateName,
        propertyPayload,
        accessors,
        methods,
      ),
    );
    return QuickjsObjectHandle._(
      this,
      validName,
      stateName,
      callbackNames,
      callbackIds,
    );
  }

  /// Binds an explicit Dart class as a JavaScript constructor.
  ///
  /// `new $name(...)` returns a JavaScript instance immediately. The Dart
  /// constructor runs through the Promise callback bridge, so instance getters
  /// and methods wait for construction before accessing the Dart instance.
  Future<QuickjsClassHandle> bindClass<T extends Object>(
    String name,
    QuickjsClass<T> definition,
  ) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<QuickjsClassHandle>.error(terminalError);
    }
    final validName = _validateGlobalName(name);
    final classId = _nextClassBindingId++;
    final instances = <int, Object>{};
    _classInstances[classId] = instances;

    final callbackNames = <String>[];
    final callbackIds = <int>[];
    final constructorCallbackName = '__quickjsClass_${classId}_constructor';
    final constructorCallbackId = _nextCallbackId++;
    callbackNames.add(constructorCallbackName);
    callbackIds.add(constructorCallbackId);
    await _bindRuntimeCallback(constructorCallbackId, constructorCallbackName, (
      args,
    ) async {
      if (args.isEmpty || args.first is! num) {
        throw StateError('QuickJS class constructor missing instance id');
      }
      final instanceId = (args.first! as num).toInt();
      final instance = await definition.constructor(args.skip(1).toList());
      instances[instanceId] = instance;
      return null;
    });

    final accessors = <Map<String, String?>>[];
    final accessorNames = <String>{};
    final methods = <Map<String, String>>[];
    final methodNames = <String>{};
    var callbackIndex = 1;
    for (final entry in definition.accessors.entries) {
      final accessorName = _validateObjectProxyMemberName(entry.key);
      if (!accessorNames.add(accessorName)) {
        throw JsValueConversionException(
          'QuickJS class member is defined more than once: $accessorName',
        );
      }
      final descriptor = entry.value;
      if (descriptor.get == null && descriptor.set == null) {
        throw JsValueConversionException(
          'QuickJS class accessor must define get or set: $accessorName',
        );
      }
      String? getCallbackName;
      final getter = descriptor.get;
      if (getter != null) {
        final callbackId = _nextCallbackId++;
        callbackIds.add(callbackId);
        getCallbackName = '__quickjsClass_${classId}_${callbackIndex++}';
        callbackNames.add(getCallbackName);
        await _bindRuntimeCallback(callbackId, getCallbackName, (args) async {
          final instance = _requireClassInstance<T>(classId, args);
          return getter(instance);
        });
      }
      String? setCallbackName;
      final setter = descriptor.set;
      if (setter != null) {
        final callbackId = _nextCallbackId++;
        callbackIds.add(callbackId);
        setCallbackName = '__quickjsClass_${classId}_${callbackIndex++}';
        callbackNames.add(setCallbackName);
        await _bindRuntimeCallback(callbackId, setCallbackName, (args) async {
          final instance = _requireClassInstance<T>(classId, args);
          await setter(instance, args.length < 2 ? null : args[1]);
          return null;
        });
      }
      accessors.add({
        'name': accessorName,
        'getCallback': getCallbackName,
        'setCallback': setCallbackName,
      });
    }
    for (final entry in definition.methods.entries) {
      final methodName = _validateObjectProxyMemberName(entry.key);
      if (accessorNames.contains(methodName)) {
        throw JsValueConversionException(
          'QuickJS class member is defined more than once: $methodName',
        );
      }
      if (!methodNames.add(methodName)) {
        throw JsValueConversionException(
          'QuickJS class member is defined more than once: $methodName',
        );
      }
      final callbackId = _nextCallbackId++;
      callbackIds.add(callbackId);
      final callbackName = '__quickjsClass_${classId}_${callbackIndex++}';
      callbackNames.add(callbackName);
      await _bindRuntimeCallback(callbackId, callbackName, (args) async {
        final instance = _requireClassInstance<T>(classId, args);
        return entry.value(instance, args.skip(1).toList());
      });
      methods.add({'name': methodName, 'callback': callbackName});
    }

    await _enqueue(
      _wrapBindClass(
        validName,
        classId,
        constructorCallbackName,
        accessors,
        methods,
      ),
    );
    return QuickjsClassHandle._(
      this,
      validName,
      classId,
      callbackNames,
      callbackIds,
    );
  }

  Future<Stream<Object?>> bindSink(String name) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<Stream<Object?>>.error(terminalError);
    }
    return _runtime.bindJsSink(_validateGlobalName(name));
  }

  Future<void> _installConsoleOnCurrentRuntime() async {
    const callbackName = '__quickjsConsoleCallback';
    final onConsole = _onConsole;
    if (onConsole != null) {
      final callbackId = _nextCallbackId++;
      await _bindRuntimeCallback(callbackId, callbackName, (args) async {
        final levelName = args.isNotEmpty ? args[0] : 'log';
        final text = args.length > 1 ? args[1] : '';
        final rawValue = args.length > 2 ? args[2] : null;
        final rawArgs = rawValue is List
            ? List<Object?>.from(rawValue)
            : const <Object?>[];
        final event = QuickjsConsoleEvent(
          level: _consoleLevelFromName('$levelName'),
          text: '$text',
          args: rawArgs,
          timestamp: DateTime.now(),
        );
        await onConsole(event);
        return null;
      });
    }
    await _runtime.evaluate(
      _wrapInstallConsole(onConsole == null ? null : callbackName),
    );
  }

  Future<void> _installHostEnvironmentOnCurrentRuntime() async {
    _validateStaticHostConfiguration();
    final capabilities = _effectiveHostCapabilities();
    if (!capabilities.isEmpty) {
      await _runtime.evaluate(
        _wrapInstallHostCapabilities(capabilities),
        name: '<quickjs:host-capabilities>',
      );
    }
    final providerNames = await _installHostProvidersOnCurrentRuntime();
    if (providerNames.isNotEmpty) {
      await _runtime.evaluate(
        _wrapInstallHostProviderRegistry(providerNames),
        name: '<quickjs:host-providers>',
      );
    }
    for (final script in _effectiveHostScripts()) {
      await _runtime.evaluate(
        script.source,
        name: _validateSourceName(script.name),
      );
    }
  }

  Future<Map<String, String>> _installHostProvidersOnCurrentRuntime() async {
    final providers = _effectiveHostProviders();
    if (providers.isEmpty) {
      return const <String, String>{};
    }
    final callbackNames = <String, String>{};
    final seen = <String>{};
    for (final provider in providers) {
      final providerName = _validateHostProviderName(provider.name);
      if (!seen.add(providerName)) {
        throw JsValueConversionException(
          'QuickJS host provider is already registered: $providerName',
        );
      }
      final callbackId = _nextCallbackId++;
      final callbackName = '__quickjsHostProvider_$callbackId';
      final debugName = provider.debugName ?? providerName;
      await _bindRuntimeCallback(
        callbackId,
        callbackName,
        (args) => _invokeHostProvider(provider, args),
        debugName: debugName,
      );
      callbackNames[providerName] = callbackName;
    }
    return callbackNames;
  }

  Future<Object?> _invokeHostProvider(
    QuickjsHostProvider provider,
    List<Object?> args,
  ) async {
    final context = QuickjsHostProviderContext();
    _pendingHostProviderCalls.add(context);
    final callbackFuture = Future<Object?>.sync(
      () => provider.callback(args, context),
    );
    final cancelledFuture = context.cancelled.then<Object?>((_) {
      throw context.cancellationReason ?? const JsCancelledException();
    });
    try {
      return await Future.any<Object?>(<Future<Object?>>[
        callbackFuture,
        cancelledFuture,
      ]);
    } finally {
      _pendingHostProviderCalls.remove(context);
    }
  }

  void _cancelHostProviderCalls(Object reason) {
    for (final context in _pendingHostProviderCalls.toList()) {
      context.cancel(reason);
    }
  }

  /// 在当前 runtime 中执行 [code]，并把基础 JS 值转换成 Dart 值。
  ///
  /// 当前阶段覆盖 number、boolean、string、null、undefined、BigInt、
  /// ArrayBuffer、Uint8Array、array 和 plain object。
  /// [globals] 会在本次执行期间临时注入到 JS `globalThis`，执行结束后恢复。
  Future<Object?> evaluateValue(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) async {
    final validName = _validateSourceName(name);
    final encodedSource = jsonEncode(
      _wrapWithGlobals(code, globals, name: validName),
    );
    final encodedValue = await eval(
      '''
(() => {
  const unsupported = (reason) => ({
    type: 'conversionError',
    message: 'QuickJS value cannot be converted to a Dart value: ' + reason,
  });
  const convert = (value, seen) => {
    if (value === undefined) {
      return { type: 'undefined' };
    }
    if (value === null) {
      return { type: 'null' };
    }
    const valueType = typeof value;
    if (valueType === 'bigint') {
      return { type: 'bigint', value: value.toString() };
    }
    if (valueType === 'number' || valueType === 'boolean' || valueType === 'string') {
      return { type: valueType, value };
    }
    if (valueType === 'symbol' || valueType === 'function') {
      return unsupported(valueType);
    }
    if (value instanceof ArrayBuffer) {
      return { type: 'bytes', value: Array.from(new Uint8Array(value)) };
    }
    if (value instanceof Uint8Array) {
      return { type: 'bytes', value: Array.from(value) };
    }
    if (valueType !== 'object') {
      return unsupported(valueType);
    }
    if (seen.has(value)) {
      return unsupported('circular reference');
    }
    seen.add(value);
    try {
      if (Array.isArray(value)) {
        const items = [];
        for (const item of value) {
          const converted = convert(item, seen);
          if (converted.type === 'conversionError') {
            return converted;
          }
          items.push(converted);
        }
        return { type: 'array', value: items };
      }
      const prototype = Object.getPrototypeOf(value);
      if (prototype === Object.prototype || prototype === null) {
        const entries = {};
        for (const key of Object.keys(value)) {
          const converted = convert(value[key], seen);
          if (converted.type === 'conversionError') {
            return converted;
          }
          entries[key] = converted;
        }
        return { type: 'object', value: entries };
      }
      return unsupported(Object.prototype.toString.call(value));
    } finally {
      seen.delete(value);
    }
  };
  const value = (0, eval)($encodedSource);
  return JSON.stringify(convert(value, new WeakSet()));
})()
''',
      timeout: timeout,
      name: validName,
    );
    final payload = jsonDecode(encodedValue) as Map<String, Object?>;
    if (payload['type'] == 'conversionError') {
      throw JsValueConversionException(payload['message']! as String);
    }
    return _normalizeStructuredValue(payload);
  }

  Object? _normalizeStructuredValue(Object? payload) {
    final typedPayload = payload as Map<String, Object?>;
    return switch (typedPayload['type']) {
      'undefined' => JsUndefined.value,
      'null' => null,
      'number' || 'boolean' || 'string' => typedPayload['value'],
      'bigint' => BigInt.parse(typedPayload['value']! as String),
      'bytes' => _normalizeBytes(typedPayload['value']),
      'array' => [
        for (final item in typedPayload['value']! as List)
          _normalizeStructuredValue(item),
      ],
      'object' => {
        for (final entry in (typedPayload['value']! as Map).entries)
          entry.key as String: _normalizeStructuredValue(entry.value),
      },
      final type => throw StateError('Unknown QuickJS value payload: $type'),
    };
  }

  /// 释放当前实例持有的 runtime。
  ///
  /// dispose 会立即拒绝新请求，取消尚未开始的队列任务，并等待正在执行的任务收尾。
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }

    final running = _running;
    final shouldCancelRunning = _runningRequest?.async == true;
    _state = QuickjsRuntimeState.closed;
    _classInstances.clear();
    _cancelHostProviderCalls(JsRuntimeClosedException());
    _cancelQueued(JsRuntimeClosedException());
    if (shouldCancelRunning) {
      unawaited(_runtime.stop());
    }
    _disposeFuture = (running ?? Future<void>.value()).then(
      (_) => _runtime.dispose(),
      onError: (Object _, StackTrace _) => _runtime.dispose(),
    );
    return _disposeFuture!;
  }

  /// 停止当前正在执行的 eval，并取消队列中的 eval。
  ///
  /// 完成后会重新创建底层 runtime，因此同一个 [Quickjs] 实例仍可继续使用。
  Future<void> stop() {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<void>.error(terminalError);
    }

    final currentStop = _stopFuture;
    if (currentStop != null) {
      return currentStop;
    }

    const cancellation = JsCancelledException();
    _cancelHostProviderCalls(cancellation);
    _cancelQueued(cancellation);
    final running = _running;
    if (running == null) {
      return Future<void>.value();
    }

    _state = QuickjsRuntimeState.stopping;
    final stopped = _runtime
        .stop()
        .then<void>(
          (_) => running,
          onError: (Object _, StackTrace _) => running,
        )
        .catchError((Object _) {})
        .then<void>((_) async {
          if (!_isTerminal) {
            await _replaceCurrentRuntime();
            _state = QuickjsRuntimeState.ready;
          }
        })
        .whenComplete(() {
          _stopFuture = null;
          _drainQueue();
        });
    _stopFuture = stopped;
    return stopped;
  }

  Future<void> _replaceCurrentRuntime() async {
    _classInstances.clear();
    _callbackDebugNames.clear();
    _moduleDebugNames.clear();
    _runtime = await _backend.createRuntime(_options);
    await _installConsoleOnCurrentRuntime();
    await _installHostEnvironmentOnCurrentRuntime();
  }

  Future<String> _enqueue(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    bool async = false,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }

    final request = _QueuedEval(code, timeout, name, async);
    _queue.add(request);
    // timeout 从入队开始计算，避免排队过久的任务进入 runtime 后才超时。
    request.startQueueTimer(() {
      if (_queue.remove(request)) {
        request.completeError(const JsTimeoutException());
      }
    });
    _drainQueue();
    return request.future;
  }

  Future<String> _enqueueModule(
    String source, {
    required String name,
    required Map<String, String> modules,
    Duration? timeout,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }
    final request = _QueuedModuleEval(source, name, modules, timeout);
    _queue.add(request);
    request.startQueueTimer(() {
      if (_queue.remove(request)) {
        request.completeError(const JsTimeoutException());
      }
    });
    _drainQueue();
    return request.future;
  }

  void _drainQueue() {
    if (_state != QuickjsRuntimeState.ready ||
        _running != null ||
        _stopFuture != null ||
        _queue.isEmpty) {
      return;
    }

    final request = _queue.removeFirst();
    _runningRequest = request;
    request.cancelQueueTimer();

    final timeout = request.remainingTimeout;
    if (timeout != null && timeout <= Duration.zero) {
      request.completeError(const JsTimeoutException());
      _drainQueue();
      return;
    }

    final running = Future<String>.sync(
      () => switch (request) {
        _QueuedModuleEval() => _runtime.evaluateModule(
          request.code,
          name: request.name,
          modules: request.modules,
          timeout: timeout,
        ),
        _ =>
          request.async
              ? _runtime.evaluateAsync(
                  request.code,
                  timeout: timeout,
                  name: request.name,
                )
              : _runtime.evaluate(
                  request.code,
                  timeout: timeout,
                  name: request.name,
                ),
      },
    );
    _state = QuickjsRuntimeState.running;
    // _running 代表当前占用 runtime 的任务；完成后再继续 drain，保证单 runtime
    // 不会被并发重入。
    _running = running.then<void>(
      request.complete,
      onError: (Object error, StackTrace stackTrace) {
        final effectiveError = _attachSourceMap(error, request.name);
        if (error is JsRuntimeClosedException ||
            error is JsRuntimeCrashException) {
          _state = error is JsRuntimeCrashException
              ? QuickjsRuntimeState.failed
              : QuickjsRuntimeState.closed;
          _failure = error;
          _cancelQueued(error);
        }
        request.completeError(effectiveError, stackTrace);
      },
    );
    unawaited(
      // 这里显式消费成功和失败，避免任务失败时产生未处理的异步错误。
      _running!.then<void>(
        (_) {
          _running = null;
          _runningRequest = null;
          if (_state == QuickjsRuntimeState.running) {
            _state = QuickjsRuntimeState.ready;
          }
          _drainQueue();
        },
        onError: (Object _, StackTrace _) {
          _running = null;
          _runningRequest = null;
          if (_state == QuickjsRuntimeState.running) {
            _state = QuickjsRuntimeState.ready;
          }
          _drainQueue();
        },
      ),
    );
  }

  void _cancelQueued(Object error) {
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      request.cancelQueueTimer();
      request.completeError(error);
    }
  }

  Object _attachSourceMap(Object error, String fallbackName) {
    if (error is! JsException) {
      return error;
    }
    final sourceName =
        error.fileName ??
        _firstRegisteredSourceNameIn(error.stack) ??
        fallbackName;
    final map = _sourceMaps[sourceName];
    if (map == null) {
      return error;
    }
    final remappedStack = _remapStack(error.stack);
    final location =
        _remapExceptionLocation(error, sourceName, map) ??
        remappedStack.location;
    return error.withSourceMap(
      map,
      stack: remappedStack.stack,
      fileName: location?.source,
      line: location?.line,
      column: location?.column,
    );
  }

  String? _firstRegisteredSourceNameIn(String? stack) {
    if (stack == null || _sourceMaps.isEmpty) {
      return null;
    }
    for (final sourceName in _sourceMaps.keys) {
      if (stack.contains(sourceName)) {
        return sourceName;
      }
    }
    return null;
  }

  _StackRemapResult _remapStack(String? stack) {
    if (stack == null || _sourceMaps.isEmpty) {
      return _StackRemapResult(stack: stack);
    }
    QuickjsSourceMapLocation? firstLocation;
    final remappedLines = <String>[];
    for (final line in stack.split('\n')) {
      var remappedLine = line;
      for (final entry in _sourceMaps.entries) {
        final pattern = RegExp('${RegExp.escape(entry.key)}:(\\d+):(\\d+)');
        remappedLine = remappedLine.replaceAllMapped(pattern, (match) {
          final generatedLine = int.parse(match.group(1)!);
          final generatedColumn = int.parse(match.group(2)!);
          final location = entry.value.lookup(
            line: generatedLine,
            column: _stackColumnToSourceMapColumn(generatedColumn),
          );
          if (location == null) {
            return match.group(0)!;
          }
          firstLocation ??= location;
          return '${location.source}:${location.line}:${location.column + 1}';
        });
      }
      remappedLines.add(remappedLine);
    }
    return _StackRemapResult(
      stack: remappedLines.join('\n'),
      location: firstLocation,
    );
  }

  QuickjsSourceMapLocation? _remapExceptionLocation(
    JsException error,
    String sourceName,
    QuickjsSourceMap sourceMap,
  ) {
    final line = error.line;
    final column = error.column;
    if (line == null || column == null) {
      return null;
    }
    return sourceMap.lookup(
      line: line,
      column: _stackColumnToSourceMapColumn(column),
    );
  }

  bool get _isTerminal =>
      _state == QuickjsRuntimeState.closed ||
      _state == QuickjsRuntimeState.failed;

  Object? get _terminalError {
    return switch (_state) {
      QuickjsRuntimeState.closed => JsRuntimeClosedException(),
      QuickjsRuntimeState.failed => _failure ?? JsRuntimeCrashException(),
      _ => null,
    };
  }

  Future<String> _callFunctionHandle(
    int handleId,
    List<Object?> args, {
    Duration? timeout,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }
    return _enqueue(_wrapFunctionHandleCall(handleId, args), timeout: timeout);
  }

  Future<String> _callFunctionHandleAsync(
    int handleId,
    List<Object?> args, {
    Duration? timeout,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }
    return _enqueue(
      _wrapAsyncFunctionBody(_wrapFunctionHandleCallAwait(handleId, args)),
      timeout: timeout,
      async: true,
    );
  }

  Future<void> _releaseFunctionHandle(int handleId) {
    if (_isTerminal) {
      return Future<void>.value();
    }
    return _enqueue(_wrapReleaseFunctionHandle(handleId)).then((_) {});
  }

  Future<void> _releaseObjectProxy(
    String name,
    String stateName,
    List<String> callbackNames,
    List<int> callbackIds,
  ) async {
    if (_isTerminal) {
      return;
    }
    await _enqueue(_wrapReleaseObjectProxy(name, stateName, callbackNames));
    for (final callbackId in callbackIds) {
      await _unbindRuntimeCallback(callbackId);
    }
  }

  T _requireClassInstance<T extends Object>(int classId, List<Object?> args) {
    if (args.isEmpty || args.first is! num) {
      throw StateError('QuickJS class instance id is missing');
    }
    final instanceId = (args.first! as num).toInt();
    final instance = _classInstances[classId]?[instanceId];
    if (instance == null) {
      throw StateError('QuickJS class instance is disposed');
    }
    if (instance is! T) {
      throw StateError('QuickJS class instance type mismatch');
    }
    return instance;
  }

  Future<void> _releaseClassBinding(
    String name,
    int classId,
    List<String> callbackNames,
    List<int> callbackIds,
  ) async {
    _classInstances.remove(classId);
    if (_isTerminal) {
      return;
    }
    await _enqueue(_wrapReleaseClassBinding(name, classId, callbackNames));
    for (final callbackId in callbackIds) {
      await _unbindRuntimeCallback(callbackId);
    }
  }

  Future<void> _bindRuntimeCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback, {
    String? debugName,
  }) async {
    await _runtime.bindCallback(callbackId, name, callback);
    _callbackDebugNames[callbackId] = debugName ?? name;
  }

  Future<void> _unbindRuntimeCallback(int callbackId) async {
    _callbackDebugNames.remove(callbackId);
    await _runtime.unbindCallback(callbackId);
  }

  Future<Map<String, String>> _buildModuleGraph(
    String rootSource,
    String rootName,
    Iterable<String> Function(String source) specifiers,
    QuickjsHostModuleFormat format,
  ) async {
    final configuredModules = _hostModuleSourceMap(format);
    final loader = _options.moduleLoader;
    final modules = <String, String>{rootName: rootSource};
    final visiting = <String>{};

    Future<void> visit(String moduleName) async {
      if (!visiting.add(moduleName)) {
        return;
      }
      final source = modules[moduleName];
      if (source == null) {
        visiting.remove(moduleName);
        return;
      }
      try {
        for (final specifier in specifiers(source)) {
          final resolved = _resolveModuleName(moduleName, specifier);
          if (modules.containsKey(resolved)) {
            continue;
          }
          final loaded =
              configuredModules[resolved] ?? await loader?.call(resolved);
          if (loaded == null) {
            throw JsValueConversionException(
              'QuickJS module loader could not resolve "$specifier" from "$moduleName"',
            );
          }
          modules[resolved] = loaded;
          await visit(resolved);
        }
      } finally {
        visiting.remove(moduleName);
      }
    }

    await visit(rootName);
    return Map<String, String>.unmodifiable(modules);
  }

  Map<String, String> _hostModuleSourceMap(QuickjsHostModuleFormat format) {
    final configuredModules = _effectiveHostModules();
    if (configuredModules.isEmpty) {
      return const <String, String>{};
    }
    final modules = <String, String>{};
    for (final module in configuredModules) {
      if (module.format != format) {
        continue;
      }
      final name = _canonicalModuleName(_validateModuleName(module.specifier));
      if (modules.containsKey(name)) {
        throw JsValueConversionException(
          'QuickJS host module is registered more than once: $name',
        );
      }
      modules[name] = module.source;
    }
    return Map<String, String>.unmodifiable(modules);
  }

  List<String> _debugModuleNames() {
    final names = <String>{..._moduleDebugNames};
    for (final module in _effectiveHostModules()) {
      names.add(_canonicalModuleName(_validateModuleName(module.specifier)));
    }
    return names.toList()..sort();
  }

  List<String> _debugProviderNames() {
    final names = <String>{
      for (final provider in _effectiveHostProviders())
        _validateHostProviderName(provider.name),
    };
    return names.toList()..sort();
  }

  List<QuickjsHostProviderDebugInfo> _debugProviderDetails() {
    final details = <QuickjsHostProviderDebugInfo>[
      for (final provider in _effectiveHostProviders())
        QuickjsHostProviderDebugInfo(
          name: _validateHostProviderName(provider.name),
          debugName: provider.debugName ?? provider.name,
          implementation: provider.implementation,
        ),
    ];
    details.sort((left, right) => left.name.compareTo(right.name));
    return details;
  }

  List<String> _debugMountNames() {
    return <String>[
      for (final mount in _allHostMounts) _validateHostMountName(mount.name),
    ]..sort();
  }

  void _validateStaticHostConfiguration() {
    final mountNames = <String>{};
    for (final mount in _allHostMounts) {
      final name = _validateHostMountName(mount.name);
      if (!mountNames.add(name)) {
        throw JsValueConversionException(
          'QuickJS host mount is registered more than once: $name',
        );
      }
    }

    final globalNames = <String>{};
    final capabilities = _effectiveHostCapabilities();
    if (capabilities.browserGlobals.window) {
      globalNames.add('window');
    }
    if (capabilities.browserGlobals.self) {
      globalNames.add('self');
    }

    final patchNames = <String>{};
    for (final patch in _effectiveHostScripts()) {
      final name = _validateSourceName(patch.name);
      if (!patchNames.add(name)) {
        throw JsValueConversionException(
          'QuickJS environment patch is registered more than once: $name',
        );
      }
      for (final declaredGlobal in patch.globals) {
        final globalName = _validateGlobalName(declaredGlobal);
        if (!globalNames.add(globalName)) {
          throw JsValueConversionException(
            'QuickJS host global is registered more than once: $globalName',
          );
        }
      }
    }

    final providerNames = <String>{};
    for (final provider in _effectiveHostProviders()) {
      final name = _validateHostProviderName(provider.name);
      if (!providerNames.add(name)) {
        throw JsValueConversionException(
          'QuickJS host provider is registered more than once: $name',
        );
      }
    }

    _hostModuleSourceMap(QuickjsHostModuleFormat.esModule);
    _hostModuleSourceMap(QuickjsHostModuleFormat.commonJs);
  }

  void _validateMountAgainstLoadedModules(
    QuickjsHostMount mount, {
    QuickjsHostMount? replacedMount,
  }) {
    final replaceableNames = <String>{
      if (replacedMount != null)
        for (final module in replacedMount.modules)
          _canonicalModuleName(_validateModuleName(module.specifier)),
    };
    for (final module in mount.modules) {
      final name = _canonicalModuleName(_validateModuleName(module.specifier));
      if (_moduleDebugNames.contains(name) &&
          !replaceableNames.contains(name)) {
        throw JsValueConversionException(
          'QuickJS loaded module cannot be shadowed by a runtime mount: $name',
        );
      }
    }
  }

  QuickjsHostCapabilities _effectiveHostCapabilities() {
    var window = _options.hostCapabilities.browserGlobals.window;
    var self = _options.hostCapabilities.browserGlobals.self;
    for (final mount in _allHostMounts) {
      final browserGlobals = mount.capabilities.browserGlobals;
      window = window || browserGlobals.window;
      self = self || browserGlobals.self;
    }
    return QuickjsHostCapabilities(
      browserGlobals: QuickjsBrowserGlobals(window: window, self: self),
    );
  }

  List<QuickjsHostScript> _effectiveHostScripts() {
    return <QuickjsHostScript>[
      for (final mount in _allHostMounts) ...mount.environmentPatches,
      ..._options.environmentPatches,
    ];
  }

  List<QuickjsHostProvider> _effectiveHostProviders() {
    return <QuickjsHostProvider>[
      for (final mount in _allHostMounts) ...mount.providers,
      ..._options.providers,
    ];
  }

  List<QuickjsHostModule> _effectiveHostModules() {
    return <QuickjsHostModule>[
      for (final mount in _allHostMounts) ...mount.modules,
      ..._options.modules,
    ];
  }

  Iterable<QuickjsHostMount> get _allHostMounts sync* {
    yield* _options.mounts;
    yield* _runtimeMounts;
  }
}

Uint8List _normalizeBytes(Object? value) {
  final bytes = value as List;
  return Uint8List.fromList([for (final byte in bytes) (byte as num).toInt()]);
}

QuickjsConsoleLevel _consoleLevelFromName(String name) {
  return switch (name) {
    'warn' => QuickjsConsoleLevel.warn,
    'error' => QuickjsConsoleLevel.error,
    _ => QuickjsConsoleLevel.log,
  };
}

String _wrapWithGlobals(
  String code,
  Map<String, Object?> globals, {
  required String name,
}) {
  final source = _appendSourceUrl(code, name);
  if (globals.isEmpty) {
    return source;
  }

  final encodedSource = jsonEncode(source);
  final encodedGlobals = jsonEncode(_encodeGlobals(globals));
  return '''
(() => {
  const inflate = (payload) => {
    switch (payload.type) {
      case 'null':
        return null;
      case 'number':
      case 'boolean':
      case 'string':
        return payload.value;
      case 'bytes':
        return new Uint8Array(payload.value);
      case 'array':
        return payload.value.map(inflate);
      case 'object': {
        const value = {};
        for (const key of Object.keys(payload.value)) {
          value[key] = inflate(payload.value[key]);
        }
        return value;
      }
      case 'date':
        return new Date(payload.value);
      default:
        throw new TypeError('Unknown Dart value payload: ' + payload.type);
    }
  };
  const globals = $encodedGlobals;
  const missing = Symbol('quickjs.missingGlobal');
  const previous = new Map();
  try {
    for (const key of Object.keys(globals)) {
      previous.set(
        key,
        Object.prototype.hasOwnProperty.call(globalThis, key)
          ? globalThis[key]
          : missing
      );
      globalThis[key] = inflate(globals[key]);
    }
    return (0, eval)($encodedSource);
  } finally {
    for (const [key, value] of previous) {
      if (value === missing) {
        delete globalThis[key];
      } else {
        globalThis[key] = value;
      }
    }
  }
})()
''';
}

String _wrapInstallConsole(String? callbackName) {
  if (callbackName == null) {
    return '''
(() => {
  const noop = () => undefined;
  globalThis.console = globalThis.console || {};
  console.log = console.warn = console.error = noop;
})()
''';
  }

  final encodedCallbackName = jsonEncode(callbackName);
  return '''
(() => {
  const callbackName = $encodedCallbackName;
  const normalize = (value, seen = new WeakSet()) => {
    if (value === undefined) return 'undefined';
    if (value === null || typeof value === 'number' ||
        typeof value === 'boolean' || typeof value === 'string') {
      return value;
    }
    if (typeof value === 'bigint') return value.toString() + 'n';
    if (typeof value === 'symbol') return String(value);
    if (typeof value === 'function') {
      return value.name ? '[Function ' + value.name + ']' : '[Function]';
    }
    if (value instanceof Error) {
      return {
        name: value.name || 'Error',
        message: value.message || '',
        stack: value.stack || null,
      };
    }
    if (value instanceof ArrayBuffer) {
      return { __quickjsType: 'bytes', value: Array.from(new Uint8Array(value)) };
    }
    if (ArrayBuffer.isView(value)) {
      return {
        __quickjsType: 'bytes',
        value: Array.from(new Uint8Array(value.buffer, value.byteOffset, value.byteLength)),
      };
    }
    if (Array.isArray(value)) {
      if (seen.has(value)) return '[Circular]';
      seen.add(value);
      const out = value.map((item) => normalize(item, seen));
      seen.delete(value);
      return out;
    }
    if (typeof value === 'object') {
      if (seen.has(value)) return '[Circular]';
      const prototype = Object.getPrototypeOf(value);
      if (prototype === Object.prototype || prototype === null) {
        seen.add(value);
        const out = {};
        for (const key of Object.keys(value)) {
          out[key] = normalize(value[key], seen);
        }
        seen.delete(value);
        return out;
      }
      try {
        return String(value);
      } catch (_) {
        return Object.prototype.toString.call(value);
      }
    }
    return String(value);
  };
  const format = (value) => {
    if (typeof value === 'string') return value;
    if (value === undefined) return 'undefined';
    if (typeof value === 'bigint') return value.toString() + 'n';
    if (typeof value === 'symbol' || typeof value === 'function') return String(value);
    if (value instanceof Error) {
      const header = (value.name || 'Error') + ': ' + (value.message || '');
      if (!value.stack) return header;
      return value.stack.includes(value.message || '') ? value.stack : header + '\\n' + value.stack;
    }
    const normalized = normalize(value);
    if (typeof normalized === 'string') return normalized;
    try {
      return JSON.stringify(normalized);
    } catch (_) {
      return String(value);
    }
  };
  const emit = (level, args) => {
    if (!callbackName) return;
    const callback = globalThis[callbackName];
    if (typeof callback !== 'function') return;
    const normalizedArgs = args.map((arg) => normalize(arg));
    const text = args.map((arg) => format(arg)).join(' ');
    try {
      const pending = callback(level, text, normalizedArgs);
      if (pending && typeof pending.catch === 'function') {
        pending.catch(() => {});
      }
    } catch (_) {}
  };
  const target = (globalThis.console && typeof globalThis.console === 'object')
    ? globalThis.console
    : {};
  for (const level of ['log', 'warn', 'error']) {
    Object.defineProperty(target, level, {
      value: (...args) => {
        emit(level, args);
        return undefined;
      },
      configurable: true,
      enumerable: true,
      writable: true,
    });
  }
  Object.defineProperty(globalThis, 'console', {
    value: target,
    configurable: true,
    enumerable: true,
    writable: true,
  });
})()
''';
}

String _wrapInstallHostCapabilities(QuickjsHostCapabilities capabilities) {
  final aliases = <String>[
    if (capabilities.browserGlobals.window) 'window',
    if (capabilities.browserGlobals.self) 'self',
  ];
  final encodedAliases = jsonEncode(aliases);
  return '''
(() => {
  const aliases = $encodedAliases;
  for (const name of aliases) {
    Object.defineProperty(globalThis, name, {
      value: globalThis,
      configurable: true,
      enumerable: false,
      writable: true,
    });
  }
})()
''';
}

String _wrapInstallHostProviderRegistry(Map<String, String> providers) {
  final encodedProviders = jsonEncode(providers);
  return '''
(() => {
  const bindings = $encodedProviders;
  const registry = Object.create(null);
  for (const name of Object.keys(bindings)) {
    const callbackName = bindings[name];
    Object.defineProperty(registry, name, {
      value: (...args) => globalThis[callbackName](...args),
      configurable: false,
      enumerable: true,
      writable: false,
    });
  }
  Object.defineProperty(globalThis, '__quickjsHostProviders', {
    value: Object.freeze(registry),
    configurable: true,
    enumerable: false,
    writable: false,
  });
})()
''';
}

String _wrapAsyncFunctionBody(String code) {
  return '''
(async () => {
$code
})()
''';
}

String _wrapBindObjectProxy(
  String name,
  String stateName,
  Map<String, Object> properties,
  List<Map<String, String?>> accessors,
  List<Map<String, String>> methods,
) {
  final encodedName = jsonEncode(name);
  final encodedStateName = jsonEncode(stateName);
  final encodedProperties = jsonEncode(properties);
  final encodedAccessors = jsonEncode(accessors);
  final encodedMethods = jsonEncode(methods);
  return '''
(() => {
const inflate = ${_dartValueInflateFunctionSource()};
const target = Object.create(null);
const state = { disposed: false };
const assertLive = () => {
  if (state.disposed) {
    throw new Error('QuickJS object proxy is disposed');
  }
};
Object.defineProperty(target, $encodedStateName, {
  value: state,
  configurable: false,
  enumerable: false,
  writable: false,
});
const properties = $encodedProperties;
for (const key of Object.keys(properties)) {
  const value = inflate(properties[key]);
  Object.defineProperty(target, key, {
    get: () => {
      assertLive();
      return value;
    },
    configurable: false,
    enumerable: true,
  });
}
const accessors = $encodedAccessors;
for (const accessor of accessors) {
  const descriptor = {
    configurable: false,
    enumerable: true,
  };
  if (accessor.getCallback) {
    descriptor.get = () => {
      assertLive();
      return globalThis[accessor.getCallback]();
    };
  }
  if (accessor.setCallback) {
    descriptor.set = (value) => {
      assertLive();
      globalThis[accessor.setCallback](value);
    };
  }
  Object.defineProperty(target, accessor.name, descriptor);
}
const methods = $encodedMethods;
for (const method of methods) {
  Object.defineProperty(target, method.name, {
    value: (...args) => {
      assertLive();
      return globalThis[method.callback](...args);
    },
    configurable: false,
    enumerable: true,
    writable: false,
  });
}
Object.defineProperty(globalThis, $encodedName, {
  value: target,
  configurable: true,
  enumerable: true,
  writable: true,
});
})()
''';
}

String _wrapEvaluateFunctionHandle(String code, {required String name}) {
  final encodedSource = jsonEncode(_appendSourceUrl(code, name));
  return '''
(() => {
  const value = (0, eval)($encodedSource);
  if (typeof value !== 'function') {
    return JSON.stringify({
      ok: false,
      message: 'QuickJS handle expression must evaluate to a function',
    });
  }
  const registryKey = '__quickjsFunctionHandles';
  const nextIdKey = '__quickjsNextFunctionHandleId';
  if (!Object.prototype.hasOwnProperty.call(globalThis, registryKey)) {
    Object.defineProperty(globalThis, registryKey, {
      value: Object.create(null),
      configurable: false,
      enumerable: false,
      writable: false,
    });
  }
  if (!Object.prototype.hasOwnProperty.call(globalThis, nextIdKey)) {
    Object.defineProperty(globalThis, nextIdKey, {
      value: 1,
      configurable: false,
      enumerable: false,
      writable: true,
    });
  }
  const id = globalThis[nextIdKey]++;
  globalThis[registryKey][id] = value;
  return JSON.stringify({ ok: true, id });
})()
''';
}

String _wrapFunctionHandleCall(int handleId, List<Object?> args) {
  final encodedArgs = jsonEncode([
    for (final arg in args) _encodeDartValue(arg, Set<Object>.identity()),
  ]);
  return '''
(() => {
const inflate = ${_dartValueInflateFunctionSource()};
const registry = globalThis.__quickjsFunctionHandles;
if (!registry || typeof registry[$handleId] !== 'function') {
  throw new Error('QuickJS function handle is not valid');
}
const args = $encodedArgs.map(inflate);
return registry[$handleId](...args);
})()
''';
}

String _wrapFunctionHandleCallAwait(int handleId, List<Object?> args) {
  final encodedArgs = jsonEncode([
    for (final arg in args) _encodeDartValue(arg, Set<Object>.identity()),
  ]);
  return '''
const inflate = ${_dartValueInflateFunctionSource()};
const registry = globalThis.__quickjsFunctionHandles;
if (!registry || typeof registry[$handleId] !== 'function') {
  throw new Error('QuickJS function handle is not valid');
}
const args = $encodedArgs.map(inflate);
return await registry[$handleId](...args);
''';
}

String _wrapReleaseFunctionHandle(int handleId) {
  return '''
(() => {
const registry = globalThis.__quickjsFunctionHandles;
if (registry) {
  delete registry[$handleId];
}
})()
''';
}

String _wrapReleaseObjectProxy(
  String name,
  String stateName,
  List<String> callbackNames,
) {
  final encodedName = jsonEncode(name);
  final encodedStateName = jsonEncode(stateName);
  final encodedCallbackNames = jsonEncode(callbackNames);
  return '''
(() => {
const proxy = globalThis[$encodedName];
if (proxy && proxy[$encodedStateName]) {
  proxy[$encodedStateName].disposed = true;
}
delete globalThis[$encodedName];
for (const callbackName of $encodedCallbackNames) {
  delete globalThis[callbackName];
}
})()
''';
}

String _wrapBindClass(
  String name,
  int classId,
  String constructorCallbackName,
  List<Map<String, String?>> accessors,
  List<Map<String, String>> methods,
) {
  final encodedName = jsonEncode(name);
  final encodedStateName = jsonEncode('__quickjsClass_${classId}_state');
  final encodedConstructorCallbackName = jsonEncode(constructorCallbackName);
  final encodedAccessors = jsonEncode(accessors);
  final encodedMethods = jsonEncode(methods);
  return '''
(() => {
let nextInstanceId = 1;
const assertReceiver = (value) => {
  if (!value || !Object.prototype.hasOwnProperty.call(value, $encodedStateName)) {
    throw new TypeError('QuickJS class method called with invalid receiver');
  }
  return value[$encodedStateName];
};
const waitLive = (value) => {
  const state = assertReceiver(value);
  return state.ready.then(() => state.pending).then(() => {
    if (state.disposed) {
      throw new Error('QuickJS class instance is disposed');
    }
    return state.id;
  });
};
const instanceStates = [];
function QuickjsBoundClass(...args) {
  if (!new.target) {
    throw new TypeError('QuickJS class constructor must be called with new');
  }
  const instanceId = nextInstanceId++;
  const target = Object.create(QuickjsBoundClass.prototype);
  const state = {
    id: instanceId,
    disposed: false,
    ready: null,
    pending: Promise.resolve(),
  };
  state.ready = globalThis[$encodedConstructorCallbackName](instanceId, ...args)
    .catch((error) => {
      state.disposed = true;
      throw error;
    });
  instanceStates.push(state);
  Object.defineProperty(target, $encodedStateName, {
    value: state,
    configurable: false,
    enumerable: false,
    writable: false,
  });
  return target;
}
Object.defineProperty(QuickjsBoundClass, 'name', {
  value: $encodedName,
  configurable: true,
});
Object.defineProperty(QuickjsBoundClass, $encodedStateName, {
  value: instanceStates,
  configurable: false,
  enumerable: false,
  writable: false,
});
const accessors = $encodedAccessors;
for (const accessor of accessors) {
  const descriptor = {
    configurable: false,
    enumerable: true,
  };
  if (accessor.getCallback) {
    descriptor.get = function() {
      return waitLive(this).then((instanceId) =>
        globalThis[accessor.getCallback](instanceId)
      );
    };
  }
  if (accessor.setCallback) {
    descriptor.set = function(value) {
      const state = assertReceiver(this);
      state.pending = state.pending
        .then(() => state.ready)
        .then(() => {
          if (state.disposed) {
            throw new Error('QuickJS class instance is disposed');
          }
          return globalThis[accessor.setCallback](state.id, value);
        });
    };
  }
  Object.defineProperty(QuickjsBoundClass.prototype, accessor.name, descriptor);
}
const methods = $encodedMethods;
for (const method of methods) {
  Object.defineProperty(QuickjsBoundClass.prototype, method.name, {
    value: function(...args) {
      return waitLive(this).then((instanceId) =>
        globalThis[method.callback](instanceId, ...args)
      );
    },
    configurable: false,
    enumerable: true,
    writable: false,
  });
}
Object.defineProperty(globalThis, $encodedName, {
  value: QuickjsBoundClass,
  configurable: true,
  enumerable: true,
  writable: true,
});
})()
''';
}

String _wrapReleaseClassBinding(
  String name,
  int classId,
  List<String> callbackNames,
) {
  final encodedName = jsonEncode(name);
  final encodedStateName = jsonEncode('__quickjsClass_${classId}_state');
  final encodedCallbackNames = jsonEncode(callbackNames);
  return '''
(() => {
const constructor = globalThis[$encodedName];
if (typeof constructor === 'function' && Array.isArray(constructor[$encodedStateName])) {
  for (const state of constructor[$encodedStateName]) {
    state.disposed = true;
  }
}
delete globalThis[$encodedName];
for (const callbackName of $encodedCallbackNames) {
  delete globalThis[callbackName];
}
})()
''';
}

String _dartValueInflateFunctionSource() {
  return '''
(payload) => {
  switch (payload.type) {
    case 'null':
      return null;
    case 'number':
    case 'boolean':
    case 'string':
      return payload.value;
    case 'bytes':
      return new Uint8Array(payload.value);
    case 'array':
      return payload.value.map((item) => inflate(item));
    case 'object': {
      const value = {};
      for (const key of Object.keys(payload.value)) {
        value[key] = inflate(payload.value[key]);
      }
      return value;
    }
    case 'date':
      return new Date(payload.value);
    default:
      throw new TypeError('Unknown Dart value payload: ' + payload.type);
  }
}
''';
}

Map<String, Object?> _encodeGlobals(Map<String, Object?> globals) {
  return {
    for (final entry in globals.entries)
      _validateGlobalName(entry.key): _encodeDartValue(
        entry.value,
        Set<Object>.identity(),
      ),
  };
}

String _validateGlobalName(String name) {
  final isIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);
  if (!isIdentifier) {
    throw JsValueConversionException(
      'QuickJS global name must be a JavaScript identifier: $name',
    );
  }
  return name;
}

String _validateObjectProxyMemberName(String name) {
  final isIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);
  if (!isIdentifier) {
    throw JsValueConversionException(
      'QuickJS object proxy member name must be a JavaScript identifier: $name',
    );
  }
  return name;
}

String _validateModuleName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException('QuickJS module name must not be empty');
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS module name must not contain NUL',
    );
  }
  return name;
}

String _validateHostProviderName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host provider name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host provider name must not contain NUL',
    );
  }
  return name;
}

String _validateHostMountName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host mount name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host mount name must not contain NUL',
    );
  }
  return name;
}

String _validateSourceName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException('QuickJS source name must not be empty');
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS source name must not contain NUL',
    );
  }
  if (name.contains('\n') || name.contains('\r')) {
    throw JsValueConversionException(
      'QuickJS source name must not contain line breaks',
    );
  }
  return name;
}

String _appendSourceUrl(String source, String name) {
  if (source.contains(RegExp(r'^\s*//# sourceURL=', multiLine: true))) {
    return source;
  }
  return '$source\n//# sourceURL=$name';
}

int _stackColumnToSourceMapColumn(int column) {
  return column <= 0 ? 0 : column - 1;
}

final class _StackRemapResult {
  const _StackRemapResult({required this.stack, this.location});

  final String? stack;
  final QuickjsSourceMapLocation? location;
}

String _wrapCommonJsModule(
  String rootSource,
  String rootName,
  Map<String, String> modules,
) {
  final allModules = <String, String>{...modules, rootName: rootSource};
  final encodedRoot = jsonEncode(rootName);
  final encodedModules = jsonEncode(allModules);
  return '''
(() => {
  const sources = $encodedModules;
  const cacheKey = '__quickjsCommonJsCache';
  const cache = globalThis[cacheKey] || Object.defineProperty(
    globalThis,
    cacheKey,
    {
      value: Object.create(null),
      configurable: false,
      enumerable: false,
      writable: false,
    }
  )[cacheKey];
  const resolve = (referrer, specifier) => {
    if (!specifier.startsWith('./') && !specifier.startsWith('../')) {
      return specifier.startsWith('node:') ? specifier.slice(5) : specifier;
    }
    const slash = referrer.lastIndexOf('/');
    const base = slash < 0 ? '' : referrer.slice(0, slash + 1);
    const parts = [];
    for (const part of (base + specifier).split('/')) {
      if (!part || part === '.') {
        continue;
      }
      if (part === '..') {
        parts.pop();
        continue;
      }
      parts.push(part);
    }
    return parts.join('/');
  };
  const load = (name) => {
    if (Object.prototype.hasOwnProperty.call(cache, name)) {
      return cache[name].exports;
    }
    if (!Object.prototype.hasOwnProperty.call(sources, name)) {
      throw new Error('Cannot find CommonJS module "' + name + '"');
    }
    const module = { id: name, filename: name, loaded: false, exports: {} };
    cache[name] = module;
    const localRequire = (specifier) => load(resolve(name, String(specifier)));
    localRequire.resolve = (specifier) => resolve(name, String(specifier));
    const body = sources[name] + '\\n//# sourceURL=' + name;
    try {
      Function('require', 'module', 'exports', body)(
        localRequire,
        module,
        module.exports
      );
      module.loaded = true;
      return module.exports;
    } catch (error) {
      delete cache[name];
      throw error;
    }
  };
  return load($encodedRoot);
})()
''';
}

Iterable<String> _esModuleSpecifiers(String source) sync* {
  final pattern = RegExp(
    r'''(?:import|export)\s+(?:[^'"]*?\s+from\s+)?['"]([^'"]+)['"]|import\s*\(\s*['"]([^'"]+)['"]\s*\)''',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    yield match.group(1) ?? match.group(2)!;
  }
}

Iterable<String> _commonJsSpecifiers(String source) sync* {
  final pattern = RegExp(
    r'''(?:^|[^\w$])require\s*\(\s*['"]([^'"]+)['"]\s*\)''',
    multiLine: true,
  );
  for (final match in pattern.allMatches(source)) {
    yield match.group(1)!;
  }
}

String _resolveModuleName(String referrer, String specifier) {
  if (!specifier.startsWith('./') && !specifier.startsWith('../')) {
    return _canonicalModuleName(specifier);
  }
  final slash = referrer.lastIndexOf('/');
  final base = slash < 0 ? '' : referrer.substring(0, slash + 1);
  return Uri.parse(base).resolve(specifier).path;
}

String _canonicalModuleName(String name) {
  return name.startsWith('node:') ? name.substring(5) : name;
}

Object _encodeDartValue(Object? value, Set<Object> seen) {
  if (value == null) {
    return {'type': 'null'};
  }
  if (value is bool) {
    return {'type': 'boolean', 'value': value};
  }
  if (value is int) {
    return {'type': 'number', 'value': value};
  }
  if (value is double) {
    if (!value.isFinite) {
      throw JsValueConversionException(
        'QuickJS global double value must be finite',
      );
    }
    return {'type': 'number', 'value': value};
  }
  if (value is String) {
    return {'type': 'string', 'value': value};
  }
  if (value is Uint8List) {
    return {'type': 'bytes', 'value': value.toList()};
  }
  if (value is DateTime) {
    return {'type': 'date', 'value': value.toUtc().toIso8601String()};
  }
  if (value is List) {
    return _encodeWithCycleCheck(value, seen, () {
      return {
        'type': 'array',
        'value': [for (final item in value) _encodeDartValue(item, seen)],
      };
    });
  }
  if (value is Map) {
    return _encodeWithCycleCheck(value, seen, () {
      return {'type': 'object', 'value': _encodeDartMap(value, seen)};
    });
  }
  throw JsValueConversionException(
    'QuickJS global value cannot be converted to JavaScript: ${value.runtimeType}',
  );
}

Map<String, Object> _encodeDartMap(Map value, Set<Object> seen) {
  final result = <String, Object>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw JsValueConversionException(
        'QuickJS global map keys must be strings',
      );
    }
    result[key] = _encodeDartValue(entry.value, seen);
  }
  return result;
}

Object _encodeWithCycleCheck(
  Object value,
  Set<Object> seen,
  Object Function() encode,
) {
  if (seen.contains(value)) {
    throw JsValueConversionException(
      'QuickJS global value cannot contain circular references',
    );
  }
  seen.add(value);
  try {
    return encode();
  } finally {
    seen.remove(value);
  }
}

final class _QueuedEval {
  _QueuedEval(this.code, this.timeout, this.name, this.async);

  final String code;
  final Duration? timeout;
  final String name;
  final bool async;
  final Completer<String> _completer = Completer<String>();
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _queueTimer;

  Future<String> get future => _completer.future;

  Duration? get remainingTimeout {
    final currentTimeout = timeout;
    if (currentTimeout == null) {
      return null;
    }
    return currentTimeout - _stopwatch.elapsed;
  }

  void startQueueTimer(void Function() onTimeout) {
    final currentTimeout = timeout;
    if (currentTimeout != null) {
      _queueTimer = Timer(currentTimeout, onTimeout);
    }
  }

  void cancelQueueTimer() {
    _queueTimer?.cancel();
    _queueTimer = null;
  }

  void complete(String value) {
    if (!_completer.isCompleted) {
      _completer.complete(value);
    }
  }

  void completeError(Object error, [StackTrace? stackTrace]) {
    if (_completer.isCompleted) {
      return;
    }
    // 队列任务可能在调用方注册 expectLater 之前被取消；先挂一个 ignore，
    // 避免 Dart 把这类预期内的取消当成未处理错误。
    _completer.future.ignore();
    _completer.completeError(error, stackTrace);
  }
}

final class _QueuedModuleEval extends _QueuedEval {
  _QueuedModuleEval(String code, String name, this.modules, Duration? timeout)
    : super(code, timeout, name, false);

  final Map<String, String> modules;
}
