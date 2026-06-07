import 'dart:js_interop';

import '../quickjs_backend.dart';
import '../quickjs_runtime_base.dart';
import 'quickjs_web_loader.dart';

/// WASM backend for Flutter web (via [quickjs-wasi](https://www.npmjs.com/package/quickjs-wasi)).
class WebQuickjsBackend implements QuickjsBackend {
  WebQuickjsBackend._(this._host, this._quickjsVersion);

  final QuickjsWebHost _host;
  final String _quickjsVersion;

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
    final resolvedWorker = quickjsNgPackageAssetUrl(
      'assets/web/quickjs_web_worker.js',
    );

    final quickjsVersion =
        (await host
                .ensureInitialized(
                  resolvedWasm.toJS,
                  resolvedBridge.toJS,
                  resolvedWorker.toJS,
                )
                .toDart)
            .toDart;
    _instance = WebQuickjsBackend._(host, quickjsVersion);
    return _instance!;
  }

  @override
  String get quickjsVersion => _quickjsVersion;

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
  Future<String> evaluate(String code) async {
    _ensureOpen();
    return (await _host.runtimeEval(_id.toJS, code.toJS).toDart).toDart;
  }

  @override
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    await _host.runtimeDispose(_id.toJS).toDart;
    _closed = true;
  }

  void _ensureOpen() {
    if (_closed) {
      throw StateError('QuickJS runtime is closed');
    }
  }
}
