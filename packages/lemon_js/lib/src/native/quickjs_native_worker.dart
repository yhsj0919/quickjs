import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'quickjs_bindings.dart';
import '../bridge/quickjs_callback_codec.dart';
import '../diagnostics/quickjs_exception.dart';
import '../runtime/quickjs_runtime_base.dart';
import '../runtime/quickjs_runtime_options.dart';
import '../bridge/quickjs_stream_bridge.dart';

const String _messageTypeKey = 'type';
const String _messageIdKey = 'id';
const String _messageContextIdKey = 'contextId';
const String _messageCodeKey = 'code';
const String _messageSourceNameKey = 'sourceName';
const String _messageModuleNameKey = 'moduleName';
const String _messageModulesKey = 'modules';
const String _messageTimeoutMsKey = 'timeoutMs';
const String _messageMemoryLimitBytesKey = 'memoryLimitBytes';
const String _messageStackLimitBytesKey = 'stackLimitBytes';
const String _messageCallbackIdKey = 'callbackId';
const String _messageCallbackNameKey = 'name';
const String _messageCallbackRequestIdKey = 'callbackRequestId';
const String _messageArgsJsonKey = 'argsJson';
const String _messageSuccessKey = 'success';
const String _messagePayloadJsonKey = 'payloadJson';
const String _messageStreamIdKey = 'streamId';
const String _messagePullRequestIdKey = 'pullRequestId';
const String _messageSinkIdKey = 'sinkId';
const String _messageSinkActionKey = 'action';
const String _messageActionRequestIdKey = 'actionRequestId';
const String _timeoutErrorMessage = 'QuickJS evaluation timed out';
const String _timeoutSentinel = '\u001eQuickJS_TIMEOUT';
const String _cancelledErrorMessage = 'QuickJS evaluation was cancelled';
const String _cancelledSentinel = '\u001eQuickJS_CANCELLED';
const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';
const String _pendingSentinel = '\u001eQuickJS_PENDING';

const String _readyMessage = 'ready';
const String _evalMessage = 'eval';
const String _createContextMessage = 'createContext';
const String _disposeContextMessage = 'disposeContext';
const String _evalContextMessage = 'evalContext';
const String _evalContextAsyncMessage = 'evalContextAsync';
const String _pumpContextTimersMessage = 'pumpContextTimers';
const String _pumpTimersMessage = 'pumpTimers';
const String _evalModuleContextMessage = 'evalModuleContext';
const String _evalModuleMessage = 'evalModule';
const String _evalAsyncMessage = 'evalAsync';
const String _bindCallbackMessage = 'bindCallback';
const String _bindContextCallbackMessage = 'bindContextCallback';
const String _callbackRequestMessage = 'callbackRequest';
const String _callbackResponseMessage = 'callbackResponse';
const String _streamPullRequestMessage = 'streamPullRequest';
const String _streamPullResponseMessage = 'streamPullResponse';
const String _streamCancelRequestMessage = 'streamCancelRequest';
const String _bindSinkMessage = 'bindSink';
const String _bindContextSinkMessage = 'bindContextSink';
const String _sinkActionRequestMessage = 'sinkActionRequest';
const String _sinkActionResponseMessage = 'sinkActionResponse';
const String _disposeMessage = 'dispose';
const String _debugCrashMessage = 'debugCrash';
const String _errorMessage = 'error';
const String _responseMessage = 'response';

typedef _WorkerReady = ({SendPort sendPort, String quickjsVersion});
typedef _QuickjsCallback = Future<Object?> Function(List<Object?> args);

SendPort? _nativeHostCallbackSendPort;
int _nativeNextHostCallbackRequestId = 1;

int _nativeHostCallback(int callbackId, Pointer<Utf8> argsJson) {
  final sendPort = _nativeHostCallbackSendPort;
  if (sendPort == null) {
    return -1;
  }
  final requestId = _nativeNextHostCallbackRequestId++;
  sendPort.send(<String, Object?>{
    _messageTypeKey: _callbackRequestMessage,
    _messageCallbackRequestIdKey: requestId,
    _messageCallbackIdKey: callbackId,
    _messageArgsJsonKey: argsJson.toDartString(),
  });
  return requestId;
}

int _nativeHostStreamPull(int streamId) {
  final sendPort = _nativeHostCallbackSendPort;
  if (sendPort == null) {
    return -1;
  }
  final requestId = _nativeNextHostCallbackRequestId++;
  sendPort.send(<String, Object?>{
    _messageTypeKey: _streamPullRequestMessage,
    _messagePullRequestIdKey: requestId,
    _messageStreamIdKey: streamId,
  });
  return requestId;
}

void _nativeHostStreamCancel(int streamId) {
  final sendPort = _nativeHostCallbackSendPort;
  sendPort?.send(<String, Object?>{
    _messageTypeKey: _streamCancelRequestMessage,
    _messageStreamIdKey: streamId,
  });
}

int _nativeHostSinkAction(
  int sinkId,
  Pointer<Utf8> action,
  Pointer<Utf8> payloadJson,
) {
  final sendPort = _nativeHostCallbackSendPort;
  if (sendPort == null) {
    return -1;
  }
  final requestId = _nativeNextHostCallbackRequestId++;
  sendPort.send(<String, Object?>{
    _messageTypeKey: _sinkActionRequestMessage,
    _messageActionRequestIdKey: requestId,
    _messageSinkIdKey: sinkId,
    _messageSinkActionKey: action.toDartString(),
    if (payloadJson != nullptr)
      _messagePayloadJsonKey: payloadJson.toDartString(),
  });
  return requestId;
}

final Pointer<NativeFunction<QuickjsHostCallbackNative>>
_nativeHostCallbackPointer = Pointer.fromFunction<QuickjsHostCallbackNative>(
  _nativeHostCallback,
  -1,
);

final Pointer<NativeFunction<QuickjsHostStreamPullNative>>
_nativeHostStreamPullPointer =
    Pointer.fromFunction<QuickjsHostStreamPullNative>(
      _nativeHostStreamPull,
      -1,
    );

final Pointer<NativeFunction<QuickjsHostStreamCancelNative>>
_nativeHostStreamCancelPointer =
    Pointer.fromFunction<QuickjsHostStreamCancelNative>(
      _nativeHostStreamCancel,
    );

final Pointer<NativeFunction<QuickjsHostSinkActionNative>>
_nativeHostSinkActionPointer =
    Pointer.fromFunction<QuickjsHostSinkActionNative>(
      _nativeHostSinkAction,
      -1,
    );

/// native 平台的 QuickJS runtime。
///
/// 这个对象运行在调用方 isolate 中，只持有 worker isolate 的端口和 pending Future。
/// 真正的 `QuickjsRuntime*` 指针只存在于 [_nativeQuickjsWorkerMain]。
final class NativeQuickjsWorkerRuntime
    implements
        QuickjsJsRuntimeBase,
        QuickjsMultiContextRuntimeBase,
        QuickjsTimerRuntimeBase {
  NativeQuickjsWorkerRuntime._(
    this._isolate,
    this._receivePort,
    this._errorPort,
    this._exitPort,
    this._sendPort,
    this._errorSubscription,
    this._exitSubscription,
    this._cancelFlag,
    this.quickjsVersion,
  );

  final Isolate _isolate;
  final ReceivePort _receivePort;
  final ReceivePort _errorPort;
  final ReceivePort _exitPort;
  final SendPort _sendPort;
  final StreamSubscription<dynamic> _errorSubscription;
  final StreamSubscription<dynamic> _exitSubscription;
  final Pointer<Int32> _cancelFlag;
  final String quickjsVersion;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, _QuickjsCallback> _callbacks = <int, _QuickjsCallback>{};
  final Map<int, Set<int>> _contextCallbackIds = <int, Set<int>>{};
  final Map<int, int> _callbackContextIds = <int, int>{};
  final Map<int, Set<int>> _contextStreamIds = <int, Set<int>>{};
  final Map<int, Set<int>> _contextSinkIds = <int, Set<int>>{};
  late final QuickjsDartStreamRegistry _streamRegistry =
      QuickjsDartStreamRegistry(
        (pullRequestId, payloadJson) {
          _sendPort.send(<String, Object?>{
            _messageTypeKey: _streamPullResponseMessage,
            _messagePullRequestIdKey: int.parse(pullRequestId),
            _messageSuccessKey: true,
            _messagePayloadJsonKey: payloadJson,
          });
        },
        (pullRequestId, message) {
          _sendPort.send(<String, Object?>{
            _messageTypeKey: _streamPullResponseMessage,
            _messagePullRequestIdKey: int.parse(pullRequestId),
            _messageSuccessKey: false,
            _messagePayloadJsonKey: message,
          });
        },
      );
  late final QuickjsJsSinkRegistry _sinkRegistry = QuickjsJsSinkRegistry(
    (actionRequestId) {
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _sinkActionResponseMessage,
        _messageActionRequestIdKey: int.parse(actionRequestId),
        _messageSuccessKey: true,
        _messagePayloadJsonKey: '',
      });
    },
    (actionRequestId, message) {
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _sinkActionResponseMessage,
        _messageActionRequestIdKey: int.parse(actionRequestId),
        _messageSuccessKey: false,
        _messagePayloadJsonKey: message,
      });
    },
  );
  StreamSubscription<dynamic>? _responseSubscription;
  int _nextRequestId = 1;
  bool _closed = false;
  bool _asyncRunning = false;
  bool _portsClosed = false;
  Future<void>? _disposeFuture;

  static Future<NativeQuickjsWorkerRuntime> create({
    QuickjsRuntimeOptions options = const QuickjsRuntimeOptions(),
  }) async {
    final readyPort = ReceivePort();
    final responsePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
    // cancelFlag 是跨 isolate 共享给 C interrupt handler 的最小取消信号。
    final cancelFlag = calloc<Int32>();
    final ready = Completer<_WorkerReady>();

    late final StreamSubscription<dynamic> readySubscription;
    late final StreamSubscription<dynamic> errorSubscription;
    late final StreamSubscription<dynamic> exitSubscription;
    late final Isolate isolate;
    NativeQuickjsWorkerRuntime? runtime;

    void failCreate(Object error, [StackTrace? stackTrace]) {
      if (!ready.isCompleted) {
        ready.completeError(error, stackTrace);
      }
    }

    readySubscription = readyPort.listen((dynamic message) {
      if (message case {
        _messageTypeKey: _readyMessage,
        'sendPort': final SendPort sendPort,
        'quickjsVersion': final String quickjsVersion,
      }) {
        if (!ready.isCompleted) {
          ready.complete((sendPort: sendPort, quickjsVersion: quickjsVersion));
        }
        return;
      }
      if (message case {_messageTypeKey: _errorMessage, 'error': final error}) {
        failCreate(StateError('$error'));
      }
    });

    errorSubscription = errorPort.listen((dynamic message) {
      // isolate 初始化完成前的错误要失败 create；初始化后则失败所有 pending 请求。
      final error = JsRuntimeCrashException('QuickJS worker failed: $message');
      final currentRuntime = runtime;
      if (currentRuntime == null) {
        failCreate(error);
      } else {
        currentRuntime._handleWorkerFailure(error);
      }
    });

    exitSubscription = exitPort.listen((dynamic _) {
      final currentRuntime = runtime;
      if (currentRuntime == null) {
        failCreate(
          const JsRuntimeCrashException(
            'QuickJS worker exited before it was ready',
          ),
        );
      } else {
        currentRuntime._handleWorkerFailure(
          const JsRuntimeCrashException('QuickJS worker exited'),
        );
      }
    });

    try {
      // worker isolate 持有 DynamicLibrary 和 QuickJS runtime，避免 UI isolate 直接进 FFI。
      isolate = await Isolate.spawn(
        _nativeQuickjsWorkerMain,
        <String, Object>{
          'readyPort': readyPort.sendPort,
          'responsePort': responsePort.sendPort,
          'cancelFlagAddress': cancelFlag.address,
          if (options.memoryLimitBytes != null)
            _messageMemoryLimitBytesKey: options.memoryLimitBytes!,
          if (options.stackLimitBytes != null)
            _messageStackLimitBytesKey: options.stackLimitBytes!,
        },
        errorsAreFatal: true,
        onError: errorPort.sendPort,
        onExit: exitPort.sendPort,
      );
      final workerReady = await ready.future;
      await readySubscription.cancel();
      readyPort.close();

      runtime = NativeQuickjsWorkerRuntime._(
        isolate,
        responsePort,
        errorPort,
        exitPort,
        workerReady.sendPort,
        errorSubscription,
        exitSubscription,
        cancelFlag,
        workerReady.quickjsVersion,
      );
      runtime._listenResponses();
      return runtime;
    } catch (error) {
      await readySubscription.cancel();
      await errorSubscription.cancel();
      await exitSubscription.cancel();
      readyPort.close();
      responsePort.close();
      errorPort.close();
      exitPort.close();
      if (ready.isCompleted) {
        isolate.kill(priority: Isolate.immediate);
      }
      calloc.free(cancelFlag);
      rethrow;
    }
  }

  /// Creates an additional native JSContext in this worker's shared JSRuntime.
  @override
  Future<int> createContext() {
    return _sendRequest<int>(_createContextMessage, const <String, Object?>{});
  }

  /// Evaluates code in an additional context without affecting its siblings.
  @override
  Future<String> evaluateContext(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<context-eval>',
  }) {
    return _sendRequest<String>(_evalContextMessage, <String, Object?>{
      _messageContextIdKey: contextId,
      _messageCodeKey: code,
      _messageSourceNameKey: name,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
  }

  @override
  Future<String> evaluateContextAsync(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<context-evalAsync>',
  }) {
    return _sendRequest<String>(_evalContextAsyncMessage, <String, Object?>{
      _messageContextIdKey: contextId,
      _messageCodeKey: code,
      _messageSourceNameKey: name,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
  }

  @override
  Future<int?> pumpContextTimers(int contextId) {
    return _sendRequest<int?>(_pumpContextTimersMessage, <String, Object?>{
      _messageContextIdKey: contextId,
    });
  }

  @override
  Future<int?> pumpTimers() {
    return _sendRequest<int?>(_pumpTimersMessage, const <String, Object?>{});
  }

  @override
  Future<void> disposeContext(int contextId) {
    final callbackIds = _contextCallbackIds.remove(contextId);
    if (callbackIds != null) {
      for (final callbackId in callbackIds) {
        _callbacks.remove(callbackId);
        _callbackContextIds.remove(callbackId);
      }
    }
    for (final streamId
        in _contextStreamIds.remove(contextId) ?? const <int>{}) {
      _streamRegistry.disposeStream(streamId);
    }
    for (final sinkId in _contextSinkIds.remove(contextId) ?? const <int>{}) {
      _sinkRegistry.disposeSink(sinkId);
    }
    return _sendRequest<void>(_disposeContextMessage, <String, Object?>{
      _messageContextIdKey: contextId,
    });
  }

  @override
  Future<void> bindContextCallback(
    int contextId,
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) async {
    if (_closed) throw JsRuntimeClosedException();
    _callbacks[callbackId] = callback;
    _callbackContextIds[callbackId] = contextId;
    _contextCallbackIds.putIfAbsent(contextId, () => <int>{}).add(callbackId);
    try {
      await _sendRequest<void>(_bindContextCallbackMessage, <String, Object?>{
        _messageContextIdKey: contextId,
        _messageCallbackIdKey: callbackId,
        _messageCallbackNameKey: name,
      });
    } catch (_) {
      _callbacks.remove(callbackId);
      _callbackContextIds.remove(callbackId);
      _contextCallbackIds[contextId]?.remove(callbackId);
      rethrow;
    }
  }

  @override
  Future<void> unbindContextCallback(int contextId, int callbackId) async {
    _callbacks.remove(callbackId);
    _callbackContextIds.remove(callbackId);
    _contextCallbackIds[contextId]?.remove(callbackId);
  }

  @override
  Future<Stream<Object?>> bindContextJsSink(int contextId, String name) async {
    if (_closed) throw JsRuntimeClosedException();
    final created = _sinkRegistry.createSink();
    _contextSinkIds.putIfAbsent(contextId, () => <int>{}).add(created.sinkId);
    try {
      await _sendRequest<void>(_bindContextSinkMessage, <String, Object?>{
        _messageContextIdKey: contextId,
        _messageSinkIdKey: created.sinkId,
        _messageCallbackNameKey: name,
      });
      return created.stream;
    } catch (_) {
      _contextSinkIds[contextId]?.remove(created.sinkId);
      _sinkRegistry.disposeSink(created.sinkId);
      rethrow;
    }
  }

  /// Evaluates an ES module with a source table owned only by this context.
  @override
  Future<String> evaluateModuleContext(
    int contextId,
    String source, {
    required String name,
    Map<String, String> modules = const {},
  }) {
    return _sendRequest<String>(_evalModuleContextMessage, <String, Object?>{
      _messageContextIdKey: contextId,
      _messageCodeKey: source,
      _messageModuleNameKey: name,
      _messageModulesKey: _encodeModuleTable(modules),
    });
  }

  @override
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    // 每次 eval 开始前清空取消标记，避免上一次 stop 影响后续任务。
    _cancelFlag.value = 0;
    final result = await _sendRequest<String>(_evalMessage, <String, Object?>{
      _messageCodeKey: code,
      _messageSourceNameKey: name,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
    return result;
  }

  @override
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    String name = '<evalAsync>',
  }) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    _cancelFlag.value = 0;
    _asyncRunning = true;
    try {
      final result =
          await _sendRequest<String>(_evalAsyncMessage, <String, Object?>{
            _messageCodeKey: code,
            _messageSourceNameKey: name,
            if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
          });
      return result;
    } finally {
      _asyncRunning = false;
    }
  }

  @override
  Future<String> evaluateModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  }) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    _cancelFlag.value = 0;
    final result =
        await _sendRequest<String>(_evalModuleMessage, <String, Object?>{
          _messageCodeKey: source,
          _messageModuleNameKey: name,
          _messageModulesKey: _encodeModuleTable(modules),
          if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
        });
    return result;
  }

  @override
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    _callbacks[callbackId] = callback;
    await _sendRequest<void>(_bindCallbackMessage, <String, Object?>{
      _messageCallbackIdKey: callbackId,
      _messageCallbackNameKey: name,
    });
  }

  @override
  Future<void> unbindCallback(int callbackId) async {
    _callbacks.remove(callbackId);
  }

  @override
  Future<Stream<Object?>> bindJsSink(String name) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    final created = _sinkRegistry.createSink();
    await _sendRequest<void>(_bindSinkMessage, <String, Object?>{
      _messageSinkIdKey: created.sinkId,
      _messageCallbackNameKey: name,
    });
    return created.stream;
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    if (_closed) {
      _disposeFuture = _closePorts();
      return _disposeFuture!;
    }
    if (_asyncRunning) {
      _closed = true;
      _cancelFlag.value = 1;
      _streamRegistry.dispose();
      _sinkRegistry.dispose();
      _failAll(JsCancelledException());
      _disposeFuture = _closePorts();
      return _disposeFuture!;
    }
    _closed = true;
    _streamRegistry.dispose();
    _sinkRegistry.dispose();
    // dispose 作为普通 worker 命令发送，让 worker 自己释放 QuickJS runtime。
    _disposeFuture = _sendRequest<void>(
      _disposeMessage,
    ).whenComplete(_closePorts);
    return _disposeFuture!;
  }

  @override
  Future<void> stop() async {
    if (_closed) {
      return;
    }
    if (_asyncRunning) {
      _closed = true;
      _cancelFlag.value = 1;
      _streamRegistry.dispose();
      _sinkRegistry.dispose();
      _failAll(JsCancelledException());
      await _closePorts();
      return;
    }
    // C interrupt handler 会读取这个标记并中断正在执行的 JS。
    _cancelFlag.value = 1;
    final pending = _pending.values.map((completer) => completer.future);
    await Future.wait<void>([
      for (final future in pending) future.then<void>((_) {}, onError: (_) {}),
    ]);
    _closed = true;
    _streamRegistry.dispose();
    _sinkRegistry.dispose();
    await _closePorts();
  }

  /// 仅供测试使用：让 worker isolate 抛出未捕获错误，模拟 worker crash。
  Future<void> debugCrashForTest() async {
    if (_closed) {
      return;
    }
    await _sendRequest<void>(_debugCrashMessage);
  }

  Future<T> _sendRequest<T>(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    // 所有 worker 命令都带 requestId，响应回来后用它完成对应 Future。
    _sendPort.send(<String, Object?>{
      _messageTypeKey: type,
      _messageIdKey: requestId,
      ...payload,
    });
    return completer.future.then((value) => value as T);
  }

  void _listenResponses() {
    _responseSubscription = _receivePort.listen(_handleWorkerMessage);
  }

  void _handleWorkerFailure(Object error) {
    _closed = true;
    _failAll(error);
    unawaited(_closePorts());
  }

  void _handleWorkerMessage(dynamic message) {
    if (message case {
      _messageTypeKey: _responseMessage,
      _messageIdKey: final int requestId,
      'ok': final bool ok,
    }) {
      final completer = _pending.remove(requestId);
      if (completer == null) {
        return;
      }
      if (ok) {
        completer.complete(message['result']);
      } else {
        final error = '${message['error']}';
        // C bridge 和 web bridge 都通过 sentinel / 文本协议把错误还原为 Dart 异常。
        if (error == _timeoutErrorMessage) {
          completer.completeError(JsTimeoutException());
        } else if (error.contains(_cancelledErrorMessage)) {
          completer.completeError(JsCancelledException());
        } else if (error.contains('QuickJS runtime is closed')) {
          completer.completeError(JsRuntimeClosedException());
        } else if (_isStackOverflowMessage(error)) {
          completer.completeError(JsStackOverflowException(error));
        } else if (error.contains(_exceptionSentinel)) {
          final sentinelIndex = error.indexOf(_exceptionSentinel);
          final exception = parseJsExceptionPayload(
            error.substring(sentinelIndex + _exceptionSentinel.length),
          );
          if (exception.message.toLowerCase().contains('out of memory')) {
            completer.completeError(JsOutOfMemoryException(exception.message));
          } else if (_isStackOverflowMessage(exception.message)) {
            completer.completeError(
              JsStackOverflowException(exception.message),
            );
          } else {
            completer.completeError(exception);
          }
        } else {
          completer.completeError(StateError(error));
        }
      }
      return;
    }
    if (message case {
      _messageTypeKey: _callbackRequestMessage,
      _messageCallbackRequestIdKey: final int callbackRequestId,
      _messageCallbackIdKey: final int callbackId,
      _messageArgsJsonKey: final String argsJson,
    }) {
      unawaited(
        _handleCallbackRequest(callbackRequestId, callbackId, argsJson),
      );
      return;
    }
    if (message case {
      _messageTypeKey: _streamPullRequestMessage,
      _messagePullRequestIdKey: final int pullRequestId,
      _messageStreamIdKey: final int streamId,
    }) {
      _streamRegistry.handlePull('$pullRequestId', streamId);
      return;
    }
    if (message case {
      _messageTypeKey: _streamCancelRequestMessage,
      _messageStreamIdKey: final int streamId,
    }) {
      _streamRegistry.handleCancel(streamId);
      return;
    }
    if (message case {
      _messageTypeKey: _sinkActionRequestMessage,
      _messageActionRequestIdKey: final int actionRequestId,
      _messageSinkIdKey: final int sinkId,
      _messageSinkActionKey: final String action,
    }) {
      _sinkRegistry.handleAction(
        '$actionRequestId',
        sinkId,
        action,
        message[_messagePayloadJsonKey] as String?,
      );
    }
  }

  Future<void> _handleCallbackRequest(
    int callbackRequestId,
    int callbackId,
    String argsJson,
  ) async {
    final callback = _callbacks[callbackId];
    if (callback == null) {
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: false,
        _messagePayloadJsonKey: 'QuickJS callback $callbackId is not bound',
      });
      return;
    }

    try {
      final decoded = jsonDecode(argsJson);
      final args = decoded is List
          ? [for (final item in decoded) decodeCallbackWireValue(item)]
          : <Object?>[];
      final result = await callback(args);
      final encodedResult = result is Stream
          ? _encodeContextStream(callbackId, result.cast<Object?>())
          : _streamRegistry.encodeCallbackResult(result);
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: true,
        _messagePayloadJsonKey: jsonEncode(encodedResult),
      });
    } catch (error) {
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: false,
        _messagePayloadJsonKey: '$error',
      });
    }
  }

  Object _encodeContextStream(int callbackId, Stream<Object?> stream) {
    final streamId = _streamRegistry.register(stream);
    final contextId = _callbackContextIds[callbackId];
    if (contextId != null) {
      _contextStreamIds.putIfAbsent(contextId, () => <int>{}).add(streamId);
    }
    return encodeDartStreamWire(streamId);
  }

  void _failAll(Object error) {
    _streamRegistry.dispose();
    _sinkRegistry.dispose();
    for (final completer in _pending.values) {
      if (!completer.isCompleted) {
        completer.completeError(error);
      }
    }
    _pending.clear();
  }

  Future<void> _closePorts() async {
    if (_portsClosed) {
      return;
    }
    _portsClosed = true;
    // 端口和 cancelFlag 只释放一次，避免 stop/dispose/crash 并发收尾时 double free。
    _isolate.kill(priority: Isolate.immediate);
    await _responseSubscription?.cancel();
    await _errorSubscription.cancel();
    await _exitSubscription.cancel();
    _receivePort.close();
    _errorPort.close();
    _exitPort.close();
    calloc.free(_cancelFlag);
  }
}

/// worker isolate 入口。
///
/// 这里创建并持有 QuickJS runtime，监听主 isolate 发来的 eval / dispose 命令。
void _nativeQuickjsWorkerMain(Map<String, Object> ports) {
  final readySendPort = ports['readyPort']! as SendPort;
  final responseSendPort = ports['responsePort']! as SendPort;
  final cancelFlag = Pointer<Int32>.fromAddress(
    ports['cancelFlagAddress']! as int,
  );
  final memoryLimitBytes = ports[_messageMemoryLimitBytesKey] as int?;
  final stackLimitBytes = ports[_messageStackLimitBytesKey] as int?;
  final commandPort = ReceivePort();

  late final QuickjsBindings bindings;
  Pointer<QuickjsRuntime> runtime = nullptr;
  final contexts = <int, Pointer<QuickjsContext>>{};
  var nextContextId = 1;
  var closed = false;

  try {
    bindings = QuickjsBindings(QuickjsBindings.open());
    final quickjsVersion = bindings.version().toDartString();
    runtime = bindings.runtimeNew();
    if (runtime == nullptr) {
      throw StateError('Failed to create QuickJS runtime');
    }
    if (memoryLimitBytes != null) {
      bindings.runtimeSetMemoryLimit(runtime, memoryLimitBytes);
    }
    if (stackLimitBytes != null) {
      bindings.runtimeSetStackLimit(runtime, stackLimitBytes);
    }
    bindings.runtimeSetCancelFlag(runtime, cancelFlag);
    bindings.runtimeSetStreamHandlers(
      runtime,
      _nativeHostStreamPullPointer,
      _nativeHostStreamCancelPointer,
      _nativeHostSinkActionPointer,
    );
    _nativeHostCallbackSendPort = responseSendPort;
    readySendPort.send(<String, Object?>{
      _messageTypeKey: _readyMessage,
      'sendPort': commandPort.sendPort,
      'quickjsVersion': quickjsVersion,
    });
  } catch (error) {
    readySendPort.send(<String, Object?>{
      _messageTypeKey: _errorMessage,
      'error': '$error',
    });
    commandPort.close();
    return;
  }

  commandPort.listen((dynamic message) async {
    if (message case {
      _messageTypeKey: _callbackResponseMessage,
      _messageCallbackRequestIdKey: final int callbackRequestId,
      _messageSuccessKey: final bool success,
      _messagePayloadJsonKey: final String payloadJson,
    }) {
      _resolveCallback(
        bindings,
        runtime,
        callbackRequestId,
        success,
        payloadJson,
      );
      return;
    }
    if (message case {
      _messageTypeKey: _streamPullResponseMessage,
      _messagePullRequestIdKey: final int pullRequestId,
      _messageSuccessKey: final bool success,
      _messagePayloadJsonKey: final String payloadJson,
    }) {
      _resolveStreamPull(
        bindings,
        runtime,
        pullRequestId,
        success,
        payloadJson,
      );
      return;
    }
    if (message case {
      _messageTypeKey: _sinkActionResponseMessage,
      _messageActionRequestIdKey: final int actionRequestId,
      _messageSuccessKey: final bool success,
      _messagePayloadJsonKey: final String payloadJson,
    }) {
      _resolveSinkAction(
        bindings,
        runtime,
        actionRequestId,
        success,
        payloadJson,
      );
      return;
    }

    if (message case {
      _messageTypeKey: final String type,
      _messageIdKey: final int requestId,
    }) {
      if (type == _debugCrashMessage) {
        throw StateError('QuickJS worker debug crash');
      }
      try {
        if (closed) {
          throw StateError('QuickJS runtime is closed');
        }
        switch (type) {
          case _createContextMessage:
            final context = bindings.contextNew(runtime);
            if (context == nullptr) {
              throw StateError('Failed to create QuickJS context');
            }
            final contextId = nextContextId++;
            contexts[contextId] = context;
            _sendOk(responseSendPort, requestId, contextId);
          case _disposeContextMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts.remove(contextId);
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            bindings.contextFree(context);
            _sendOk(responseSendPort, requestId, null);
          case _evalContextMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            final code = message[_messageCodeKey] as String;
            final name =
                message[_messageSourceNameKey] as String? ?? '<context-eval>';
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = _evalContext(
              bindings,
              context,
              code,
              name,
              timeoutMs,
            );
            _sendOk(responseSendPort, requestId, result);
          case _evalContextAsyncMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            final result = await _evalContextAsync(
              bindings,
              context,
              message[_messageCodeKey] as String,
              message[_messageSourceNameKey] as String? ??
                  '<context-evalAsync>',
              message[_messageTimeoutMsKey] as int?,
              cancelFlag,
            );
            _sendOk(responseSendPort, requestId, result);
          case _evalModuleContextMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            final result = _evalModuleContext(
              bindings,
              context,
              message[_messageCodeKey] as String,
              message[_messageModuleNameKey] as String,
              message[_messageModulesKey] as String? ?? '',
            );
            _sendOk(responseSendPort, requestId, result);
          case _pumpContextTimersMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            final delay = bindings.contextPumpTimers(context);
            if (delay < -1) {
              throw StateError('QuickJS timer pending job failed');
            }
            _sendOk(responseSendPort, requestId, delay < 0 ? null : delay);
          case _pumpTimersMessage:
            final delay = bindings.runtimePumpTimers(runtime);
            if (delay < -1) {
              throw StateError('QuickJS timer pending job failed');
            }
            _sendOk(responseSendPort, requestId, delay < 0 ? null : delay);
          case _evalMessage:
            final code = message[_messageCodeKey] as String;
            final name = message[_messageSourceNameKey] as String? ?? '<eval>';
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = _eval(bindings, runtime, code, name, timeoutMs);
            _sendOk(responseSendPort, requestId, result);
          case _evalModuleMessage:
            final source = message[_messageCodeKey] as String;
            final name = message[_messageModuleNameKey] as String;
            final modules = message[_messageModulesKey] as String? ?? '';
            final result = _evalModule(
              bindings,
              runtime,
              source,
              name,
              modules,
            );
            _sendOk(responseSendPort, requestId, result);
          case _evalAsyncMessage:
            final code = message[_messageCodeKey] as String;
            final name =
                message[_messageSourceNameKey] as String? ?? '<evalAsync>';
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = await _evalAsync(
              bindings,
              runtime,
              code,
              name,
              timeoutMs,
              cancelFlag,
            );
            _sendOk(responseSendPort, requestId, result);
          case _bindCallbackMessage:
            final callbackId = message[_messageCallbackIdKey] as int;
            final name = message[_messageCallbackNameKey] as String;
            _bindCallback(bindings, runtime, callbackId, name);
            _sendOk(responseSendPort, requestId, null);
          case _bindContextCallbackMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            _bindContextCallback(
              bindings,
              context,
              message[_messageCallbackIdKey] as int,
              message[_messageCallbackNameKey] as String,
            );
            _sendOk(responseSendPort, requestId, null);
          case _bindSinkMessage:
            final sinkId = message[_messageSinkIdKey] as int;
            final name = message[_messageCallbackNameKey] as String;
            _bindSink(bindings, runtime, sinkId, name);
            _sendOk(responseSendPort, requestId, null);
          case _bindContextSinkMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            _bindContextSink(
              bindings,
              context,
              message[_messageSinkIdKey] as int,
              message[_messageCallbackNameKey] as String,
            );
            _sendOk(responseSendPort, requestId, null);
          case _disposeMessage:
            // runtime 必须在持有它的 worker isolate 中释放。
            closed = true;
            contexts.clear();
            bindings.runtimeFree(runtime);
            _nativeHostCallbackSendPort = null;
            runtime = nullptr;
            _sendOk(responseSendPort, requestId, null);
            commandPort.close();
          default:
            throw StateError('Unknown QuickJS worker command: $type');
        }
      } catch (error) {
        _sendError(responseSendPort, requestId, error);
      }
    }
  });
}

void _bindSink(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  int sinkId,
  String name,
) {
  final namePtr = name.toNativeUtf8();
  try {
    final result = bindings.runtimeBindSink(runtime, sinkId, namePtr);
    if (result < 0) {
      throw StateError('QuickJS sink binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _bindContextSink(
  QuickjsBindings bindings,
  Pointer<QuickjsContext> context,
  int sinkId,
  String name,
) {
  final namePtr = name.toNativeUtf8();
  try {
    if (bindings.contextBindSink(context, sinkId, namePtr) < 0) {
      throw StateError('QuickJS context sink binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _bindCallback(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  int callbackId,
  String name,
) {
  final namePtr = name.toNativeUtf8();
  try {
    final result = bindings.runtimeBindCallback(
      runtime,
      callbackId,
      namePtr,
      _nativeHostCallbackPointer,
    );
    if (result < 0) {
      throw StateError('QuickJS callback binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _bindContextCallback(
  QuickjsBindings bindings,
  Pointer<QuickjsContext> context,
  int callbackId,
  String name,
) {
  final namePtr = name.toNativeUtf8();
  try {
    final result = bindings.contextBindCallback(
      context,
      callbackId,
      namePtr,
      _nativeHostCallbackPointer,
    );
    if (result < 0) {
      throw StateError('QuickJS context callback binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _resolveCallback(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  int callbackRequestId,
  bool success,
  String payloadJson,
) {
  final payloadPtr = payloadJson.toNativeUtf8();
  try {
    final result = bindings.runtimeResolveCallback(
      runtime,
      callbackRequestId,
      success ? 1 : 0,
      payloadPtr,
    );
    if (result < 0) {
      // The owning context may have been disposed while Dart work was in
      // flight. Its pending Promise is already released, so a late response is
      // intentionally dropped instead of crashing the shared runtime worker.
      return;
    }
  } finally {
    calloc.free(payloadPtr);
  }
}

void _resolveStreamPull(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  int pullRequestId,
  bool success,
  String payloadJson,
) {
  final payloadPtr = payloadJson.toNativeUtf8();
  try {
    final result = bindings.runtimeResolveStreamPull(
      runtime,
      pullRequestId,
      success ? 1 : 0,
      payloadPtr,
    );
    if (result < 0) {
      // A disposed context no longer owns a Promise to receive this response.
      return;
    }
  } finally {
    calloc.free(payloadPtr);
  }
}

void _resolveSinkAction(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  int actionRequestId,
  bool success,
  String message,
) {
  final messagePtr = message.toNativeUtf8();
  try {
    final result = bindings.runtimeResolveSinkAction(
      runtime,
      actionRequestId,
      success ? 1 : 0,
      messagePtr,
    );
    if (result < 0) {
      // Sink actions may complete after their context has been disposed.
      return;
    }
  } finally {
    calloc.free(messagePtr);
  }
}

String _evalModule(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String source,
  String name,
  String modules,
) {
  final sourcePtr = source.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final modulesPtr = modules.toNativeUtf8();
  final resultPtr = bindings.evalModule(
    runtime,
    sourcePtr,
    namePtr,
    modulesPtr,
  );
  calloc.free(sourcePtr);
  calloc.free(namePtr);
  calloc.free(modulesPtr);
  return _takeResult(bindings, resultPtr);
}

String _evalModuleContext(
  QuickjsBindings bindings,
  Pointer<QuickjsContext> context,
  String source,
  String name,
  String modules,
) {
  final sourcePtr = source.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final modulesPtr = modules.toNativeUtf8();
  try {
    return _takeResult(
      bindings,
      bindings.contextEvalModule(context, sourcePtr, namePtr, modulesPtr),
    );
  } finally {
    calloc.free(sourcePtr);
    calloc.free(namePtr);
    calloc.free(modulesPtr);
  }
}

String _encodeModuleTable(Map<String, String> modules) {
  if (modules.isEmpty) {
    return '';
  }
  final buffer = StringBuffer();
  for (final entry in modules.entries) {
    buffer
      ..write(Uri.encodeComponent(entry.key))
      ..write('=')
      ..writeln(Uri.encodeComponent(entry.value));
  }
  return buffer.toString();
}

String _eval(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String code,
  String name,
  int? timeoutMs,
) {
  final codePtr = code.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final resultPtr = bindings.evalTimeoutNamed(
    runtime,
    codePtr,
    namePtr,
    timeoutMs ?? 0,
  );
  calloc.free(codePtr);
  calloc.free(namePtr);
  if (resultPtr == nullptr) {
    throw StateError('QuickJS eval returned null');
  }
  try {
    final result = resultPtr.toDartString();
    // C bridge 用不可见前缀区分普通字符串结果和特殊错误。
    if (result == _cancelledSentinel) {
      throw JsCancelledException();
    }
    if (result == _timeoutSentinel) {
      throw const JsTimeoutException();
    }
    if (result.startsWith(_exceptionSentinel)) {
      throw parseJsExceptionPayload(
        result.substring(_exceptionSentinel.length),
      );
    }
    return result;
  } finally {
    bindings.freeString(resultPtr);
  }
}

String _evalContext(
  QuickjsBindings bindings,
  Pointer<QuickjsContext> context,
  String code,
  String name,
  int? timeoutMs,
) {
  final codePtr = code.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final resultPtr = bindings.contextEvalTimeoutNamed(
    context,
    codePtr,
    namePtr,
    timeoutMs ?? 0,
  );
  calloc.free(codePtr);
  calloc.free(namePtr);
  return _takeResult(bindings, resultPtr);
}

Future<String> _evalAsync(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String code,
  String name,
  int? timeoutMs,
  Pointer<Int32> cancelFlag,
) async {
  final codePtr = code.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final stopwatch = Stopwatch()..start();
  Pointer<Utf8> resultPtr = bindings.evalAsyncStartNamed(
    runtime,
    codePtr,
    namePtr,
  );
  calloc.free(codePtr);
  calloc.free(namePtr);

  while (true) {
    if (cancelFlag.value != 0) {
      throw JsCancelledException();
    }
    final result = _takeResult(bindings, resultPtr);
    if (result != _pendingSentinel) {
      return result;
    }
    if (timeoutMs != null && stopwatch.elapsedMilliseconds >= timeoutMs) {
      throw const JsTimeoutException();
    }
    await Future<void>.delayed(Duration.zero);
    if (cancelFlag.value != 0) {
      throw JsCancelledException();
    }
    resultPtr = bindings.evalAsyncPoll(runtime);
  }
}

Future<String> _evalContextAsync(
  QuickjsBindings bindings,
  Pointer<QuickjsContext> context,
  String code,
  String name,
  int? timeoutMs,
  Pointer<Int32> cancelFlag,
) async {
  final codePtr = code.toNativeUtf8();
  final namePtr = name.toNativeUtf8();
  final stopwatch = Stopwatch()..start();
  Pointer<Utf8> resultPtr = bindings.contextEvalAsyncStartNamed(
    context,
    codePtr,
    namePtr,
  );
  calloc.free(codePtr);
  calloc.free(namePtr);

  while (true) {
    if (cancelFlag.value != 0) throw JsCancelledException();
    final result = _takeResult(bindings, resultPtr);
    if (result != _pendingSentinel) return result;
    if (timeoutMs != null && stopwatch.elapsedMilliseconds >= timeoutMs) {
      throw const JsTimeoutException();
    }
    await Future<void>.delayed(Duration.zero);
    resultPtr = bindings.contextEvalAsyncPoll(context);
  }
}

String _takeResult(QuickjsBindings bindings, Pointer<Utf8> resultPtr) {
  if (resultPtr == nullptr) {
    throw StateError('QuickJS eval returned null');
  }
  try {
    final result = resultPtr.toDartString();
    if (result == _cancelledSentinel) {
      throw JsCancelledException();
    }
    if (result == _timeoutSentinel) {
      throw const JsTimeoutException();
    }
    if (result.startsWith(_exceptionSentinel)) {
      throw parseJsExceptionPayload(
        result.substring(_exceptionSentinel.length),
      );
    }
    return result;
  } finally {
    bindings.freeString(resultPtr);
  }
}

void _sendOk(SendPort sendPort, int requestId, Object? result) {
  sendPort.send(<String, Object?>{
    _messageTypeKey: _responseMessage,
    _messageIdKey: requestId,
    'ok': true,
    'result': result,
  });
}

void _sendError(SendPort sendPort, int requestId, Object error) {
  // Dart 侧异常跨 isolate 发送时统一压成字符串，再由主 isolate 映射回异常类型。
  final message = switch (error) {
    JsException() => '$_exceptionSentinel${_encodeJsException(error)}',
    _ => '$error',
  };
  sendPort.send(<String, Object?>{
    _messageTypeKey: _responseMessage,
    _messageIdKey: requestId,
    'ok': false,
    'error': message,
  });
}

String _encodeJsException(JsException error) {
  return jsonEncode(<String, Object?>{
    'message': error.message,
    if (error.name != null) 'name': error.name,
    if (error.stack != null) 'stack': error.stack,
    if (error.fileName != null) 'fileName': error.fileName,
    if (error.line != null) 'line': error.line,
    if (error.column != null) 'column': error.column,
  });
}

bool _isStackOverflowMessage(String message) {
  final lower = message.toLowerCase();
  return lower.contains('stack overflow') ||
      lower.contains('maximum call stack size exceeded');
}
