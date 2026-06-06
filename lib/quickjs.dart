import 'src/quickjs_backend.dart';
import 'src/quickjs_backend_factory.dart';
import 'src/quickjs_js_runtime.dart';

export 'src/quickjs_js_runtime.dart';

/// Flutter bindings for [QuickJS](https://github.com/quickjs-ng/quickjs).
class Quickjs {
  Quickjs._(this._backend);

  final QuickjsBackend _backend;

  /// Creates a [Quickjs] instance for the current platform.
  ///
  /// On web, initializes the QuickJS WASM module (via quickjs-wasi).
  static Future<Quickjs> create() async {
    return Quickjs._(await createQuickjsBackend());
  }

  /// Bundled QuickJS version string.
  String get quickjsVersion => _backend.quickjsVersion;

  /// Creates a new isolated JavaScript runtime.
  Future<QuickjsJsRuntime> createRuntime() async {
    final runtime = await _backend.createRuntime();
    return QuickjsJsRuntime.wrap(runtime);
  }

  /// Evaluates [code] in a short-lived runtime.
  Future<String> evaluate(String code) => _backend.evaluate(code);
}
