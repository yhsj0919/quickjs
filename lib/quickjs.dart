import 'dart:async';

import 'src/quickjs_backend.dart';
import 'src/quickjs_backend_factory.dart';
import 'src/quickjs_runtime_base.dart';

/// Flutter bindings for [QuickJS](https://github.com/quickjs-ng/quickjs).
class Quickjs {
  Quickjs._(this._backend, this._runtime);

  final QuickjsBackend _backend;
  final QuickjsJsRuntimeBase _runtime;
  bool _closed = false;
  Future<void> _tail = Future<void>.value();
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
    _disposeFuture = _tail.catchError((Object _) {}).then((_) {
      return _runtime.dispose();
    });
    return _disposeFuture!;
  }

  Future<T> _enqueue<T>(Future<T> Function() execute) {
    if (_closed) {
      return Future<T>.error(StateError('QuickJS runtime is closed'));
    }
    final request = _tail.then((_) {
      return execute();
    });
    _tail = request.then<void>((_) {}, onError: (Object _, StackTrace _) {});
    return request;
  }
}
