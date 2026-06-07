import 'src/quickjs_backend.dart';
import 'src/quickjs_backend_factory.dart';
import 'src/quickjs_runtime_base.dart';

/// Flutter bindings for [QuickJS](https://github.com/quickjs-ng/quickjs).
class Quickjs {
  Quickjs._(this._backend, this._runtime);

  final QuickjsBackend _backend;
  final QuickjsJsRuntimeBase _runtime;
  bool _closed = false;

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
  Future<String> evaluate(String code) async {
    _ensureOpen();
    return _runtime.evaluate(code);
  }

  /// Releases the runtime owned by this QuickJS instance.
  void dispose() {
    if (_closed) {
      return;
    }
    _runtime.dispose();
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('QuickJS runtime is closed');
    }
  }
}
