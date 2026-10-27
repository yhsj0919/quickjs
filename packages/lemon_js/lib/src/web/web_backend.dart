import 'dart:async';
import 'dart:convert';
import 'dart:js_interop';

import '../backend/backend.dart';
import '../bridge/callback_codec.dart';
import '../diagnostics/exception.dart';
import '../runtime/runtime_base.dart';
import '../runtime/runtime_options.dart';
import '../bridge/stream_bridge.dart';
import 'web_loader.dart';

const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';

JSPromise<JSString> _callbackFutureToJsPromise(Future<JSString> future) {
  return JSPromise<JSString>(
    ((JSFunction resolve, JSFunction reject) {
      future.then(
        (value) => resolve.callAsFunction(resolve, value),
        onError: (Object error, StackTrace _) {
          reject.callAsFunction(reject, error.toString().toJS);
        },
      );
    }).toJS,
  );
}

/// Flutter Web 使用的 QuickJS WASM backend。
///
/// Dart 侧只通过 `quickjsNgWeb` 全局对象发消息，实际 QuickJS 执行在 Web Worker 中。
class WebJsBackend implements JsBackend {
  WebJsBackend._(this._host, this._engineVersion);

  final JsWebHost _host;
  final String _engineVersion;

  static WebJsBackend? _instance;

  /// 初始化 web host，并缓存 backend。
  ///
  /// WASM module 和 worker script 是包资源，必须转换成 Flutter Web 的 package asset URL。
  static Future<WebJsBackend> create({
    String? bridgeModuleUrl,
    String? wasmUrl,
  }) async {
    if (_instance != null) {
      return _instance!;
    }

    final host = await loadJsWebHost();
    final resolvedBridge =
        bridgeModuleUrl ?? packageAssetUrl('assets/web/quickjs_bridge.mjs');
    final resolvedWasm = wasmUrl ?? packageAssetUrl('assets/web/quickjs.wasm');
    final resolvedWorker = packageAssetUrl('assets/web/quickjs_web_worker.js');

    final engineVersion =
        (await host
                .ensureInitialized(
                  resolvedWasm.toJS,
                  resolvedBridge.toJS,
                  resolvedWorker.toJS,
                )
                .toDart)
            .toDart;
    _instance = WebJsBackend._(host, engineVersion);
    return _instance!;
  }

  @override
  String get engineVersion => _engineVersion;

  @override
  Future<JsJsRuntimeBase> createRuntime(JsOptions options) async {
    final id =
        (await _host
                .runtimeNew(
                  options.memoryLimitBytes?.toJS,
                  options.stackLimitBytes?.toJS,
                )
                .toDart)
            .toDartInt;
    return WebJsJsRuntime(_host, id);
  }
}

final class WebJsJsRuntime
    implements JsJsRuntimeBase, JsRecoverableRuntimeBase {
  WebJsJsRuntime(this._host, this._id) {
    _generation = _host.runtimeGeneration().toDartInt;
    _registerStreamBridgeForCurrentId();
  }

  final JsWebHost _host;
  final int _id;
  late final int _generation;

  @override
  bool get needsRebuild => _generation != _host.runtimeGeneration().toDartInt;
  bool _closed = false;
  int _nextSinkActionRequestId = 1;
  final Map<String, Completer<String>> _pendingStreamPulls =
      <String, Completer<String>>{};
  final Map<String, Completer<void>> _pendingSinkActions =
      <String, Completer<void>>{};
  late final JsDartStreamRegistry _streamRegistry = JsDartStreamRegistry(
    (pullRequestId, payloadJson) {
      _pendingStreamPulls.remove(pullRequestId)?.complete(payloadJson);
    },
    (pullRequestId, message) {
      _pendingStreamPulls.remove(pullRequestId)?.completeError(message);
    },
  );
  late final JsJsSinkRegistry _sinkRegistry = JsJsSinkRegistry(
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
    return _callbackFutureToJsPromise(
      completer.future.then((payloadJson) => payloadJson.toJS),
    );
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
    return _callbackFutureToJsPromise(completer.future.then((_) => ''.toJS));
  }

  @override
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) async {
    _ensureOpen();
    try {
      return await _evaluateCurrentRuntime(code, timeout: timeout, name: name);
    } catch (error) {
      throw _mapWebError(error);
    }
  }

  @override
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    String name = '<run>',
  }) async {
    _ensureOpen();
    try {
      return _mapWebEvalResult(
        (await _host
                .runtimeEvalAsync(
                  _id.toJS,
                  code.toJS,
                  name.toJS,
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
  Future<String> evaluateModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  }) async {
    _ensureOpen();
    try {
      return _mapWebEvalResult(
        (await _host
                .runtimeEvalModule(
                  _id.toJS,
                  source.toJS,
                  name.toJS,
                  jsonEncode(modules).toJS,
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
    FutureOr<Object?> Function(List<Object?> args) callback,
  ) async {
    _ensureOpen();
    JSPromise<JSString> callbackAdapter(JSString argsJson) {
      final future = () async {
        final decoded = jsonDecode(argsJson.toDart);
        final args = decoded is List
            ? [for (final item in decoded) decodeCallbackWireValue(item)]
            : <Object?>[];
        final result = await callback(args);
        return jsonEncode(_streamRegistry.encodeCallbackResult(result)).toJS;
      }();
      return _callbackFutureToJsPromise(future);
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
  Future<void> unbindCallback(int callbackId) async {
    if (_closed) {
      return;
    }
    await _host.runtimeUnbindCallback(_id.toJS, callbackId.toJS).toDart;
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
    if (!needsRebuild) {
      await _host.runtimeDispose(_id.toJS).toDart;
    }
    _closed = true;
  }

  @override
  Future<void> stop() async {
    _ensureOpen();
    await _host.runtimeStop().toDart;
  }

  void _ensureOpen() {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
  }

  Future<String> _evaluateCurrentRuntime(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) async {
    return _mapWebEvalResult(
      (await _host
              .runtimeEval(
                _id.toJS,
                code.toJS,
                name.toJS,
                timeout?.inMilliseconds.toJS,
              )
              .toDart)
          .toDart,
    );
  }
}

Object _mapWebError(Object error) {
  if (error is JsException) {
    return error;
  }
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
// ignore_for_file: public_member_api_docs
