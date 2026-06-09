import 'dart:async';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import '../quickjs_bindings.dart';
import '../quickjs_exception.dart';
import '../quickjs_runtime_base.dart';

const String _messageTypeKey = 'type';
const String _messageIdKey = 'id';
const String _messageCodeKey = 'code';
const String _messageTimeoutMsKey = 'timeoutMs';
const String _timeoutErrorMessage = 'QuickJS evaluation timed out';
const String _timeoutSentinel = '\u001eQuickJS_TIMEOUT';
const String _cancelledErrorMessage = 'QuickJS evaluation was cancelled';
const String _cancelledSentinel = '\u001eQuickJS_CANCELLED';
const String _exceptionSentinel = '\u001eQuickJS_EXCEPTION';

const String _readyMessage = 'ready';
const String _evalMessage = 'eval';
const String _disposeMessage = 'dispose';
const String _errorMessage = 'error';
const String _responseMessage = 'response';

typedef _WorkerReady = ({SendPort sendPort, String quickjsVersion});

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
  StreamSubscription<dynamic>? _responseSubscription;
  int _nextRequestId = 1;
  bool _closed = false;
  bool _portsClosed = false;
  Future<void>? _disposeFuture;

  static Future<NativeQuickjsWorkerRuntime> create() async {
    final readyPort = ReceivePort();
    final responsePort = ReceivePort();
    final errorPort = ReceivePort();
    final exitPort = ReceivePort();
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
      isolate = await Isolate.spawn(
        _nativeQuickjsWorkerMain,
        <String, Object>{
          'readyPort': readyPort.sendPort,
          'responsePort': responsePort.sendPort,
          'cancelFlagAddress': cancelFlag.address,
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
    _cancelFlag.value = 0;
    final result = await _sendRequest<String>(_evalMessage, <String, Object?>{
      _messageCodeKey: code,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
    return result;
  }

  @override
  Future<void> dispose() {
    if (_disposeFuture != null) {
      return _disposeFuture!;
    }
    _closed = true;
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
    _cancelFlag.value = 1;
    final pending = _pending.values.map((completer) => completer.future);
    await Future.wait<void>(
      [for (final future in pending) future.then<void>((_) {}, onError: (_) {})],
    );
    _closed = true;
    await _closePorts();
  }

  Future<T> _sendRequest<T>(
    String type, [
    Map<String, Object?> payload = const <String, Object?>{},
  ]) {
    final requestId = _nextRequestId++;
    final completer = Completer<String?>();
    _pending[requestId] = completer;
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
        if (error == _timeoutErrorMessage) {
          completer.completeError(JsTimeoutException());
        } else if (error.contains(_cancelledErrorMessage)) {
          completer.completeError(JsCancelledException());
        } else if (error.contains('QuickJS runtime is closed')) {
          completer.completeError(JsRuntimeClosedException());
        } else if (error.startsWith(_exceptionSentinel)) {
          completer.completeError(
            JsException(error.substring(_exceptionSentinel.length)),
          );
        } else {
          completer.completeError(StateError(error));
        }
      }
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

void _nativeQuickjsWorkerMain(Map<String, Object> ports) {
  final readySendPort = ports['readyPort']! as SendPort;
  final responseSendPort = ports['responsePort']! as SendPort;
  final cancelFlag = Pointer<Int32>.fromAddress(
    ports['cancelFlagAddress']! as int,
  );
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
    bindings.runtimeSetCancelFlag(runtime, cancelFlag);
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

  commandPort.listen((dynamic message) {
    if (message case {
      _messageTypeKey: final String type,
      _messageIdKey: final int requestId,
    }) {
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
          case _disposeMessage:
            closed = true;
            bindings.runtimeFree(runtime);
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

String _eval(
  QuickjsBindings bindings,
  Pointer<QuickjsRuntime> runtime,
  String code,
  int? timeoutMs,
) {
  final codePtr = code.toNativeUtf8();
  final resultPtr = timeoutMs == null || timeoutMs <= 0
      ? bindings.eval(runtime, codePtr)
      : bindings.evalTimeout(runtime, codePtr, timeoutMs);
  calloc.free(codePtr);
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
      throw JsException(result.substring(_exceptionSentinel.length));
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
  final message = switch (error) {
    JsException(:final message) => '$_exceptionSentinel$message',
    _ => '$error',
  };
  sendPort.send(<String, Object?>{
    _messageTypeKey: _responseMessage,
    _messageIdKey: requestId,
    'ok': false,
    'error': message,
  });
}
