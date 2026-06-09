import 'dart:js_interop';

import '../quickjs_backend.dart';
import '../quickjs_exception.dart';
import '../quickjs_runtime_base.dart';
import 'quickjs_web_loader.dart';

const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';

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
  Future<String> evaluate(String code, {Duration? timeout}) async {
    try {
      return _mapWebEvalResult(
        (await _host.evalCode(code.toJS, timeout?.inMilliseconds.toJS).toDart)
            .toDart,
      );
    } catch (error) {
      if (error is QuickjsException) {
        rethrow;
      }
      throw _mapWebError(error);
    }
  }
}

final class WebQuickjsJsRuntime implements QuickjsJsRuntimeBase {
  WebQuickjsJsRuntime(this._host, this._id);

  final QuickjsWebHost _host;
  int _id;
  bool _closed = false;
  Future<void>? _recovering;

  @override
  Future<String> evaluate(String code, {Duration? timeout}) async {
    _ensureOpen();
    try {
      return await _evaluateCurrentRuntime(code, timeout: timeout);
    } catch (error) {
      if (error is QuickjsException) {
        rethrow;
      }
      final mapped = _mapWebError(error);
      if (mapped is JsTimeoutException) {
        await _recoverRuntime();
      } else if (mapped is JsRuntimeClosedException) {
        await _recoverRuntime();
        return _evaluateCurrentRuntime(code, timeout: timeout);
      }
      throw mapped;
    }
  }

  @override
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    await _host.runtimeDispose(_id.toJS).toDart;
    _closed = true;
  }

  @override
  Future<void> stop() async {
    _ensureOpen();
    await _host.runtimeStop().toDart;
    await _recoverRuntime();
  }

  void _ensureOpen() {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
  }

  Future<void> _recoverRuntime() {
    final current = _recovering;
    if (current != null) {
      return current;
    }
    final recovering = _host.runtimeNew().toDart.then((id) {
      _id = id.toDartInt;
    });
    _recovering = recovering.whenComplete(() {
      _recovering = null;
    });
    return _recovering!;
  }

  Future<String> _evaluateCurrentRuntime(
    String code, {
    Duration? timeout,
  }) async {
    return _mapWebEvalResult(
      (await _host
              .runtimeEval(_id.toJS, code.toJS, timeout?.inMilliseconds.toJS)
              .toDart)
          .toDart,
    );
  }
}

Object _mapWebError(Object error) {
  final message = '$error';
  final sentinelIndex = message.indexOf(_exceptionSentinel);
  if (sentinelIndex >= 0) {
    return JsException(
      message.substring(sentinelIndex + _exceptionSentinel.length),
    );
  }
  if (message.contains('QuickJS evaluation timed out')) {
    return const JsTimeoutException();
  }
  if (message.contains('QuickJS evaluation was cancelled')) {
    return JsCancelledException();
  }
  if (message.contains('QuickJS runtime is closed') ||
      message.contains('invalid runtime id')) {
    return JsRuntimeClosedException();
  }
  return StateError(message);
}

String _mapWebEvalResult(String result) {
  if (result.startsWith(_exceptionSentinel)) {
    throw JsException(result.substring(_exceptionSentinel.length));
  }
  return result;
}
