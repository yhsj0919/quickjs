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
  Future<void>? _disposeFuture;
  Future<void>? _stopFuture;

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

    _state = QuickjsRuntimeState.closed;
    _cancelQueued(JsRuntimeClosedException());
    _disposeFuture = (_running ?? Future<void>.value()).then(
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

  Future<String> _enqueue(String code, {Duration? timeout}) {
    final terminalError = _terminalError;
    if (terminalError != null) {
      return Future<String>.error(terminalError);
    }

    final request = _QueuedEval(code, timeout);
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

  void _drainQueue() {
    if (_state != QuickjsRuntimeState.ready ||
        _running != null ||
        _stopFuture != null ||
        _queue.isEmpty) {
      return;
    }

    final request = _queue.removeFirst();
    request.cancelQueueTimer();

    final timeout = request.remainingTimeout;
    if (timeout != null && timeout <= Duration.zero) {
      request.completeError(const JsTimeoutException());
      _drainQueue();
      return;
    }

    final running = Future<String>.sync(
      () => _runtime.evaluate(request.code, timeout: timeout),
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
          if (_state == QuickjsRuntimeState.running) {
            _state = QuickjsRuntimeState.ready;
          }
          _drainQueue();
        },
        onError: (Object _, StackTrace _) {
          _running = null;
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
  _QueuedEval(this.code, this.timeout);

  final String code;
  final Duration? timeout;
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
