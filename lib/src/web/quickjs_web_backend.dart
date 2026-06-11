import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import '../quickjs_backend.dart';
import '../quickjs_callback_codec.dart';
import '../quickjs_exception.dart';
import '../quickjs_runtime_base.dart';
import '../quickjs_runtime_options.dart';
import '../quickjs_stream_bridge.dart';
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
  WebQuickjsJsRuntime(this._host, this._id, this._options) {
    _registerStreamBridgeForCurrentId();
  }

  final QuickjsWebHost _host;
  final QuickjsRuntimeOptions _options;
  int _id;
  bool _closed = false;
  Future<void>? _recovering;
  int _nextSinkActionRequestId = 1;
  final Map<String, Completer<String>> _pendingStreamPulls =
      <String, Completer<String>>{};
  final Map<String, Completer<void>> _pendingSinkActions =
      <String, Completer<void>>{};
  late final QuickjsDartStreamRegistry _streamRegistry =
      QuickjsDartStreamRegistry(
        (pullRequestId, payloadJson) {
          _pendingStreamPulls.remove(pullRequestId)?.complete(payloadJson);
        },
        (pullRequestId, message) {
          _pendingStreamPulls.remove(pullRequestId)?.completeError(message);
        },
      );
  late final QuickjsJsSinkRegistry _sinkRegistry = QuickjsJsSinkRegistry(
    (actionRequestId) {
      _pendingSinkActions.remove(actionRequestId)?.complete();
    },
    (actionRequestId, message) {
      _pendingSinkActions.remove(actionRequestId)?.completeError(message);
    },
  );

  void _registerStreamBridgeForCurrentId() {
    _host.runtimeRegisterStreamBridge(
      _id.toJS,
      _handleStreamPull.toJS,
      _handleStreamCancel.toJS,
      _handleSinkAction.toJS,
    );
  }

  JSPromise<JSString> _handleStreamPull(
    JSString pullRequestId,
    JSNumber streamId,
  ) {
    final id = pullRequestId.toDart;
    final completer = Completer<String>();
    _pendingStreamPulls[id] = completer;
    _streamRegistry.handlePull(id, streamId.toDartInt);
    return completer.future.then((payloadJson) => payloadJson.toJS).toJS;
  }

  void _handleStreamCancel(JSNumber streamId) {
    _streamRegistry.handleCancel(streamId.toDartInt);
  }

  JSPromise<JSAny?> _handleSinkAction(
    JSNumber sinkId,
    JSString action,
    JSString? payloadJson,
  ) {
    final id = '$_id:${_nextSinkActionRequestId++}';
    final completer = Completer<void>();
    _pendingSinkActions[id] = completer;
    _sinkRegistry.handleAction(
      id,
      sinkId.toDartInt,
      action.toDart,
      payloadJson?.toDart,
    );
    return completer.future.then((_) => null).toJS;
  }

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
  Future<String> evaluateAsync(String code, {Duration? timeout}) async {
    _ensureOpen();
    try {
      return _mapWebEvalResult(
        (await _host
                .runtimeEvalAsync(
                  _id.toJS,
                  code.toJS,
                  timeout?.inMilliseconds.toJS,
                )
                .toDart)
            .toDart,
      );
    } catch (error) {
      throw _mapWebError(error);
    }
  }

  @override
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) async {
    _ensureOpen();
    JSPromise<JSString> callbackAdapter(JSString argsJson) {
      return (() async {
        final decoded = jsonDecode(argsJson.toDart);
        final args = decoded is List
            ? [for (final item in decoded) decodeCallbackWireValue(item)]
            : <Object?>[];
        final result = await callback(args);
        return jsonEncode(_streamRegistry.encodeCallbackResult(result)).toJS;
      })().toJS;
    }

    await _host
        .runtimeBindCallback(
          _id.toJS,
          callbackId.toJS,
          name.toJS,
          callbackAdapter.toJS,
        )
        .toDart;
  }

  @override
  Future<Stream<Object?>> bindJsSink(String name) async {
    _ensureOpen();
    final created = _sinkRegistry.createSink();
    await _host
        .runtimeBindSink(_id.toJS, created.sinkId.toJS, name.toJS)
        .toDart;
    return created.stream;
  }

  @override
  Future<void> dispose() async {
    if (_closed) {
      return;
    }
    _streamRegistry.dispose();
    _sinkRegistry.dispose();
    for (final completer in _pendingStreamPulls.values) {
      completer.completeError(JsRuntimeClosedException());
    }
    _pendingStreamPulls.clear();
    for (final completer in _pendingSinkActions.values) {
      completer.completeError(JsRuntimeClosedException());
    }
    _pendingSinkActions.clear();
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
          _registerStreamBridgeForCurrentId();
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
