import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../quickjs_bindings.dart';
import '../quickjs_exception.dart';
import '../quickjs_runtime_base.dart';
import '../quickjs_runtime_options.dart';

const String _messageTypeKey = 'type';
const String _messageIdKey = 'id';
const String _messageCodeKey = 'code';
const String _messageTimeoutMsKey = 'timeoutMs';
const String _messageMemoryLimitBytesKey = 'memoryLimitBytes';
const String _messageStackLimitBytesKey = 'stackLimitBytes';
const String _messageCallbackIdKey = 'callbackId';
const String _messageCallbackNameKey = 'name';
const String _messageCallbackRequestIdKey = 'callbackRequestId';
const String _messageArgsJsonKey = 'argsJson';
const String _messageSuccessKey = 'success';
const String _messagePayloadJsonKey = 'payloadJson';
const String _timeoutErrorMessage = 'QuickJS evaluation timed out';
const String _timeoutSentinel = '\u001eQuickJS_TIMEOUT';
const String _cancelledErrorMessage = 'QuickJS evaluation was cancelled';
const String _cancelledSentinel = '\u001eQuickJS_CANCELLED';
const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';
const String _pendingSentinel = '\u001eQuickJS_PENDING';

const String _readyMessage = 'ready';
const String _evalMessage = 'eval';
const String _evalAsyncMessage = 'evalAsync';
const String _bindCallbackMessage = 'bindCallback';
const String _callbackRequestMessage = 'callbackRequest';
const String _callbackResponseMessage = 'callbackResponse';
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

final Pointer<NativeFunction<QuickjsHostCallbackNative>>
_nativeHostCallbackPointer = Pointer.fromFunction<QuickjsHostCallbackNative>(
  _nativeHostCallback,
  -1,
);

/// native 平台的 QuickJS runtime。
///
/// 这个对象运行在调用方 isolate 中，只持有 worker isolate 的端口和 pending Future。
/// 真正的 `QuickjsRuntime*` 指针只存在于 [_nativeQuickjsWorkerMain]。
final class NativeQuickjsWorkerRuntime implements QuickjsJsRuntimeBase {
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
  final Map<int, Completer<String?>> _pending = <int, Completer<String?>>{};
  final Map<int, _QuickjsCallback> _callbacks = <int, _QuickjsCallback>{};
  StreamSubscription<dynamic>? _responseSubscription;
  int _nextRequestId = 1;
  bool _closed = false;
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

  @override
  Future<String> evaluate(String code, {Duration? timeout}) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    // 每次 eval 开始前清空取消标记，避免上一次 stop 影响后续任务。
    _cancelFlag.value = 0;
    final result = await _sendRequest<String>(_evalMessage, <String, Object?>{
      _messageCodeKey: code,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
    return result;
  }

  @override
  Future<String> evaluateAsync(String code, {Duration? timeout}) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    _cancelFlag.value = 0;
    final result =
        await _sendRequest<String>(_evalAsyncMessage, <String, Object?>{
          _messageCodeKey: code,
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
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    if (_closed) {
      _disposeFuture = _closePorts();
      return _disposeFuture!;
    }
    _closed = true;
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
    // C interrupt handler 会读取这个标记并中断正在执行的 JS。
    _cancelFlag.value = 1;
    final pending = _pending.values.map((completer) => completer.future);
    await Future.wait<void>([
      for (final future in pending) future.then<void>((_) {}, onError: (_) {}),
    ]);
    _closed = true;
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
    final completer = Completer<String?>();
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
        completer.complete(message['result'] as String?);
      } else {
        final error = '${message['error']}';
        // C bridge 和 web bridge 都通过 sentinel / 文本协议把错误还原为 Dart 异常。
        if (error == _timeoutErrorMessage) {
          completer.completeError(JsTimeoutException());
        } else if (error.contains(_cancelledErrorMessage)) {
          completer.completeError(JsCancelledException());
        } else if (error.contains('QuickJS runtime is closed')) {
          completer.completeError(JsRuntimeClosedException());
        } else if (error.startsWith(_exceptionSentinel)) {
          final exception = parseJsExceptionPayload(
            error.substring(_exceptionSentinel.length),
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
      final args = decoded is List ? decoded.cast<Object?>() : <Object?>[];
      final result = await callback(args);
      _sendPort.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: true,
        _messagePayloadJsonKey: jsonEncode(result),
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

  void _failAll(Object error) {
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
          case _evalMessage:
            final code = message[_messageCodeKey] as String;
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = _eval(bindings, runtime, code, timeoutMs);
            _sendOk(responseSendPort, requestId, result);
          case _evalAsyncMessage:
            final code = message[_messageCodeKey] as String;
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = await _evalAsync(bindings, runtime, code, timeoutMs);
            _sendOk(responseSendPort, requestId, result);
          case _bindCallbackMessage:
            final callbackId = message[_messageCallbackIdKey] as int;
            final name = message[_messageCallbackNameKey] as String;
            _bindCallback(bindings, runtime, callbackId, name);
            _sendOk(responseSendPort, requestId, null);
          case _disposeMessage:
            // runtime 必须在持有它的 worker isolate 中释放。
            closed = true;
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
      throw StateError('QuickJS callback resolution failed');
    }
  } finally {
    calloc.free(payloadPtr);
  }
}

String _eval(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String code,
  int? timeoutMs,
) {
  final codePtr = code.toNativeUtf8();
  final resultPtr = bindings.evalTimeout(runtime, codePtr, timeoutMs ?? 0);
  calloc.free(codePtr);
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

Future<String> _evalAsync(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String code,
  int? timeoutMs,
) async {
  final codePtr = code.toNativeUtf8();
  final stopwatch = Stopwatch()..start();
  Pointer<Utf8> resultPtr = bindings.evalAsyncStart(runtime, codePtr);
  calloc.free(codePtr);

  while (true) {
    final result = _takeResult(bindings, resultPtr);
    if (result != _pendingSentinel) {
      return result;
    }
    if (timeoutMs != null && stopwatch.elapsedMilliseconds >= timeoutMs) {
      throw const JsTimeoutException();
    }
    await Future<void>.delayed(Duration.zero);
    resultPtr = bindings.evalAsyncPoll(runtime);
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

void _sendOk(SendPort sendPort, int requestId, String? result) {
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
