import 'dart:js_interop';

import '../quickjs_backend.dart';
import '../quickjs_exception.dart';
import '../quickjs_runtime_base.dart';
import '../quickjs_runtime_options.dart';
import 'quickjs_web_loader.dart';

const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';

/// Flutter Web 使用的 QuickJS WASM backend。
///
/// Dart 侧只通过 `quickjsNgWeb` 全局对象发消息，实际 QuickJS 执行在 Web Worker 中。
class WebQuickjsBackend implements QuickjsBackend {
  WebQuickjsBackend._(this._host, this._quickjsVersion);

  final QuickjsWebHost _host;
  final String _quickjsVersion;

  static WebQuickjsBackend? _instance;

  /// 初始化 web host，并缓存 backend。
  ///
  /// WASM module 和 worker script 是包资源，必须转换成 Flutter Web 的 package asset URL。
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
  Future<QuickjsJsRuntimeBase> createRuntime(
    QuickjsRuntimeOptions options,
  ) async {
    final id = (await _host.runtimeNew(options.memoryLimitBytes?.toJS).toDart)
        .toDartInt;
    return WebQuickjsJsRuntime(_host, id, options);
  }
}

final class WebQuickjsJsRuntime implements QuickjsJsRuntimeBase {
  WebQuickjsJsRuntime(this._host, this._id, this._options);

  final QuickjsWebHost _host;
  final QuickjsRuntimeOptions _options;
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
        // 同步 WASM 无法真正 interrupt 时，JS 层会 terminate worker；这里重建 runtime。
        await _recoverRuntime();
      } else if (mapped is JsRuntimeClosedException) {
        // worker 重启后旧 runtime id 会失效，重建 id 后重试一次当前 eval。
        await _recoverRuntime();
        return _evaluateCurrentRuntime(code, timeout: timeout);
      }
      throw mapped;
    }
  }

  @override
  Future<String> evaluateAsync(String code, {Duration? timeout}) {
    throw UnsupportedError(
      'Promise-based callback bridge is not implemented for Web yet',
    );
  }

  @override
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) {
    throw UnsupportedError(
      'Promise-based callback bridge is not implemented for Web yet',
    );
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
    // 并发恢复只允许一个 runtimeNew 在路上，避免多个新 id 互相覆盖。
    final recovering = _host
        .runtimeNew(_options.memoryLimitBytes?.toJS)
        .toDart
        .then((id) {
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
    final exception = parseJsExceptionPayload(
      message.substring(sentinelIndex + _exceptionSentinel.length),
    );
    if (exception.message.toLowerCase().contains('out of memory')) {
      return JsOutOfMemoryException(exception.message);
    }
    if (_isStackOverflowMessage(exception.message)) {
      return JsStackOverflowException(exception.message);
    }
    return exception;
  }
  if (message.contains('QuickJS evaluation timed out')) {
    return const JsTimeoutException();
  }
  if (message.toLowerCase().contains('out of memory')) {
    return const JsOutOfMemoryException();
  }
  if (_isStackOverflowMessage(message)) {
    return const JsStackOverflowException();
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
  // web bridge 与 native bridge 使用同一个 JS exception sentinel。
  if (result.startsWith(_exceptionSentinel)) {
    final exception = parseJsExceptionPayload(
      result.substring(_exceptionSentinel.length),
    );
    if (exception.message.toLowerCase().contains('out of memory')) {
      throw JsOutOfMemoryException(exception.message);
    }
    if (_isStackOverflowMessage(exception.message)) {
      throw JsStackOverflowException(exception.message);
    }
    throw exception;
  }
  return result;
}

bool _isStackOverflowMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('stack overflow') ||
      lower.contains('maximum call stack size exceeded');
}
