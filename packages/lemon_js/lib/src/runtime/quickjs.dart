import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import '../backend/quickjs_backend.dart';
import '../backend/quickjs_backend_factory.dart';
import '../diagnostics/quickjs_diag.dart';
import '../diagnostics/quickjs_exception.dart';
import 'quickjs_runtime_base.dart';
import 'quickjs_runtime_options.dart';
import 'quickjs_plugin.dart';
import '../diagnostics/quickjs_source_map.dart';
import 'quickjs_value.dart';

part '../module/quickjs_text_encoding.dart';

const String _moduleCallBreadcrumbName = '__quickjsLastModuleCall';

typedef JsCallback = FutureOr<Object?> Function(List<Object?> args);
typedef JsConsoleSink = FutureOr<void> Function(JsConsoleEvent event);
typedef JsClassConstructor<T extends Object> =
    FutureOr<T> Function(List<Object?> args);
typedef JsGetter<T extends Object> = FutureOr<Object?> Function(T target);
typedef JsSetter<T extends Object> =
    FutureOr<void> Function(T target, Object? value);
typedef JsMemberCallback<T extends Object> =
    FutureOr<Object?> Function(T target, List<Object?> args);

/// JavaScript console method severity.
enum JsConsoleLevel { log, warn, error }

/// A single JavaScript `console.*` event emitted by one [Quickjs] runtime.
final class JsConsoleEvent {
  const JsConsoleEvent({
    required this.level,
    required this.text,
    required this.args,
    required this.timestamp,
  });

  final JsConsoleLevel level;
  final String text;
  final List<Object?> args;
  final DateTime timestamp;
}

/// A fixed Dart value exposed as a readonly JavaScript property.
final class JsValue {
  const JsValue(this.name, this.value);

  final String name;
  final Object? value;
}

/// A dynamic JavaScript property backed by Dart getter/setter callbacks.
final class JsAccessor<T extends Object> {
  const JsAccessor(this.name, {this.get, this.set});

  final String name;

  /// Called when JS reads the property. JS receives a Promise.
  final JsGetter<T>? get;

  /// Called when JS writes the property.
  ///
  /// JavaScript setter syntax cannot return a Promise to the assignment
  /// expression, so async setter errors are not awaitable through `obj.prop = x`.
  final JsSetter<T>? set;
}

/// A Promise-returning JavaScript method backed by a Dart callback.
final class JsMethod<T extends Object> {
  const JsMethod(this.name, this.callback);

  final String name;
  final JsMemberCallback<T> callback;
}

/// Explicit descriptor for a Dart object exposed to JavaScript.
///
/// This first proxy slice intentionally avoids Dart reflection. Properties are
/// exposed as readonly enumerable JS properties, accessors as dynamic JS properties,
/// and methods as JS functions that return Promises through the existing
/// callback bridge.
final class JsMembers<T extends Object> {
  const JsMembers({
    this.values = const <JsValue>[],
    this.accessors = const [],
    this.methods = const [],
  });

  final List<JsValue> values;
  final List<JsAccessor<T>> accessors;
  final List<JsMethod<T>> methods;
}

/// An existing Dart object exposed to JavaScript.
final class JsObject<T extends Object> {
  const JsObject({required this.target, required this.members});

  final T target;
  final JsMembers<T> members;
}

/// Explicit descriptor for a Dart class exposed as a JavaScript constructor.
///
/// The constructor returns a JS instance synchronously, while the Dart instance
/// is created through the Promise callback bridge. Instance getters and methods
/// wait for that constructor Promise before touching the Dart instance.
final class JsClass<T extends Object> {
  const JsClass({required this.create, required this.members});

  final JsClassConstructor<T> create;
  final JsMembers<T> members;
}

final class _ValidatedJsMembers<T extends Object> {
  const _ValidatedJsMembers(this.values, this.accessors, this.methods);

  final Map<String, Object> values;
  final List<(String, JsAccessor<T>)> accessors;
  final List<(String, JsMethod<T>)> methods;
}

_ValidatedJsMembers<T> _validateJsMembers<T extends Object>(
  JsMembers<T> members, {
  required String owner,
}) {
  final names = <String>{};
  String validateName(String name) {
    final validName = _validateObjectProxyMemberName(name);
    if (!names.add(validName)) {
      throw JsValueConversionException(
        'QuickJS $owner member is defined more than once: $validName',
      );
    }
    return validName;
  }

  final values = <String, Object>{};
  for (final value in members.values) {
    values[validateName(value.name)] = _encodeDartValue(
      value.value,
      Set<Object>.identity(),
    );
  }
  final accessors = <(String, JsAccessor<T>)>[];
  for (final accessor in members.accessors) {
    final name = validateName(accessor.name);
    if (accessor.get == null && accessor.set == null) {
      throw JsValueConversionException(
        'QuickJS $owner accessor must define get or set: $name',
      );
    }
    accessors.add((name, accessor));
  }
  final methods = <(String, JsMethod<T>)>[
    for (final method in members.methods) (validateName(method.name), method),
  ];
  return _ValidatedJsMembers(values, accessors, methods);
}

/// Runtime-owned handle to a JavaScript constructor binding.
final class JsClassHandle {
  JsClassHandle._(
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
final class JsObjectHandle {
  JsObjectHandle._(
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
final class JsFunctionHandle {
  JsFunctionHandle._(this._owner, this.id);

  final Quickjs _owner;
  bool _disposed = false;
  Future<void>? _disposeFuture;

  /// Opaque handle id, unique within the owning runtime.
  final int id;

  /// Calls the referenced JavaScript function with [args].
  ///
  /// This path preserves synchronous interrupt semantics for long-running
  /// JavaScript. Use [run] when the function returns a Promise.
  Future<Object?> call(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<Object?>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._callFunctionHandle(id, args, timeout: timeout);
  }

  /// Calls the function synchronously and returns the raw bridge string.
  Future<String> callRaw(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<String>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._callFunctionHandleRaw(id, args, timeout: timeout);
  }

  /// Calls the referenced JavaScript function and awaits its result.
  ///
  /// This accepts both synchronous and Promise-returning JavaScript functions.
  /// The [timeout] covers the awaited Promise lifecycle. If the function may do
  /// long synchronous work before returning a Promise or reaching its first
  /// `await`, prefer [call] so the synchronous interrupt path can stop it.
  Future<Object?> run(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<Object?>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._runFunctionHandle(id, args, timeout: timeout);
  }

  /// Awaits the function result and returns the raw bridge string.
  Future<String> runRaw(List<Object?> args, {Duration? timeout}) {
    if (_disposed) {
      return Future<String>.error(
        JsRuntimeClosedException('QuickJS function handle is disposed'),
      );
    }
    return _owner._runFunctionHandleRaw(id, args, timeout: timeout);
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

  /// Cancels the current runtime operation, matching [Quickjs.restart] semantics.
  Future<void> cancel() {
    return _owner.restart();
  }
}

/// `Quickjs` 实例当前可观察的生命周期状态。
enum JsRuntimeState {
  /// Runtime 正在创建中。
  creating,

  /// Runtime 可接受并执行新的请求。
  ready,

  /// Runtime 正在执行一个 eval 请求。
  running,

  /// Runtime 正在停止当前请求并恢复可用状态。
  restarting,

  /// Runtime 已被 dispose，不能再使用。
  closed,

  /// Runtime worker 已崩溃或进入不可恢复失败状态。
  failed,
}

/// Conflict handling for [Quickjs.loadFeatures].
enum JsFeaturesConflictPolicy {
  /// Reject duplicate features names or capability declarations.
  reject,

  /// Replace an existing runtime-installed features with the same name.
  ///
  /// Features supplied through [JsOptions.features] remain immutable,
  /// and conflicts with other features are still rejected.
  replace,
}

/// Structured host-provider metadata exposed by the inspector prototype.
final class JsProviderDebugInfo {
  const JsProviderDebugInfo({
    required this.name,
    required this.debugName,
    required this.implementation,
  });

  final String name;
  final String debugName;
  final JsProviderImplementation implementation;
}

/// Structured mounted-plugin metadata exposed by the inspector prototype.
final class JsPluginDebugInfo {
  const JsPluginDebugInfo({
    required this.id,
    required this.version,
    required this.entry,
    required this.exports,
    required this.featuresName,
    required this.moduleNames,
    this.init,
    this.dispose,
  });

  final String id;
  final String version;
  final String entry;
  final List<String> exports;
  final String featuresName;
  final List<String> moduleNames;
  final String? init;
  final String? dispose;
}

/// Runtime debug snapshot exposed by the inspector prototype.
final class JsInspectorSnapshot {
  const JsInspectorSnapshot({
    required this.state,
    required this.quickjsVersion,
    required this.running,
    required this.pendingEvaluations,
    required this.registeredCallbacks,
    required this.registeredProviders,
    this.providerDetails = const <JsProviderDebugInfo>[],
    this.pluginDetails = const <JsPluginDebugInfo>[],
    required this.registeredFeatures,
    required this.moduleNames,
    required this.sourceMapNames,
    required this.memoryLimitBytes,
    required this.stackLimitBytes,
    this.globals,
  });

  final JsRuntimeState state;
  final String quickjsVersion;
  final bool running;
  final int pendingEvaluations;
  final List<String> registeredCallbacks;
  final List<String> registeredProviders;
  final List<JsProviderDebugInfo> providerDetails;
  final List<JsPluginDebugInfo> pluginDetails;
  final List<String> registeredFeatures;
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
class Quickjs implements JsPluginHost {
  Quickjs._(
    this._backend,
    this._runtime,
    this._options,
    this._onConsole, {
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsProvider> providers = const <JsProvider>[],
    List<JsFeatures> features = const <JsFeatures>[],
  }) : _moduleLoader = moduleLoader,
       _scripts = List<JsScript>.unmodifiable(scripts),
       _modules = List<JsModule>.unmodifiable(modules),
       _providers = List<JsProvider>.unmodifiable(providers),
       _initialFeatures = List<JsFeatures>.unmodifiable(features);

  /// Creates a [Quickjs] wrapper around a supplied backend/runtime pair.
  ///
  /// This is intended for package tests that need deterministic control over
  /// runtime lifecycle transitions without depending on a real QuickJS worker.
  Quickjs.test(
    QuickjsBackend backend,
    QuickjsJsRuntimeBase runtime, {
    JsOptions options = const JsOptions(),
    JsConsoleSink? onConsole,
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsProvider> providers = const <JsProvider>[],
    List<JsFeatures> features = const <JsFeatures>[],
  }) : this._(
         backend,
         runtime,
         options,
         onConsole,
         moduleLoader: moduleLoader,
         scripts: scripts,
         modules: modules,
         providers: providers,
         features: features,
       );

  final QuickjsBackend _backend;
  QuickjsJsRuntimeBase _runtime;
  final JsOptions _options;
  final JsConsoleSink? _onConsole;
  final JsModuleLoader? _moduleLoader;
  final List<JsScript> _scripts;
  final List<JsModule> _modules;
  final List<JsProvider> _providers;
  final List<JsFeatures> _initialFeatures;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  JsRuntimeState _state = JsRuntimeState.ready;
  Object? _failure;
  Future<void>? _running;
  _QueuedEval? _runningRequest;
  Future<void>? _disposeFuture;
  Future<void>? _restartFuture;
  int _nextCallbackId = 1;
  int _nextObjectProxyId = 1;
  int _nextClassBindingId = 1;
  int _nextPluginCallId = 1;
  int _nextEvalRequestId = 0;
  DateTime? _lastEvalEndedAt;
  final Map<String, JsSourceMap> _sourceMaps = <String, JsSourceMap>{};
  final Map<int, String> _callbackDebugNames = <int, String>{};
  final Set<String> _moduleDebugNames = <String>{};
  final Map<String, String> _moduleNamespaceGlobalNames = <String, String>{};
  final List<JsFeatures> _runtimeFeatures = <JsFeatures>[];
  final Map<int, Map<int, Object>> _classInstances = <int, Map<int, Object>>{};
  final Set<JsProviderContext> _pendingHostProviderCalls =
      <JsProviderContext>{};

  /// 为当前平台创建一个独立的 QuickJS runtime。
  static Future<Quickjs> create({
    JsOptions options = const JsOptions(),
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsProvider> providers = const <JsProvider>[],
    List<JsFeatures> features = const <JsFeatures>[],
    List<JsPlugin> plugins = const <JsPlugin>[],
    JsConsoleSink? onConsole,
  }) async {
    if (options.maxPendingTasks < 1) {
      throw ArgumentError.value(
        options.maxPendingTasks,
        'options.maxPendingTasks',
        'must be positive',
      );
    }
    final backend = await createQuickjsBackend();
    final runtime = await backend.createRuntime(options);
    final engine = Quickjs._(
      backend,
      runtime,
      options,
      onConsole,
      moduleLoader: moduleLoader,
      scripts: scripts,
      modules: modules,
      providers: providers,
      features: <JsFeatures>[
        ...features,
        for (final plugin in plugins) plugin.asFeatures(),
      ],
    );
    try {
      await engine._installInitialEnvironmentOnCurrentRuntime();
    } catch (_) {
      await runtime.dispose();
      rethrow;
    }
    return engine;
  }

  /// Builds the high-level QuickJS API on an already-created backend context.
  ///
  /// Context runtimes use this path so features and plugins reuse the canonical
  /// installer without creating or rebuilding another native `JSRuntime`.
  static Future<Quickjs> attachContext(
    QuickjsBackend backend,
    QuickjsJsRuntimeBase runtime, {
    JsOptions options = const JsOptions(),
    JsModuleLoader? moduleLoader,
    List<JsScript> scripts = const <JsScript>[],
    List<JsModule> modules = const <JsModule>[],
    List<JsProvider> providers = const <JsProvider>[],
    List<JsFeatures> features = const <JsFeatures>[],
    List<JsPlugin> plugins = const <JsPlugin>[],
    JsConsoleSink? onConsole,
  }) async {
    final engine = Quickjs._(
      backend,
      runtime,
      options,
      onConsole,
      moduleLoader: moduleLoader,
      scripts: scripts,
      modules: modules,
      providers: providers,
      features: <JsFeatures>[
        ...features,
        for (final plugin in plugins) plugin.asFeatures(),
      ],
    );
    try {
      await engine._installInitialEnvironmentOnCurrentRuntime();
    } catch (_) {
      await runtime.dispose();
      rethrow;
    }
    return engine;
  }

  /// 当前打包进插件的 QuickJS 版本号。
  String get quickjsVersion => _backend.quickjsVersion;

  /// 当前 runtime 生命周期状态。
  JsRuntimeState get state => _state;

  /// Features a capability bundle and rebuilds the current runtime.
  ///
  /// The first runtime-mounting implementation is intentionally atomic: the
  /// runtime must be idle, the features is validated against all existing static
  /// and runtime features, then the runtime is rebuilt. Existing JavaScript
  /// globals, module cache, bound callbacks, and handles are not preserved.
  /// Successfully loaded bundles are reinstalled by later [restart] rebuilds.
  /// [JsFeaturesConflictPolicy.replace] replaces only a same-name features
  /// previously installed through this method; initialization features remain
  /// immutable and unrelated capability conflicts are still rejected.
  Future<void> loadFeatures(
    JsFeatures features, {
    JsFeaturesConflictPolicy conflictPolicy = JsFeaturesConflictPolicy.reject,
  }) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      throw terminalError;
    }
    if (_state != JsRuntimeState.ready ||
        _running != null ||
        _queue.isNotEmpty ||
        _restartFuture != null) {
      throw StateError(
        'QuickJS host features can only be installed while idle',
      );
    }

    final featuresName = _validateFeaturesName(features.name);
    final previousFeatures = List<JsFeatures>.of(_runtimeFeatures);
    final staticFeaturesExist = _initialFeatures.any(
      (candidate) => _validateFeaturesName(candidate.name) == featuresName,
    );
    final runtimeFeaturesIndex = _runtimeFeatures.indexWhere(
      (candidate) => _validateFeaturesName(candidate.name) == featuresName,
    );
    if (conflictPolicy == JsFeaturesConflictPolicy.replace &&
        staticFeaturesExist) {
      throw JsValueConversionException(
        'QuickJS initialization features cannot be replaced at runtime: $featuresName',
      );
    }
    final replacedFeatures =
        conflictPolicy == JsFeaturesConflictPolicy.replace &&
            runtimeFeaturesIndex >= 0
        ? _runtimeFeatures[runtimeFeaturesIndex]
        : null;
    _validateFeaturesAgainstLoadedModules(
      features,
      replacedFeatures: replacedFeatures,
    );
    if (conflictPolicy == JsFeaturesConflictPolicy.replace &&
        runtimeFeaturesIndex >= 0) {
      _runtimeFeatures[runtimeFeaturesIndex] = features;
    } else {
      _runtimeFeatures.add(features);
    }
    try {
      _validateStaticHostConfiguration();
    } catch (_) {
      _runtimeFeatures
        ..clear()
        ..addAll(previousFeatures);
      rethrow;
    }

    if (_runtime is QuickjsInPlaceMountRuntime) {
      try {
        await _installFeaturesOnCurrentContext(features);
      } catch (_) {
        _runtimeFeatures
          ..clear()
          ..addAll(previousFeatures);
        rethrow;
      }
      return;
    }

    _state = JsRuntimeState.restarting;
    final previousRuntime = _runtime;
    try {
      await previousRuntime.dispose();
      await _replaceCurrentRuntime();
      _state = JsRuntimeState.ready;
    } catch (error, stackTrace) {
      try {
        await _runtime.dispose();
      } catch (_) {}
      _runtimeFeatures
        ..clear()
        ..addAll(previousFeatures);
      try {
        await _replaceCurrentRuntime();
        _state = JsRuntimeState.ready;
      } catch (recoveryError) {
        try {
          await _runtime.dispose();
        } catch (_) {}
        _failure = recoveryError;
        _state = JsRuntimeState.failed;
      }
      Error.throwWithStackTrace(error, stackTrace);
    }
  }

  /// Registers a source map for generated JavaScript [sourceName].
  ///
  /// The [sourceName] should match the `name:` passed to eval/evaluate APIs or
  /// the module name used for module evaluation. The current registry phase
  /// attaches matching source maps to [JsThrownException.sourceMap]; actual stack
  /// rewriting is handled by the later stack remap phase.
  void registerSourceMap(String sourceName, JsSourceMap sourceMap) {
    _sourceMaps[_validateSourceName(sourceName)] = sourceMap;
  }

  /// Removes the source map registered for [sourceName].
  void unregisterSourceMap(String sourceName) {
    _sourceMaps.remove(_validateSourceName(sourceName));
  }

  /// Returns the source map registered for [sourceName], if any.
  JsSourceMap? sourceMapFor(String sourceName) {
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
  Future<JsInspectorSnapshot> debugInspect({
    bool includeGlobals = false,
  }) async {
    final globals = includeGlobals
        ? await debugEvaluateValue(
            'Object.getOwnPropertyNames(globalThis).sort()',
            name: '<inspector:globals>',
          )
        : null;
    return JsInspectorSnapshot(
      state: state,
      quickjsVersion: quickjsVersion,
      running: _running != null,
      pendingEvaluations: _queue.length,
      registeredCallbacks: List<String>.unmodifiable(
        _callbackDebugNames.values.toList()..sort(),
      ),
      registeredProviders: List<String>.unmodifiable(_debugProviderNames()),
      providerDetails: List<JsProviderDebugInfo>.unmodifiable(
        _debugProviderDetails(),
      ),
      pluginDetails: List<JsPluginDebugInfo>.unmodifiable(
        _debugPluginDetails(),
      ),
      registeredFeatures: List<String>.unmodifiable(_debugMountNames()),
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
  /// queue, timeout, and conversion semantics as [eval].
  Future<Object?> debugEvaluateValue(
    String expression, {
    Duration? timeout,
    String name = '<inspector>',
  }) {
    return eval(expression, timeout: timeout, name: name);
  }

  /// 在当前 runtime 中执行 [code]。
  ///
  /// 调用只会入队，不会在 Flutter UI isolate 中同步执行 JS。
  /// [globals] 会在本次执行期间临时注入到 JS `globalThis`，执行结束后恢复。
  /// Returns QuickJS's raw bridge string without Dart value conversion.
  /// Prefer [eval] unless the exact textual representation is required.
  Future<String> evalRaw(
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

  /// 在当前 runtime 中执行异步 JavaScript 函数体，并等待返回的 Promise。
  ///
  /// [code] 会包裹在 `async () => { ... }` 中执行；需要返回值时使用 `return`。
  /// Waits for the async body and returns QuickJS's raw bridge string.
  /// Prefer [run] unless the exact textual representation is required.
  Future<String> runRaw(
    String code, {
    Duration? timeout,
    String name = '<run>',
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
      JsModuleFormat.esModule,
    );
    _moduleDebugNames.addAll(modules.keys);
    return _enqueueModule(
      source,
      name: validName,
      modules: modules,
      timeout: timeout,
    );
  }

  /// Runs due timers/jobs and returns the delay until the next native timer.
  /// Null means no timer is scheduled. Non-native backends retain a bounded
  /// compatibility poll because they cannot inspect the native timer queue.
  Future<Duration?> pumpTimers() async {
    final runtime = _runtime;
    if (runtime is QuickjsTimerRuntimeBase) {
      final milliseconds = await (runtime as QuickjsTimerRuntimeBase)
          .pumpTimers();
      return milliseconds == null ? null : Duration(milliseconds: milliseconds);
    }
    await runRaw(
      'await new Promise((resolve) => setTimeout(resolve, 0)); return null;',
      name: '<quickjs:timer-pump>',
    );
    return const Duration(milliseconds: 500);
  }

  /// Validates that a plugin entry module exposes every declared function.
  @override
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout}) async {
    final entry = plugin.manifest.entry;
    final lifecycleExports = <String>[
      if (plugin.manifest.init != null) plugin.manifest.init!,
      if (plugin.manifest.dispose != null) plugin.manifest.dispose!,
    ];
    await _evaluateModuleNamespaceValue(
      entry,
      '''
for (const name of ${jsonEncode(plugin.manifest.exports)}) {
  if (typeof __quickjsModuleNamespace[name] !== 'function') {
    throw new TypeError(
      'QuickJS plugin export is not a function: ' +
      ${jsonEncode(entry)} + '#' + name
    );
  }
}
for (const name of ${jsonEncode(lifecycleExports)}) {
  if (typeof __quickjsModuleNamespace[name] !== 'function') {
    throw new TypeError(
      'QuickJS plugin lifecycle export is not a function: ' +
      ${jsonEncode(entry)} + '#' + name
    );
  }
}
return JSON.stringify({ type: 'null' });
''',
      timeout: timeout,
      name: 'plugin:${plugin.manifest.id}:validate',
    );
  }

  /// Calls the plugin's optional init lifecycle export.
  ///
  /// If the manifest does not declare an init export, this is a no-op.
  @override
  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) {
    final init = plugin.manifest.init;
    if (init == null) {
      return Future<Object?>.value(null);
    }
    return callModule(
      plugin.manifest.entry,
      init,
      <Object?>[context],
      timeout: timeout,
      name: 'plugin:${plugin.manifest.id}:init',
    );
  }

  /// Calls the plugin's optional dispose lifecycle export.
  ///
  /// If the manifest does not declare a dispose export, this is a no-op.
  @override
  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout}) {
    final dispose = plugin.manifest.dispose;
    if (dispose == null) {
      return Future<Object?>.value(null);
    }
    return callModule(
      plugin.manifest.entry,
      dispose,
      const <Object?>[],
      timeout: timeout,
      name: 'plugin:${plugin.manifest.id}:dispose',
    );
  }

  /// Calls a declared function from a plugin entry module.
  @override
  Future<Object?> callPlugin(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    if (!plugin.manifest.exports.contains(method)) {
      throw JsValueConversionException(
        'QuickJS plugin export is not declared: ${plugin.manifest.id}#$method',
      );
    }
    return callModule(
      plugin.manifest.entry,
      method,
      args,
      timeout: timeout,
      name: 'plugin:${plugin.manifest.id}:$method',
    );
  }

  /// Calls a plugin export by method name from the plugins mounted in this runtime.
  ///
  /// If [pluginId] is omitted, exactly one mounted plugin must declare [method].
  /// When multiple plugins export the same method, pass [pluginId] to choose one.
  Future<Object?> invokePlugin(
    String method,
    List<Object?> args, {
    String? pluginId,
    Duration? timeout,
  }) async {
    final plugin = _resolveMountedPlugin(method, pluginId: pluginId);
    return callPlugin(plugin, method, args, timeout: timeout);
  }

  /// Calls a function export from an ES module and converts its awaited result.
  Future<Object?> callModule(
    String module,
    String method,
    List<Object?> args, {
    Duration? timeout,
    String? name,
  }) async {
    final moduleName = _canonicalModuleName(_validateModuleName(module));
    final encodedModule = jsonEncode(moduleName);
    final encodedMethod = jsonEncode(method);
    final encodedBreadcrumbName = jsonEncode(_moduleCallBreadcrumbName);
    final encodedArgs = jsonEncode(<Object>[
      for (final arg in args) _encodeDartValue(arg, Set<Object>.identity()),
    ]);
    return await _evaluateModuleNamespaceValue(
      moduleName,
      '''
const method = $encodedMethod;
function breadcrumb(phase) {
  globalThis[$encodedBreadcrumbName] = {
    module: $encodedModule,
    method,
    phase,
    timestamp: Date.now()
  };
}
breadcrumb('resolve export ' + $encodedModule + '#' + method);
const fn = __quickjsModuleNamespace[method];
if (typeof fn !== 'function') {
  throw new TypeError(
    'QuickJS module export is not a function: ' + $encodedModule + '#' + method
  );
}
let phase = 'inflate arguments';
try {
  breadcrumb(phase);
  const args = $encodedArgs.map((arg) => inflate(arg));
  phase = 'call ' + $encodedModule + '#' + method;
  breadcrumb(phase);
  const value = await fn(...args);
  phase = 'convert result from ' + $encodedModule + '#' + method;
  breadcrumb(phase);
  const converted = convert(value, new WeakSet());
  phase = 'stringify result from ' + $encodedModule + '#' + method;
  breadcrumb(phase);
  return JSON.stringify(converted);
} catch (error) {
  breadcrumb('failed during ' + phase);
  if (error && error.message === 'Maximum call stack size exceeded') {
    try {
      error.message = 'QuickJS module call stack overflow during ' + phase;
    } catch (_) {}
  }
  throw error;
}
''',
      timeout: timeout,
      name: name ?? 'module:$moduleName:$method',
    );
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
      JsModuleFormat.commonJs,
    );
    _moduleDebugNames.addAll(modules.keys);
    return _enqueue(
      _wrapCommonJsModule(source, validName, modules),
      timeout: timeout,
      name: validName,
    );
  }

  /// Evaluates [code] and stores the resulting JavaScript function as a handle.
  Future<JsFunctionHandle> bindFunction(
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
    return JsFunctionHandle._(this, payload['id']! as int);
  }

  /// 在 JS `globalThis` 上绑定一个 Promise-based Dart callback。
  ///
  /// JS 侧调用绑定函数时会得到 Promise；Dart callback 的返回值会 resolve 该 Promise，
  /// Dart callback 抛错会 reject 该 Promise。
  Future<void> injectFunction(String name, JsCallback callback) {
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

  /// Injects [stream] on JS `globalThis` as an async iterable.
  ///
  /// JavaScript consumes the values with `for await (const value of name)`.
  /// Each pull requests the next Dart event, preserving backpressure. Stream
  /// errors reject the pending JS iteration and completion ends the iterator.
  Future<void> injectStream<T>(String name, Stream<T> stream) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<void>.error(terminalError);
    }
    final validName = _validateGlobalName(name);
    final callbackId = _nextCallbackId++;
    final callbackName = '__quickjsInjectedStream_$callbackId';
    await _bindRuntimeCallback(callbackId, callbackName, (_) async => stream);
    try {
      await evalRaw('''
(async () => {
  globalThis[${jsonEncode(validName)}] = await globalThis[${jsonEncode(callbackName)}]();
})()
''', name: '<injectStream:$validName>');
    } finally {
      await _unbindRuntimeCallback(callbackId);
    }
  }

  /// 在 JS `globalThis` 上绑定 `{ emit, close, error }`，并返回 Dart [Stream]。
  ///
  /// JS 侧每次 `await sink.emit(value)` 会等待 Dart 侧确认，用于串行 backpressure。
  /// Binds an explicit Dart object proxy on JS `globalThis`.
  ///
  /// [object.values] become readonly enumerable properties.
  /// [object.accessors] become dynamic getter / setter descriptors.
  /// [object.methods] become JS functions that return Promises and route calls
  /// through the same callback bridge used by [bind].
  Future<JsObjectHandle> injectObject<T extends Object>(
    String name,
    JsObject<T> object,
  ) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<JsObjectHandle>.error(terminalError);
    }
    final validName = _validateGlobalName(name);
    final validated = _validateJsMembers(object.members, owner: 'object proxy');

    final proxyId = _nextObjectProxyId++;
    final stateName = '__quickjsObjectProxy_${proxyId}_state';
    final accessors = <Map<String, String?>>[];
    final methods = <Map<String, String>>[];
    final callbackNames = <String>[];
    final callbackIds = <int>[];
    var methodIndex = 1;
    try {
      for (final (accessorName, descriptor) in validated.accessors) {
        String? getCallbackName;
        final getter = descriptor.get;
        if (getter != null) {
          final callbackId = _nextCallbackId++;
          getCallbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
          callbackIds.add(callbackId);
          await _bindRuntimeCallback(callbackId, getCallbackName, (_) async {
            return getter(object.target);
          });
          callbackNames.add(getCallbackName);
        }
        String? setCallbackName;
        final setter = descriptor.set;
        if (setter != null) {
          final callbackId = _nextCallbackId++;
          setCallbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
          callbackIds.add(callbackId);
          await _bindRuntimeCallback(callbackId, setCallbackName, (args) async {
            await setter(object.target, args.isEmpty ? null : args.first);
            return null;
          });
          callbackNames.add(setCallbackName);
        }
        accessors.add({
          'name': accessorName,
          'getCallback': getCallbackName,
          'setCallback': setCallbackName,
        });
      }
      for (final (methodName, method) in validated.methods) {
        final callbackId = _nextCallbackId++;
        final callbackName = '__quickjsObjectProxy_${proxyId}_${methodIndex++}';
        callbackIds.add(callbackId);
        await _bindRuntimeCallback(callbackId, callbackName, (args) async {
          return method.callback(object.target, args);
        });
        callbackNames.add(callbackName);
        methods.add({'name': methodName, 'callback': callbackName});
      }

      await _enqueue(
        _wrapBindObjectProxy(
          validName,
          stateName,
          validated.values,
          accessors,
          methods,
        ),
      );
      return JsObjectHandle._(
        this,
        validName,
        stateName,
        callbackNames,
        callbackIds,
      );
    } catch (_) {
      for (final callbackId in callbackIds.reversed) {
        try {
          await _unbindRuntimeCallback(callbackId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Binds an explicit Dart class as a JavaScript constructor.
  ///
  /// `new $name(...)` returns a JavaScript instance immediately. The Dart
  /// constructor runs through the Promise callback bridge, so instance getters
  /// and methods wait for construction before accessing the Dart instance.
  Future<JsClassHandle> injectClass<T extends Object>(
    String name,
    JsClass<T> definition,
  ) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<JsClassHandle>.error(terminalError);
    }
    final validName = _validateGlobalName(name);
    final validated = _validateJsMembers(definition.members, owner: 'class');
    final classId = _nextClassBindingId++;
    final instances = <int, Object>{};
    _classInstances[classId] = instances;

    final callbackNames = <String>[];
    final callbackIds = <int>[];
    final constructorCallbackName = '__quickjsClass_${classId}_constructor';
    final constructorCallbackId = _nextCallbackId++;
    callbackNames.add(constructorCallbackName);
    callbackIds.add(constructorCallbackId);
    try {
      await _bindRuntimeCallback(
        constructorCallbackId,
        constructorCallbackName,
        (args) async {
          if (args.isEmpty || args.first is! num) {
            throw StateError('QuickJS class constructor missing instance id');
          }
          final instanceId = (args.first! as num).toInt();
          final instance = await definition.create(args.skip(1).toList());
          instances[instanceId] = instance;
          return null;
        },
      );

      final accessors = <Map<String, String?>>[];
      final methods = <Map<String, String>>[];
      var callbackIndex = 1;
      for (final (accessorName, descriptor) in validated.accessors) {
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
      for (final (methodName, method) in validated.methods) {
        final callbackId = _nextCallbackId++;
        callbackIds.add(callbackId);
        final callbackName = '__quickjsClass_${classId}_${callbackIndex++}';
        callbackNames.add(callbackName);
        await _bindRuntimeCallback(callbackId, callbackName, (args) async {
          final instance = _requireClassInstance<T>(classId, args);
          return method.callback(instance, args.skip(1).toList());
        });
        methods.add({'name': methodName, 'callback': callbackName});
      }

      await _enqueue(
        _wrapBindClass(
          validName,
          classId,
          constructorCallbackName,
          validated.values,
          accessors,
          methods,
        ),
      );
      return JsClassHandle._(
        this,
        validName,
        classId,
        callbackNames,
        callbackIds,
      );
    } catch (_) {
      _classInstances.remove(classId);
      for (final callbackId in callbackIds.reversed) {
        try {
          await _unbindRuntimeCallback(callbackId);
        } catch (_) {}
      }
      rethrow;
    }
  }

  /// Binds a JS `{ emit, close, error }` sink and returns its Dart stream.
  ///
  /// `await name.emit(value)` waits until Dart accepts the event, providing
  /// backpressure. `name.close()` completes the stream and `name.error(value)`
  /// reports a stream error.
  Future<Stream<Object?>> bindStream(String name) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<Stream<Object?>>.error(terminalError);
    }
    return _runtime.bindJsSink(_validateGlobalName(name));
  }

  Future<String> _prepareConsoleInstall() async {
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
        final event = JsConsoleEvent(
          level: _consoleLevelFromName('$levelName'),
          text: '$text',
          args: rawArgs,
          timestamp: DateTime.now(),
        );
        await onConsole(event);
        return null;
      });
    }
    return _wrapInstallConsole(onConsole == null ? null : callbackName);
  }

  /// Installs the complete initial global environment through one worker eval.
  ///
  /// Provider callbacks must be bound first because the generated registry
  /// references their global names. Each source is then executed through an
  /// independent indirect eval inside the batch, preserving the global-scope
  /// behavior of the former multi-request installer while removing its fixed
  /// isolate/worker round trips.
  Future<void> _installInitialEnvironmentOnCurrentRuntime() async {
    _validateStaticHostConfiguration();
    final sources = <({String name, String source})>[
      (name: '<quickjs:console>', source: await _prepareConsoleInstall()),
      (name: '<quickjs:text-encoding>', source: _wrapInstallTextEncoding()),
    ];
    final browserGlobals = _effectiveBrowserGlobals();
    if (!browserGlobals.isEmpty) {
      sources.add((
        name: '<quickjs:browser-globals>',
        source: _wrapInstallBrowserGlobals(browserGlobals),
      ));
    }
    final providerNames = await _installHostProvidersOnCurrentRuntime();
    if (providerNames.isNotEmpty) {
      sources.add((
        name: '<quickjs:host-providers>',
        source: _wrapInstallHostProviderRegistry(providerNames),
      ));
    }
    for (final script in _effectiveHostScripts()) {
      sources.add((
        name: _validateSourceName(script.name),
        source: await script.loadSource(),
      ));
    }
    await _runtime.evaluate(
      _wrapInitialEnvironmentBatch(sources),
      name: '<quickjs:initial-environment>',
    );
  }

  Future<Map<String, String>> _installHostProvidersOnCurrentRuntime([
    Iterable<JsProvider>? selectedProviders,
  ]) async {
    final providers = selectedProviders?.toList() ?? _effectiveHostProviders();
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

  Future<void> _installFeaturesOnCurrentContext(JsFeatures features) async {
    final browserGlobals = _effectiveBrowserGlobals();
    if (!browserGlobals.isEmpty) {
      await _runtime.evaluate(
        _wrapInstallBrowserGlobals(browserGlobals),
        name: '<quickjs:context-features-capabilities:${features.name}>',
      );
    }
    final providerNames = await _installHostProvidersOnCurrentRuntime(
      features.providers,
    );
    if (providerNames.isNotEmpty) {
      await _runtime.evaluate(
        _wrapInstallHostProviderRegistry(providerNames),
        name: '<quickjs:context-features-providers:${features.name}>',
      );
    }
    final globalsScript = _providerGlobalsHostScript(
      features.providers,
      features.name,
    );
    if (globalsScript != null) {
      await _runtime.evaluate(
        await globalsScript.loadSource(),
        name: _validateSourceName(globalsScript.name),
      );
    }
    for (final script in features.scripts) {
      await _runtime.evaluate(
        await script.loadSource(),
        name: _validateSourceName(script.name),
      );
    }
  }

  Future<Object?> _invokeHostProvider(
    JsProvider provider,
    List<Object?> args,
  ) async {
    final context = JsProviderContext();
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
  Future<Object?> eval(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    Map<String, Object?> globals = const {},
  }) async {
    final validName = _validateSourceName(name);
    final encodedSource = jsonEncode(
      _wrapWithGlobals(code, globals, name: validName),
    );
    final encodedValue = await evalRaw(
      '''
(() => {
  const unsupported = (reason) => ({
    type: 'conversionError',
    message: 'QuickJS value cannot be converted to a Dart value: ' + reason,
  });
  const budget = { nodes: 0, maxNodes: 10000, maxDepth: 32 };
  const convert = (value, seen, depth = 0) => {
    if (depth > budget.maxDepth) {
      return unsupported('object graph is too deep');
    }
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
    // The node budget protects recursive containers. Primitive leaves are
    // bounded by their owning arrays/objects and should not make a flat scene
    // description fail merely because its commands have many numeric fields.
    budget.nodes += 1;
    if (budget.nodes > budget.maxNodes) {
      return unsupported('object graph is too large');
    }
    if (seen.has(value)) {
      return unsupported('circular reference');
    }
    seen.add(value);
    try {
      if (Array.isArray(value)) {
        const items = [];
        for (const item of value) {
          const converted = convert(item, seen, depth + 1);
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
          const converted = convert(value[key], seen, depth + 1);
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
    return _decodeStructuredPayload(encodedValue);
  }

  /// Executes an async JavaScript function body and returns a Dart value.
  ///
  /// The source is wrapped in an async function, so it may use `await` and
  /// should use `return` to produce a result. The Dart API is asynchronous
  /// because execution happens in a background isolate or worker; `run`
  /// additionally waits for the JavaScript Promise to settle and pumps jobs
  /// and timers while it is pending.
  Future<Object?> run(
    String code, {
    Duration? timeout,
    String name = '<run>',
    Map<String, Object?> globals = const {},
  }) async {
    final payloadJson = await runRaw(
      '''
const convert = ${_jsValueConvertFunctionSource()};
const value = await (async () => {
$code
})();
return JSON.stringify(convert(value, new WeakSet()));
''',
      timeout: timeout,
      name: name,
      globals: globals,
    );
    return _decodeStructuredPayload(payloadJson);
  }

  /// Calls a function stored on `globalThis` and returns its awaited result as
  /// a structured Dart value.
  ///
  /// [method] is resolved as a property name, and [args] are encoded without
  /// interpolating their values into executable JavaScript source.
  Future<Object?> call(String method, List<Object?> args, {Duration? timeout}) {
    return run(
      _wrapGlobalCall(method, args),
      timeout: timeout,
      name: '<call:$method>',
    );
  }

  /// Calls a function stored on `globalThis` and returns QuickJS's raw bridge
  /// string after awaiting its result.
  Future<String> callRaw(
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) {
    return runRaw(
      _wrapGlobalCall(method, args),
      timeout: timeout,
      name: '<call:$method>',
    );
  }

  String _wrapGlobalCall(String method, List<Object?> args) {
    if (method.isEmpty) {
      throw ArgumentError.value(method, 'method', 'must not be empty');
    }
    final encodedMethod = jsonEncode(method);
    final encodedArgs = jsonEncode(<Object>[
      for (final arg in args) _encodeDartValue(arg, Set<Object>.identity()),
    ]);
    return '''
const method = $encodedMethod;
const fn = globalThis[method];
if (typeof fn !== 'function') {
  throw new TypeError('QuickJS global is not a function: ' + method);
}
const inflate = ${_dartValueInflateFunctionSource()};
const args = $encodedArgs.map((arg) => inflate(arg));
return await Reflect.apply(fn, globalThis, args);
''';
  }

  Object? _decodeStructuredPayload(String payloadJson) {
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
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

  JsPlugin _resolveMountedPlugin(String method, {String? pluginId}) {
    final plugins = _mountedPlugins();
    if (pluginId != null) {
      for (final plugin in plugins) {
        if (plugin.manifest.id == pluginId) {
          if (!plugin.manifest.exports.contains(method)) {
            throw JsValueConversionException(
              'QuickJS plugin export is not declared: $pluginId#$method',
            );
          }
          return plugin;
        }
      }
      throw JsValueConversionException(
        'QuickJS plugin is not mounted: $pluginId',
      );
    }

    final matches = <JsPlugin>[
      for (final plugin in plugins)
        if (plugin.manifest.exports.contains(method)) plugin,
    ];
    if (matches.isEmpty) {
      throw JsValueConversionException(
        'QuickJS plugin export is not declared by any mounted plugin: $method',
      );
    }
    if (matches.length > 1) {
      final ids = matches.map((plugin) => plugin.manifest.id).join(', ');
      throw JsValueConversionException(
        'QuickJS plugin export is ambiguous: $method is declared by $ids',
      );
    }
    return matches.single;
  }

  List<JsPlugin> _mountedPlugins() {
    return <JsPlugin>[
      for (final features in _allFeatures)
        if (features is JsPluginFeatures) features.plugin,
    ];
  }

  Future<Object?> _evaluateModuleNamespaceValue(
    String module,
    String asyncBody, {
    Duration? timeout,
    required String name,
  }) async {
    final validModule = _canonicalModuleName(_validateModuleName(module));
    final callId = _nextPluginCallId++;
    final resultName = '__quickjsPluginResult_$callId';
    final encodedResultName = jsonEncode(resultName);
    final namespaceName = await _ensureModuleNamespaceGlobal(
      validModule,
      timeout: timeout,
    );
    final encodedNamespaceName = jsonEncode(namespaceName);
    final validName = _validateModuleName(name);
    late final String payloadJson;
    try {
      payloadJson = await runRaw(
        '''
const __quickjsModuleNamespace = globalThis[$encodedNamespaceName];
const inflate = ${_dartValueInflateFunctionSource()};
const convert = ${_jsValueConvertFunctionSource()};
try {
  globalThis[$encodedResultName] = (async () => {
$asyncBody
  })();
  return await globalThis[$encodedResultName];
} finally {
  delete globalThis[$encodedResultName];
}
''',
        timeout: timeout,
        name: '$validName:result',
      );
    } catch (error, stackTrace) {
      QuickjsDiag.log(
        'module.call',
        'FAILED name=$validName module=$validModule error=$error',
      );
      final breadcrumb = await _readModuleCallBreadcrumb();
      QuickjsDiag.log(
        'module.call',
        'breadcrumb name=$validName module=$validModule value=$breadcrumb',
      );
      Error.throwWithStackTrace(error, stackTrace);
    }
    final payload = jsonDecode(payloadJson) as Map<String, Object?>;
    if (payload['type'] == 'conversionError') {
      throw JsValueConversionException(payload['message']! as String);
    }
    return _normalizeStructuredValue(payload);
  }

  Future<Object?> _readModuleCallBreadcrumb() async {
    try {
      return await debugEvaluateValue(
        'globalThis[${jsonEncode(_moduleCallBreadcrumbName)}] ?? null',
        timeout: const Duration(milliseconds: 250),
        name: '<quickjs:module-call-breadcrumb>',
      );
    } catch (error) {
      return 'unavailable: $error';
    }
  }

  Future<String> _ensureModuleNamespaceGlobal(
    String module, {
    Duration? timeout,
  }) async {
    final existing = _moduleNamespaceGlobalNames[module];
    if (existing != null) {
      return existing;
    }

    final namespaceName = '__quickjsModuleNamespace_${_nextPluginCallId++}';
    final encodedModule = jsonEncode(module);
    final encodedNamespaceName = jsonEncode(namespaceName);
    await evalModule(
      '''
import * as namespace from $encodedModule;
Object.defineProperty(globalThis, $encodedNamespaceName, {
  value: namespace,
  configurable: true,
  enumerable: false,
  writable: false,
});
''',
      name: '<quickjs:module-namespace:$module>',
      timeout: timeout,
    );
    _moduleNamespaceGlobalNames[module] = namespaceName;
    return namespaceName;
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
    _state = JsRuntimeState.closed;
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

  /// 中止当前任务、取消等待队列并重建底层 runtime。
  ///
  /// 完成后会重新创建底层 runtime，因此同一个 [Quickjs] 实例仍可继续使用。
  Future<void> restart() {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<void>.error(terminalError);
    }

    final currentRestart = _restartFuture;
    if (currentRestart != null) {
      return currentRestart;
    }

    const cancellation = JsCancelledException();
    _cancelHostProviderCalls(cancellation);
    _cancelQueued(cancellation);
    final running = _running;
    _state = JsRuntimeState.restarting;
    final restarted =
        (running == null
                ? _runtime.dispose()
                : _runtime
                      .stop()
                      .then<void>(
                        (_) => running,
                        onError: (Object _, StackTrace _) => running,
                      )
                      .catchError((Object _) {}))
            .then<void>((_) async {
              if (!_isTerminal) {
                await _replaceCurrentRuntime();
                _state = JsRuntimeState.ready;
              }
            })
            .whenComplete(() {
              _restartFuture = null;
              _drainQueue();
            });
    _restartFuture = restarted;
    return restarted;
  }

  Future<void> _replaceCurrentRuntime() async {
    _classInstances.clear();
    _callbackDebugNames.clear();
    _moduleDebugNames.clear();
    _moduleNamespaceGlobalNames.clear();
    _runtime = await _backend.createRuntime(_options);
    await _installInitialEnvironmentOnCurrentRuntime();
  }

  Future<String> _enqueue(
    String code, {
    Duration? timeout,
    String name = '<eval>',
    bool async = false,
  }) {
    final rejection = _queueRejection;
    if (rejection != null) return Future<String>.error(rejection);

    final request = _QueuedEval(
      ++_nextEvalRequestId,
      code,
      timeout,
      name,
      async,
    );
    _queue.add(request);
    QuickjsDiag.log(
      'eval.queue',
      'enqueue id=${request.id} name=$name async=$async '
          'timeoutMs=${timeout?.inMilliseconds} depth=${_queue.length}',
    );
    // timeout 从入队开始计算，避免排队过久的任务进入 runtime 后才超时。
    request.startQueueTimer(() {
      if (_queue.remove(request)) {
        QuickjsDiag.log(
          'eval.queue.timeout',
          'id=${request.id} name=${request.name} async=${request.async} '
              'timeoutMs=${request.timeout?.inMilliseconds}',
        );
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
    final rejection = _queueRejection;
    if (rejection != null) return Future<String>.error(rejection);
    final request = _QueuedModuleEval(
      ++_nextEvalRequestId,
      source,
      name,
      modules,
      timeout,
    );
    _queue.add(request);
    QuickjsDiag.log(
      'eval.queue',
      'enqueue id=${request.id} name=$name module=true '
          'timeoutMs=${timeout?.inMilliseconds} depth=${_queue.length}',
    );
    request.startQueueTimer(() {
      if (_queue.remove(request)) {
        QuickjsDiag.log(
          'eval.queue.timeout',
          'id=${request.id} name=${request.name} module=true '
              'timeoutMs=${request.timeout?.inMilliseconds}',
        );
        request.completeError(const JsTimeoutException());
      }
    });
    _drainQueue();
    return request.future;
  }

  Object? get _queueRejection =>
      _terminalError ??
      (_queue.length >= _options.maxPendingTasks
          ? const JsQueueFullException()
          : null);

  void _drainQueue() {
    if (_state != JsRuntimeState.ready ||
        _running != null ||
        _restartFuture != null ||
        _queue.isEmpty) {
      return;
    }

    final request = _queue.removeFirst();
    _runningRequest = request;
    request.cancelQueueTimer();

    final timeout = request.remainingTimeout;
    final startedAt = DateTime.now();
    final idleMs = _lastEvalEndedAt == null
        ? null
        : startedAt.difference(_lastEvalEndedAt!).inMilliseconds;
    QuickjsDiag.log(
      'eval.queue',
      'start id=${request.id} name=${request.name} async=${request.async} '
          'module=${request is _QueuedModuleEval} idleMs=$idleMs '
          'remainingTimeoutMs=${timeout?.inMilliseconds} depth=${_queue.length}',
    );
    if (timeout != null && timeout <= Duration.zero) {
      QuickjsDiag.log(
        'eval.queue.timeout',
        'expired-before-run id=${request.id} name=${request.name}',
      );
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
    _state = JsRuntimeState.running;
    // _running 代表当前占用 runtime 的任务；完成后再继续 drain，保证单 runtime
    // 不会被并发重入。
    _running = running.then<void>(
      request.complete,
      onError: (Object error, StackTrace stackTrace) {
        final effectiveError = _attachSourceMap(error, request.name);
        if (error is JsRuntimeClosedException ||
            error is JsRuntimeCrashException) {
          _state = error is JsRuntimeCrashException
              ? JsRuntimeState.failed
              : JsRuntimeState.closed;
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
          _lastEvalEndedAt = DateTime.now();
          final elapsedMs = DateTime.now().difference(startedAt).inMilliseconds;
          if (request.failed) {
            QuickjsDiag.log(
              'eval.queue',
              'FAILED id=${request.id} name=${request.name} '
                  'elapsedMs=$elapsedMs error=${request.error}',
            );
          } else {
            QuickjsDiag.log(
              'eval.queue',
              'done id=${request.id} name=${request.name} elapsedMs=$elapsedMs',
            );
          }
          _running = null;
          _runningRequest = null;
          if (_state == JsRuntimeState.running) {
            _state = JsRuntimeState.ready;
          }
          _drainQueue();
        },
        onError: (Object _, StackTrace _) {
          _lastEvalEndedAt = DateTime.now();
          QuickjsDiag.log(
            'eval.queue',
            'FAILED id=${request.id} name=${request.name} '
                'elapsedMs=${DateTime.now().difference(startedAt).inMilliseconds}',
          );
          _running = null;
          _runningRequest = null;
          if (_state == JsRuntimeState.running) {
            _state = JsRuntimeState.ready;
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
    if (error is! JsThrownException) {
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
    JsSourceLocation? firstLocation;
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

  JsSourceLocation? _remapExceptionLocation(
    JsThrownException error,
    String sourceName,
    JsSourceMap sourceMap,
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
      _state == JsRuntimeState.closed || _state == JsRuntimeState.failed;

  Object? get _terminalError {
    return switch (_state) {
      JsRuntimeState.closed => JsRuntimeClosedException(),
      JsRuntimeState.failed => _failure ?? JsRuntimeCrashException(),
      _ => null,
    };
  }

  Future<Object?> _callFunctionHandle(
    int handleId,
    List<Object?> args, {
    Duration? timeout,
  }) async {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<Object?>.error(terminalError);
    }
    final payload = await _enqueue(
      _wrapStructuredFunctionHandleCall(handleId, args),
      timeout: timeout,
    );
    return _decodeStructuredPayload(payload);
  }

  Future<String> _callFunctionHandleRaw(
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

  Future<Object?> _runFunctionHandle(
    int handleId,
    List<Object?> args, {
    Duration? timeout,
  }) async {
    final payload = await _runFunctionHandleRaw(
      handleId,
      args,
      timeout: timeout,
      structured: true,
    );
    return _decodeStructuredPayload(payload);
  }

  Future<String> _runFunctionHandleRaw(
    int handleId,
    List<Object?> args, {
    Duration? timeout,
    bool structured = false,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }
    return _enqueue(
      _wrapAsyncFunctionBody(
        structured
            ? _wrapStructuredFunctionHandleCallAwait(handleId, args)
            : _wrapFunctionHandleCallAwait(handleId, args),
      ),
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
    JsModuleFormat format,
  ) async {
    final configuredModules = await _hostModuleSourceMap(format);
    final loader = _moduleLoader;
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

  Future<Map<String, String>> _hostModuleSourceMap(
    JsModuleFormat format,
  ) async {
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
      modules[name] = await module.loadSource();
    }
    return Map<String, String>.unmodifiable(modules);
  }

  void _validateHostModuleNames(JsModuleFormat format) {
    final configuredModules = _effectiveHostModules();
    if (configuredModules.isEmpty) {
      return;
    }
    final names = <String>{};
    for (final module in configuredModules) {
      if (module.format != format) {
        continue;
      }
      final name = _canonicalModuleName(_validateModuleName(module.specifier));
      if (!names.add(name)) {
        throw JsValueConversionException(
          'QuickJS host module is registered more than once: $name',
        );
      }
    }
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

  List<JsProviderDebugInfo> _debugProviderDetails() {
    final details = <JsProviderDebugInfo>[
      for (final provider in _effectiveHostProviders())
        JsProviderDebugInfo(
          name: _validateHostProviderName(provider.name),
          debugName: provider.debugName ?? provider.name,
          implementation: provider.implementation,
        ),
    ];
    details.sort((left, right) => left.name.compareTo(right.name));
    return details;
  }

  List<JsPluginDebugInfo> _debugPluginDetails() {
    final details = <JsPluginDebugInfo>[
      for (final features in _allFeatures)
        if (features is JsPluginFeatures)
          JsPluginDebugInfo(
            id: features.plugin.manifest.id,
            version: features.plugin.manifest.version,
            entry: features.plugin.manifest.entry,
            exports: List<String>.unmodifiable(
              features.plugin.manifest.exports,
            ),
            featuresName: _validateFeaturesName(features.name),
            moduleNames: List<String>.unmodifiable(
              features.plugin.modules.map((module) => module.specifier).toList()
                ..sort(),
            ),
            init: features.plugin.manifest.init,
            dispose: features.plugin.manifest.dispose,
          ),
    ];
    details.sort((left, right) => left.id.compareTo(right.id));
    return details;
  }

  List<String> _debugMountNames() {
    return <String>[
      for (final features in _allFeatures) _validateFeaturesName(features.name),
    ]..sort();
  }

  void _validateStaticHostConfiguration() {
    final featuresNames = <String>{};
    for (final features in _allFeatures) {
      final name = _validateFeaturesName(features.name);
      if (!featuresNames.add(name)) {
        throw JsValueConversionException(
          'QuickJS host features is registered more than once: $name',
        );
      }
    }

    final globalNames = <String>{};
    final browserGlobals = _effectiveBrowserGlobals();
    if (browserGlobals.window) {
      globalNames.add('window');
    }
    if (browserGlobals.self) {
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

    _validateHostModuleNames(JsModuleFormat.esModule);
    _validateHostModuleNames(JsModuleFormat.commonJs);
  }

  void _validateFeaturesAgainstLoadedModules(
    JsFeatures features, {
    JsFeatures? replacedFeatures,
  }) {
    final replaceableNames = <String>{
      if (replacedFeatures != null)
        for (final module in replacedFeatures.modules)
          _canonicalModuleName(_validateModuleName(module.specifier)),
    };
    for (final module in features.modules) {
      final name = _canonicalModuleName(_validateModuleName(module.specifier));
      if (_moduleDebugNames.contains(name) &&
          !replaceableNames.contains(name)) {
        throw JsValueConversionException(
          'QuickJS loaded module cannot be shadowed by a runtime features: $name',
        );
      }
    }
  }

  JsGlobals _effectiveBrowserGlobals() {
    var window = false;
    var self = false;
    for (final features in _allFeatures) {
      final browserGlobals = features.browserGlobals;
      window = window || browserGlobals.window;
      self = self || browserGlobals.self;
    }
    return JsGlobals(window: window, self: self);
  }

  List<JsScript> _effectiveHostScripts() {
    return <JsScript>[
      ..._providerGlobalsHostScripts(),
      for (final features in _allFeatures) ...features.scripts,
      ..._scripts,
    ];
  }

  List<JsScript> _providerGlobalsHostScripts() {
    final scripts = <JsScript>[];
    for (final features in _allFeatures) {
      final script = _providerGlobalsHostScript(
        features.providers,
        features.name,
      );
      if (script != null) {
        scripts.add(script);
      }
    }
    final runtimeScript = _providerGlobalsHostScript(_providers, 'runtime');
    if (runtimeScript != null) {
      scripts.add(runtimeScript);
    }
    return scripts;
  }

  JsScript? _providerGlobalsHostScript(
    List<JsProvider> providers,
    String scopeName,
  ) {
    final globals = <String, String>{};
    for (final provider in providers) {
      final globalName = provider.globalName;
      if (globalName != null) {
        if (globals.containsKey(globalName)) {
          throw JsValueConversionException(
            'QuickJS host global is registered more than once: $globalName',
          );
        }
        globals[globalName] = provider.name;
      }
    }
    if (globals.isEmpty) {
      return null;
    }
    return JsScript.providerGlobals(
      name: '<quickjs:provider-globals:$scopeName>',
      globals: globals,
    );
  }

  List<JsProvider> _effectiveHostProviders() {
    return <JsProvider>[
      for (final features in _allFeatures) ...features.providers,
      ..._providers,
    ];
  }

  List<JsModule> _effectiveHostModules() {
    return <JsModule>[
      for (final features in _allFeatures) ...features.modules,
      ..._modules,
    ];
  }

  Iterable<JsFeatures> get _allFeatures sync* {
    yield* _initialFeatures;
    yield* _runtimeFeatures;
  }
}

Uint8List _normalizeBytes(Object? value) {
  final bytes = value as List;
  return Uint8List.fromList([for (final byte in bytes) (byte as num).toInt()]);
}

JsConsoleLevel _consoleLevelFromName(String name) {
  return switch (name) {
    'warn' => JsConsoleLevel.warn,
    'error' => JsConsoleLevel.error,
    _ => JsConsoleLevel.log,
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

String _wrapInitialEnvironmentBatch(
  List<({String name, String source})> sources,
) {
  final buffer = StringBuffer('(() => {\n');
  for (final source in sources) {
    final namedSource = '${source.source}\n//# sourceURL=${source.name}';
    buffer
      ..write('(0, eval)(')
      ..write(jsonEncode(namedSource))
      ..writeln(');');
  }
  return (buffer..write('})()')).toString();
}

String _wrapInstallBrowserGlobals(JsGlobals browserGlobals) {
  final aliases = <String>[
    if (browserGlobals.window) 'window',
    if (browserGlobals.self) 'self',
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
  const previous = globalThis.__quickjsHostProviders;
  if (previous && typeof previous === 'object') {
    for (const name of Object.keys(previous)) {
      Object.defineProperty(registry, name, {
        value: previous[name],
        configurable: false,
        enumerable: true,
        writable: false,
      });
    }
  }
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

String _wrapStructuredFunctionHandleCall(int handleId, List<Object?> args) {
  return '''
(() => {
const convert = ${_jsValueConvertFunctionSource()};
const value = ${_wrapFunctionHandleCall(handleId, args)};
return JSON.stringify(convert(value, new WeakSet()));
})()
''';
}

String _wrapStructuredFunctionHandleCallAwait(
  int handleId,
  List<Object?> args,
) {
  return '''
const convert = ${_jsValueConvertFunctionSource()};
const value = await (async () => {
${_wrapFunctionHandleCallAwait(handleId, args)}
})();
return JSON.stringify(convert(value, new WeakSet()));
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
  Map<String, Object> properties,
  List<Map<String, String?>> accessors,
  List<Map<String, String>> methods,
) {
  final encodedName = jsonEncode(name);
  final encodedStateName = jsonEncode('__quickjsClass_${classId}_state');
  final encodedConstructorCallbackName = jsonEncode(constructorCallbackName);
  final encodedProperties = jsonEncode(properties);
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
const inflate = ${_dartValueInflateFunctionSource()};
const properties = $encodedProperties;
for (const key of Object.keys(properties)) {
  Object.defineProperty(QuickjsBoundClass.prototype, key, {
    value: inflate(properties[key]),
    configurable: false,
    enumerable: true,
    writable: false,
  });
}
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
(payload, depth = 0, budget = { nodes: 0, maxNodes: 10000, maxDepth: 32 }) => {
  if (depth > budget.maxDepth) {
    throw new RangeError('QuickJS Dart value graph is too deep');
  }
  budget.nodes += 1;
  if (budget.nodes > budget.maxNodes) {
    throw new RangeError('QuickJS Dart value graph is too large');
  }
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
      return payload.value.map((item) => inflate(item, depth + 1, budget));
    case 'object': {
      const value = {};
      for (const key of Object.keys(payload.value)) {
        value[key] = inflate(payload.value[key], depth + 1, budget);
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

String _jsValueConvertFunctionSource() {
  return '''
(value, seen, depth = 0, budget = { nodes: 0, maxNodes: 10000, maxDepth: 32 }) => {
  const unsupported = (reason) => ({
    type: 'conversionError',
    message: 'QuickJS value cannot be converted to a Dart value: ' + reason,
  });
  if (depth > budget.maxDepth) {
    return unsupported('object graph is too deep');
  }
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
  // Count recursive containers, not primitive leaves. This keeps the guard
  // meaningful while allowing large flat display lists and numeric datasets.
  budget.nodes += 1;
  if (budget.nodes > budget.maxNodes) {
    return unsupported('object graph is too large');
  }
  if (seen.has(value)) {
    return unsupported('circular reference');
  }
  seen.add(value);
  try {
    if (Array.isArray(value)) {
      const items = [];
      for (const item of value) {
        const converted = convert(item, seen, depth + 1, budget);
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
        const converted = convert(value[key], seen, depth + 1, budget);
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

String _validateFeaturesName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host features name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host features name must not contain NUL',
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
  final JsSourceLocation? location;
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

Object _encodeDartValue(
  Object? value,
  Set<Object> seen, [
  int depth = 0,
  _DartValueBudget? budget,
]) {
  final activeBudget = budget ?? _DartValueBudget();
  if (depth > _DartValueBudget.maxDepth) {
    throw const JsValueConversionException(
      'QuickJS Dart value graph is too deep',
    );
  }
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
    activeBudget.countContainer();
    return _encodeWithCycleCheck(value, seen, () {
      return {
        'type': 'array',
        'value': [
          for (final item in value)
            _encodeDartValue(item, seen, depth + 1, activeBudget),
        ],
      };
    });
  }
  if (value is Map) {
    activeBudget.countContainer();
    return _encodeWithCycleCheck(value, seen, () {
      return {
        'type': 'object',
        'value': _encodeDartMap(value, seen, depth + 1, activeBudget),
      };
    });
  }
  throw JsValueConversionException(
    'QuickJS global value cannot be converted to JavaScript: ${value.runtimeType}',
  );
}

Map<String, Object> _encodeDartMap(
  Map value,
  Set<Object> seen,
  int depth,
  _DartValueBudget budget,
) {
  final result = <String, Object>{};
  for (final entry in value.entries) {
    final key = entry.key;
    if (key is! String) {
      throw JsValueConversionException(
        'QuickJS global map keys must be strings',
      );
    }
    result[key] = _encodeDartValue(entry.value, seen, depth, budget);
  }
  return result;
}

final class _DartValueBudget {
  static const maxNodes = 10000;
  static const maxDepth = 32;
  int _nodes = 0;

  void countContainer() {
    if (++_nodes > maxNodes) {
      throw const JsValueConversionException(
        'QuickJS Dart value graph is too large',
      );
    }
  }
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
  _QueuedEval(this.id, this.code, this.timeout, this.name, this.async);

  final int id;
  final String code;
  final Duration? timeout;
  final String name;
  final bool async;
  final Completer<String> _completer = Completer<String>();
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _queueTimer;
  Object? error;

  Future<String> get future => _completer.future;
  bool get failed => error != null;

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
    this.error = error;
    // 队列任务可能在调用方注册 expectLater 之前被取消；先挂一个 ignore，
    // 避免 Dart 把这类预期内的取消当成未处理错误。
    _completer.future.ignore();
    _completer.completeError(error, stackTrace);
  }
}

final class _QueuedModuleEval extends _QueuedEval {
  _QueuedModuleEval(
    int id,
    String code,
    String name,
    this.modules,
    Duration? timeout,
  ) : super(id, code, timeout, name, false);

  final Map<String, String> modules;
}
