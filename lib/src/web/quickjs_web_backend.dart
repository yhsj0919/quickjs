import 'dart:js_interop';

import '../quickjs_backend.dart';
import '../quickjs_runtime_base.dart';
import 'quickjs_web_loader.dart';

/// QuickJS version in the WASM build (quickjs-wasi / quickjs).
const String kWebQuickjsVersion = '0.14.0';

/// WASM backend for Flutter web (via [quickjs-wasi](https://www.npmjs.com/package/quickjs-wasi)).
class WebQuickjsBackend implements QuickjsBackend {
  WebQuickjsBackend._(this._host);

  final QuickjsWebHost _host;

  static WebQuickjsBackend? _instance;

  static Future<WebQuickjsBackend> create({
    String? bridgeModuleUrl,
    String? wasmUrl,
  }) async {
    if (_instance != null) {
      return _instance!;
    }

    final host = await loadQuickjsWebHost();
    final resolvedBridge =
        bridgeModuleUrl ??
        quickjsNgPackageAssetUrl('assets/web/quickjs_bridge.mjs');
    final resolvedWasm =
        wasmUrl ?? quickjsNgPackageAssetUrl('assets/web/quickjs.wasm');

    await host.ensureInitialized(resolvedWasm.toJS, resolvedBridge.toJS).toDart;
    _instance = WebQuickjsBackend._(host);
    return _instance!;
  }

  @override
  String get quickjsVersion => kWebQuickjsVersion;

  @override
  Future<QuickjsJsRuntimeBase> createRuntime() async {
    final id = (await _host.runtimeNew().toDart).toDartInt;
    return WebQuickjsJsRuntime(_host, id);
  }

  @override
  Future<String> evaluate(String code) async {
    return (await _host.evalCode(code.toJS).toDart).toDart;
  }
}

final class WebQuickjsJsRuntime implements QuickjsJsRuntimeBase {
  WebQuickjsJsRuntime(this._host, this._id);

  final QuickjsWebHost _host;
  final int _id;
  bool _closed = false;

  @override
  String evaluate(String code) {
    _ensureOpen();
    return _host.runtimeEval(_id.toJS, code.toJS).toDart;
  }

  @override
  void dispose() {
    if (_closed) {
      return;
    }
    _host.runtimeDispose(_id.toJS);
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('QuickJS runtime is closed');
    }
  }
}
