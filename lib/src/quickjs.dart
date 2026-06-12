import 'dart:async';
import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'quickjs_backend.dart';
import 'quickjs_backend_factory.dart';
import 'quickjs_exception.dart';
import 'quickjs_runtime_base.dart';
import 'quickjs_runtime_options.dart';
import 'quickjs_value.dart';

typedef QuickjsCallback = FutureOr<Object?> Function(List<Object?> args);

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

/// QuickJS 的公开 Dart 入口。
///
/// 这个类只负责管理请求队列和 runtime 生命周期；真正的执行发生在平台 backend
/// 里，native 侧是 Dart isolate + FFI，web 侧是 Web Worker + WASM。
class Quickjs {
  Quickjs._(this._backend, this._runtime, this._options);

  /// Creates a [Quickjs] wrapper around a supplied backend/runtime pair.
  ///
  /// This is intended for package tests that need deterministic control over
  /// runtime lifecycle transitions without depending on a real QuickJS worker.
  Quickjs.test(
    QuickjsBackend backend,
    QuickjsJsRuntimeBase runtime, {
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
  }) : this._(backend, runtime, options);

  final QuickjsBackend _backend;
  QuickjsJsRuntimeBase _runtime;
  final QuickjsRuntimeOptions _options;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  QuickjsRuntimeState _state = QuickjsRuntimeState.ready;
  Object? _failure;
  Future<void>? _running;
  _QueuedEval? _runningRequest;
  Future<void>? _disposeFuture;
  Future<void>? _stopFuture;
  int _nextCallbackId = 1;

  /// 为当前平台创建一个独立的 QuickJS runtime。
  static Future<Quickjs> create({
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
  }) async {
    final backend = await createQuickjsBackend();
    return Quickjs._(backend, await backend.createRuntime(options), options);
  }

  /// 当前打包进插件的 QuickJS 版本号。
  String get quickjsVersion => _backend.quickjsVersion;

  /// 当前 runtime 生命周期状态。
  QuickjsRuntimeState get state => _state;

  /// 在当前 runtime 中执行 [code]。
  ///
  /// 调用只会入队，不会在 Flutter UI isolate 中同步执行 JS。
  /// [globals] 会在本次执行期间临时注入到 JS `globalThis`，执行结束后恢复。
  Future<String> eval(
    String code, {
    Duration? timeout,
    Map<String, Object?> globals = const {},
  }) {
    return _enqueue(_wrapWithGlobals(code, globals), timeout: timeout);
  }

  /// [eval] 的兼容别名，保留给更自然的调用命名。
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    Map<String, Object?> globals = const {},
  }) {
    return eval(code, timeout: timeout, globals: globals);
  }

  /// 在当前 runtime 中执行异步 JavaScript 函数体，并等待返回的 Promise。
  ///
  /// [code] 会包裹在 `async () => { ... }` 中执行；需要返回值时使用 `return`。
  Future<String> evalAsync(
    String code, {
    Duration? timeout,
    Map<String, Object?> globals = const {},
  }) {
    return _enqueue(
      _wrapWithGlobals(_wrapAsyncFunctionBody(code), globals),
      timeout: timeout,
      async: true,
    );
  }

  /// [evalAsync] 的兼容别名。
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    Map<String, Object?> globals = const {},
  }) {
    return evalAsync(code, timeout: timeout, globals: globals);
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
    );
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
    );
    return _enqueue(
      _wrapCommonJsModule(source, validName, modules),
      timeout: timeout,
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
    return _runtime.bindCallback(callbackId, validName, (args) async {
      return callback(args);
    });
  }

  /// 在 JS `globalThis` 上绑定 `{ emit, close, error }`，并返回 Dart [Stream]。
  ///
  /// JS 侧每次 `await sink.emit(value)` 会等待 Dart 侧确认，用于串行 backpressure。
  Future<Stream<Object?>> bindSink(String name) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<Stream<Object?>>.error(terminalError);
    }
    return _runtime.bindJsSink(_validateGlobalName(name));
  }

  /// 在当前 runtime 中执行 [code]，并把基础 JS 值转换成 Dart 值。
  ///
  /// 当前阶段覆盖 number、boolean、string、null、undefined、BigInt、
  /// ArrayBuffer、Uint8Array、array 和 plain object。
  /// [globals] 会在本次执行期间临时注入到 JS `globalThis`，执行结束后恢复。
  Future<Object?> evaluateValue(
    String code, {
    Duration? timeout,
    Map<String, Object?> globals = const {},
  }) async {
    final encodedSource = jsonEncode(_wrapWithGlobals(code, globals));
    final encodedValue = await eval('''
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
''', timeout: timeout);
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

    _cancelQueued(JsCancelledException());
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
            _runtime = await _backend.createRuntime(_options);
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

  Future<String> _enqueue(
    String code, {
    Duration? timeout,
    bool async = false,
  }) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }

    final request = _QueuedEval(code, timeout, async);
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
              ? _runtime.evaluateAsync(request.code, timeout: timeout)
              : _runtime.evaluate(request.code, timeout: timeout),
      },
    );
    _state = QuickjsRuntimeState.running;
    // _running 代表当前占用 runtime 的任务；完成后再继续 drain，保证单 runtime
    // 不会被并发重入。
    _running = running.then<void>(
      request.complete,
      onError: (Object error, StackTrace stackTrace) {
        if (error is JsRuntimeClosedException ||
            error is JsRuntimeCrashException) {
          _state = error is JsRuntimeCrashException
              ? QuickjsRuntimeState.failed
              : QuickjsRuntimeState.closed;
          _failure = error;
          _cancelQueued(error);
        }
        request.completeError(error, stackTrace);
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

  Future<Map<String, String>> _buildModuleGraph(
    String rootSource,
    String rootName,
    Iterable<String> Function(String source) specifiers,
  ) async {
    final loader = _options.moduleLoader;
    if (loader == null) {
      return const {};
    }
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
          final loaded = await loader(resolved);
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
}

Uint8List _normalizeBytes(Object? value) {
  final bytes = value as List;
  return Uint8List.fromList([for (final byte in bytes) (byte as num).toInt()]);
}

String _wrapWithGlobals(String code, Map<String, Object?> globals) {
  if (globals.isEmpty) {
    return code;
  }

  final encodedSource = jsonEncode(code);
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

String _wrapAsyncFunctionBody(String code) {
  return '''
(async () => {
$code
})()
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
      return specifier;
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
    return specifier;
  }
  final slash = referrer.lastIndexOf('/');
  final base = slash < 0 ? '' : referrer.substring(0, slash + 1);
  return Uri.parse(base).resolve(specifier).path;
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
  _QueuedEval(this.code, this.timeout, this.async);

  final String code;
  final Duration? timeout;
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
  _QueuedModuleEval(String code, this.name, this.modules, Duration? timeout)
    : super(code, timeout, false);

  final String name;
  final Map<String, String> modules;
}
