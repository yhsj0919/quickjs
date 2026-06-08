import 'dart:async';
import 'dart:collection';

import 'src/quickjs_backend.dart';
import 'src/quickjs_backend_factory.dart';
import 'src/quickjs_exception.dart';
import 'src/quickjs_runtime_base.dart';

export 'src/quickjs_exception.dart';

/// Flutter bindings for [QuickJS](https://github.com/quickjs-ng/quickjs).
class Quickjs {
  Quickjs._(this._backend, this._runtime);

  final QuickjsBackend _backend;
  QuickjsJsRuntimeBase _runtime;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  bool _closed = false;
  Future<void>? _running;
  Future<void>? _disposeFuture;
  Future<void>? _stopFuture;

  /// Creates a [Quickjs] instance for the current platform.
  ///
  /// On web, initializes the QuickJS WASM module (via quickjs-wasi).
  static Future<Quickjs> create() async {
    final backend = await createQuickjsBackend();
    return Quickjs._(backend, await backend.createRuntime());
  }

  /// Bundled QuickJS version string.
  String get quickjsVersion => _backend.quickjsVersion;

  /// Evaluates [code] in this QuickJS instance.
  Future<String> eval(String code, {Duration? timeout}) {
    final request = _enqueue(code, timeout: timeout);
    return request;
  }

  /// Evaluates [code] in this QuickJS instance.
  Future<String> evaluate(String code, {Duration? timeout}) {
    return eval(code, timeout: timeout);
  }

  /// Releases the runtime owned by this QuickJS instance.
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    _closed = true;
    _cancelQueued(JsRuntimeClosedException());
    _disposeFuture = (_running ?? Future<void>.value()).then(
      (_) {
        return _runtime.dispose();
      },
      onError: (Object _, StackTrace _) {
        return _runtime.dispose();
      },
    );
    return _disposeFuture!;
  }

  /// Stops the currently running evaluation and cancels queued evaluations.
  ///
  /// The [Quickjs] instance remains usable after this future completes.
  Future<void> stop() {
    if (_closed) {
      return Future<void>.error(JsRuntimeClosedException());
    }
    final current = _stopFuture;
    if (current != null) {
      return current;
    }

    _cancelQueued(JsCancelledException());
    final running = _running;
    if (running == null) {
      return Future<void>.value();
    }

    final stopped = _runtime.stop().then<void>(
      (_) => running,
      onError: (Object _, StackTrace _) => running,
    ).catchError((Object _) {}).then<void>((_) async {
      if (_closed) {
        return;
      }
      _runtime = await _backend.createRuntime();
    }).whenComplete(() {
      _stopFuture = null;
      _drainQueue();
    });
    _stopFuture = stopped;
    return stopped;
  }

  Future<String> _enqueue(String code, {Duration? timeout}) {
    if (_closed) {
      return Future<String>.error(JsRuntimeClosedException());
    }
    final request = _QueuedEval(code, timeout);
    _queue.add(request);
    request.startQueueTimer(() {
      if (_queue.remove(request) && !request.completer.isCompleted) {
        request.completer.completeError(const JsTimeoutException());
      }
    });
    _drainQueue();
    return request.completer.future;
  }

  void _drainQueue() {
    if (_running != null ||
        _stopFuture != null ||
        _closed ||
        _queue.isEmpty) {
      return;
    }

    final request = _queue.removeFirst();
    request.cancelQueueTimer();
    final timeout = request.remainingTimeout;
    if (timeout != null && timeout <= Duration.zero) {
      request.completer.completeError(const JsTimeoutException());
      _drainQueue();
      return;
    }
    final running = Future<String>.sync(
      () => _runtime.evaluate(request.code, timeout: timeout),
    );
    _running = running.then<void>(
      request.completer.complete,
      onError: (Object error, StackTrace stackTrace) {
        if (error is JsRuntimeClosedException) {
          _closed = true;
          _cancelQueued(error);
        }
        request.completer.completeError(error, stackTrace);
      },
    );
    _running!.then<void>(
      (_) {
        _running = null;
        _drainQueue();
      },
      onError: (Object _, StackTrace _) {
        _running = null;
        _drainQueue();
      },
    );
  }

  void _cancelQueued(Object error) {
    while (_queue.isNotEmpty) {
      final request = _queue.removeFirst();
      request.cancelQueueTimer();
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
  }
}

final class _QueuedEval {
  _QueuedEval(this.code, this.timeout);

  final String code;
  final Duration? timeout;
  final Completer<String> completer = Completer<String>();
  final Stopwatch _stopwatch = Stopwatch()..start();
  Timer? _queueTimer;

  Duration? get remainingTimeout {
    final currentTimeout = timeout;
    if (currentTimeout == null) {
      return null;
    }
    return currentTimeout - _stopwatch.elapsed;
  }

  void startQueueTimer(void Function() onTimeout) {
    final currentTimeout = timeout;
    if (currentTimeout == null) {
      return;
    }
    _queueTimer = Timer(currentTimeout, onTimeout);
  }

  void cancelQueueTimer() {
    _queueTimer?.cancel();
    _queueTimer = null;
  }
}
