import 'dart:async';
import 'dart:collection';

import 'src/quickjs_backend.dart';
import 'src/quickjs_backend_factory.dart';
import 'src/quickjs_runtime_base.dart';

/// Flutter bindings for [QuickJS](https://github.com/quickjs-ng/quickjs).
class Quickjs {
  Quickjs._(this._backend, this._runtime);

  final QuickjsBackend _backend;
  final QuickjsJsRuntimeBase _runtime;
  final Queue<_QueuedEval> _queue = Queue<_QueuedEval>();
  bool _closed = false;
  Future<void>? _running;
  Future<void>? _disposeFuture;

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
  Future<String> eval(String code) {
    final request = _enqueue(() => _runtime.evaluate(code));
    return request;
  }

  /// Evaluates [code] in this QuickJS instance.
  Future<String> evaluate(String code) {
    return eval(code);
  }

  /// Releases the runtime owned by this QuickJS instance.
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    _closed = true;
    _cancelQueued(StateError('QuickJS runtime is closed'));
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

  Future<String> _enqueue(Future<String> Function() execute) {
    if (_closed) {
      return Future<String>.error(StateError('QuickJS runtime is closed'));
    }
    final request = _QueuedEval(execute);
    _queue.add(request);
    _drainQueue();
    return request.completer.future;
  }

  void _drainQueue() {
    if (_running != null || _closed || _queue.isEmpty) {
      return;
    }

    final request = _queue.removeFirst();
    final running = Future<String>.sync(request.execute);
    _running = running.then<void>(
      request.completer.complete,
      onError: request.completer.completeError,
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
      if (!request.completer.isCompleted) {
        request.completer.completeError(error);
      }
    }
  }
}

final class _QueuedEval {
  _QueuedEval(this.execute);

  final Future<String> Function() execute;
  final Completer<String> completer = Completer<String>();
}
