import 'dart:async';
import 'dart:collection';

import 'quickjs_backend.dart';
import 'quickjs_backend_factory.dart';
import 'quickjs_exception.dart';
import 'quickjs_runtime_base.dart';

enum _QuickjsRuntimeState { ready, running, stopping, closed, failed }

/// QuickJS 的公开 Dart 入口。
///
/// 这个类只负责管理请求队列和 runtime 生命周期；真正的执行发生在平台 backend
/// 里，native 侧是 Dart isolate + FFI，web 侧是 Web Worker + WASM。
class Quickjs {
  Quickjs._(this._backend, this._runtime);

  final QuickjsBackend _backend;
  QuickjsJsRuntimeBase _runtime;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  _QuickjsRuntimeState _state = _QuickjsRuntimeState.ready;
  Object? _failure;
  Future<void>? _running;
  Future<void>? _disposeFuture;
  Future<void>? _stopFuture;

  /// 为当前平台创建一个独立的 QuickJS runtime。
  static Future<Quickjs> create() async {
    final backend = await createQuickjsBackend();
    return Quickjs._(backend, await backend.createRuntime());
  }

  /// 当前打包进插件的 QuickJS 版本号。
  String get quickjsVersion => _backend.quickjsVersion;

  /// 在当前 runtime 中执行 [code]。
  ///
  /// 调用只会入队，不会在 Flutter UI isolate 中同步执行 JS。
  Future<String> eval(String code, {Duration? timeout}) {
    return _enqueue(code, timeout: timeout);
  }

  /// [eval] 的兼容别名，保留给更自然的调用命名。
  Future<String> evaluate(String code, {Duration? timeout}) {
    return eval(code, timeout: timeout);
  }

  /// 释放当前实例持有的 runtime。
  ///
  /// dispose 会立即拒绝新请求，取消尚未开始的队列任务，并等待正在执行的任务收尾。
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }

    _state = _QuickjsRuntimeState.closed;
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

    _state = _QuickjsRuntimeState.stopping;
    final stopped = _runtime
        .stop()
        .then<void>(
          (_) => running,
          onError: (Object _, StackTrace _) => running,
        )
        .catchError((Object _) {})
        .then<void>((_) async {
          if (!_isTerminal) {
            _runtime = await _backend.createRuntime();
            _state = _QuickjsRuntimeState.ready;
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
    if (_state != _QuickjsRuntimeState.ready ||
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
    _state = _QuickjsRuntimeState.running;
    // _running 代表当前占用 runtime 的任务；完成后再继续 drain，保证单 runtime
    // 不会被并发重入。
    _running = running.then<void>(
      request.complete,
      onError: (Object error, StackTrace stackTrace) {
        if (error is JsRuntimeClosedException ||
            error is JsRuntimeCrashException) {
          _state = error is JsRuntimeCrashException
              ? _QuickjsRuntimeState.failed
              : _QuickjsRuntimeState.closed;
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
          if (_state == _QuickjsRuntimeState.running) {
            _state = _QuickjsRuntimeState.ready;
          }
          _drainQueue();
        },
        onError: (Object _, StackTrace _) {
          _running = null;
          if (_state == _QuickjsRuntimeState.running) {
            _state = _QuickjsRuntimeState.ready;
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
      _state == _QuickjsRuntimeState.closed ||
      _state == _QuickjsRuntimeState.failed;

  Object? get _terminalError {
    return switch (_state) {
      _QuickjsRuntimeState.closed => JsRuntimeClosedException(),
      _QuickjsRuntimeState.failed => _failure ?? JsRuntimeCrashException(),
      _ => null,
    };
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
