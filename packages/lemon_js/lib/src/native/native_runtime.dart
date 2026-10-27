// Shared native heap with serialized foreground sync and background Future calls.
import 'dart:async';
import 'dart:convert';
import 'dart:ffi';
import 'dart:isolate';

import 'package:ffi/ffi.dart';

import 'quickjs_bindings.dart';
import '../bridge/callback_codec.dart';
import '../diagnostics/exception.dart';
import '../runtime/runtime_base.dart';
import '../runtime/runtime_options.dart';
import '../bridge/stream_bridge.dart';

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
const String _invokeMessage = 'invoke';
const String _createContextMessage = 'createContext';
const String _disposeContextMessage = 'disposeContext';
const String _evalContextMessage = 'evalContext';
const String _evalContextAsyncMessage = 'evalContextAsync';
const String _pumpContextTimersMessage = 'pumpContextTimers';
const String _pumpTimersMessage = 'pumpTimers';
const String _evalModuleContextMessage = 'evalModuleContext';
const String _evalModuleMessage = 'evalModule';
const String _evalAsyncMessage = 'run';
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

typedef _WorkerReady = ({
  SendPort sendPort,
  String engineVersion,
  int runtimeAddress,
});
typedef _JsCallback = FutureOr<Object?> Function(List<Object?> args);

abstract class _NativeTransport {
  Pointer<Int32> get cancelFlag;
  String get engineVersion;
  void send(Map<String, Object?> message);
  void listen(void Function(dynamic) listener);
  Future<void> close();
}

final class _WorkerTransport implements _NativeTransport {
  _WorkerTransport(
    this.isolate,
    this.receivePort,
    this.errorPort,
    this.exitPort,
    this.sendPort,
    this.errorSubscription,
    this.exitSubscription,
    this.cancelFlag,
    this.engineVersion,
  );
  final Isolate isolate;
  final ReceivePort receivePort, errorPort, exitPort;
  final SendPort sendPort;
  final StreamSubscription<dynamic> errorSubscription, exitSubscription;
  StreamSubscription<dynamic>? responseSubscription;
  _NativeExecutor? attachedExecutor;
  @override
  final Pointer<Int32> cancelFlag;
  @override
  final String engineVersion;
  @override
  void send(Map<String, Object?> message) => sendPort.send(message);
  @override
  void listen(void Function(dynamic) listener) {
    responseSubscription = receivePort.listen((dynamic message) {
      if (message is Map) {
        if (message['contextAddress'] case final int address) {
          attachedExecutor?.contexts[message['result'] as int] =
              Pointer<JsContext>.fromAddress(address);
        }
        if (message['disposedContextId'] case final int contextId) {
          attachedExecutor?.contexts.remove(contextId);
        }
      }
      listener(message);
    });
  }

  @override
  Future<void> close() async {
    isolate.kill(priority: Isolate.immediate);
    await responseSubscription?.cancel();
    await errorSubscription.cancel();
    await exitSubscription.cancel();
    attachedExecutor?.closed = true;
    attachedExecutor?.contexts.clear();
    attachedExecutor?.releaseCallbacks();
    receivePort.close();
    errorPort.close();
    exitPort.close();
    calloc.free(cancelFlag);
  }
}

/// Background Future transport with foreground synchronous access to the same heap.
final class NativeJsWorkerRuntime extends _NativeRuntime
    with _SynchronousNativeRuntime {
  late final _NativeExecutor _syncExecutor;
  @override
  _NativeExecutor get _executor => _syncExecutor;
  NativeJsWorkerRuntime._(super.transport);
  static Future<NativeJsWorkerRuntime> create({
    JsOptions options = const JsOptions(),
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
    NativeJsWorkerRuntime? runtime;

    void failCreate(Object error, [StackTrace? stackTrace]) {
      if (!ready.isCompleted) {
        ready.completeError(error, stackTrace);
      }
    }

    readySubscription = readyPort.listen((dynamic message) {
      if (message case {
        _messageTypeKey: _readyMessage,
        'sendPort': final SendPort sendPort,
        'engineVersion': final String engineVersion,
        'runtimeAddress': final int runtimeAddress,
      }) {
        if (!ready.isCompleted) {
          ready.complete((
            sendPort: sendPort,
            engineVersion: engineVersion,
            runtimeAddress: runtimeAddress,
          ));
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
      // Worker owns creation/disposal and Future calls. Foreground sync calls
      // borrow the same native heap through the runtime's exclusive-access gate.
      isolate = await Isolate.spawn(
        _nativeJsWorkerMain,
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

      runtime = NativeJsWorkerRuntime._(
        _WorkerTransport(
          isolate,
          responsePort,
          errorPort,
          exitPort,
          workerReady.sendPort,
          errorSubscription,
          exitSubscription,
          cancelFlag,
          workerReady.engineVersion,
        ),
      );
      final transport = runtime._transport as _WorkerTransport;
      runtime._syncExecutor = _NativeExecutor(
        cancelFlag,
        (message) =>
            scheduleMicrotask(() => runtime!._handleWorkerMessage(message)),
        options,
        immediateCallback: runtime._invokeImmediateCallback,
        borrowedRuntime: Pointer<JsRuntime>.fromAddress(
          workerReady.runtimeAddress,
        ),
      );
      transport.attachedExecutor = runtime._syncExecutor;
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
}

abstract class _NativeRuntime
    implements
        JsJsRuntimeBase,
        JsMultiContextRuntimeBase,
        JsTimerRuntimeBase,
        JsInvocationRuntimeBase,
        JsMultiContextInvocationRuntimeBase {
  _NativeRuntime(this._transport);
  final _NativeTransport _transport;
  String get engineVersion => _transport.engineVersion;
  final Map<int, Completer<Object?>> _pending = <int, Completer<Object?>>{};
  final Map<int, _JsCallback> _callbacks = <int, _JsCallback>{};
  final Map<int, Set<int>> _contextCallbackIds = <int, Set<int>>{};
  final Map<int, int> _callbackContextIds = <int, int>{};
  final Map<int, Set<int>> _contextStreamIds = <int, Set<int>>{};
  final Map<int, Set<int>> _contextSinkIds = <int, Set<int>>{};
  late final JsDartStreamRegistry _streamRegistry = JsDartStreamRegistry(
    (pullRequestId, payloadJson) {
      _transport.send(<String, Object?>{
        _messageTypeKey: _streamPullResponseMessage,
        _messagePullRequestIdKey: int.parse(pullRequestId),
        _messageSuccessKey: true,
        _messagePayloadJsonKey: payloadJson,
      });
    },
    (pullRequestId, message) {
      _transport.send(<String, Object?>{
        _messageTypeKey: _streamPullResponseMessage,
        _messagePullRequestIdKey: int.parse(pullRequestId),
        _messageSuccessKey: false,
        _messagePayloadJsonKey: message,
      });
    },
  );
  late final JsJsSinkRegistry _sinkRegistry = JsJsSinkRegistry(
    (actionRequestId) {
      _transport.send(<String, Object?>{
        _messageTypeKey: _sinkActionResponseMessage,
        _messageActionRequestIdKey: int.parse(actionRequestId),
        _messageSuccessKey: true,
        _messagePayloadJsonKey: '',
      });
    },
    (actionRequestId, message) {
      _transport.send(<String, Object?>{
        _messageTypeKey: _sinkActionResponseMessage,
        _messageActionRequestIdKey: int.parse(actionRequestId),
        _messageSuccessKey: false,
        _messagePayloadJsonKey: message,
      });
    },
  );
  int _nextRequestId = 1;
  @override
  Future<String> invoke(
    String requestJson, {
    bool awaitResult = false,
    Duration? timeout,
  }) => _invokeRequest(null, requestJson, awaitResult, timeout);

  @override
  Future<String> invokeContext(
    int contextId,
    String requestJson, {
    bool awaitResult = false,
    Duration? timeout,
  }) => _invokeRequest(contextId, requestJson, awaitResult, timeout);

  Future<String> _invokeRequest(
    int? contextId,
    String requestJson,
    bool awaitResult,
    Duration? timeout,
  ) {
    Future<String> send() => _sendRequest<String>(_invokeMessage, {
      _messageContextIdKey: ?contextId,
      _messageArgsJsonKey: requestJson,
      'awaitResult': awaitResult,
      if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
    });
    return contextId == null && awaitResult ? _runRootAsync(send) : send();
  }

  Future<String> _runRootAsync(Future<String> Function() action) async {
    if (_closed) throw JsRuntimeClosedException();
    _transport.cancelFlag.value = 0;
    _asyncRunning = true;
    try {
      return await action();
    } finally {
      _asyncRunning = false;
    }
  }

  bool _closed = false;
  bool _asyncRunning = false;
  bool _portsClosed = false;
  Future<void>? _disposeFuture;

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
    String name = '<context-run>',
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
    FutureOr<Object?> Function(List<Object?> args) callback,
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
    _transport.cancelFlag.value = 0;
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
    String name = '<run>',
  }) async {
    if (_closed) {
      throw JsRuntimeClosedException();
    }
    return _runRootAsync(() async {
      final result =
          await _sendRequest<String>(_evalAsyncMessage, <String, Object?>{
            _messageCodeKey: code,
            _messageSourceNameKey: name,
            if (timeout != null) _messageTimeoutMsKey: timeout.inMilliseconds,
          });
      return result;
    });
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
    _transport.cancelFlag.value = 0;
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
    FutureOr<Object?> Function(List<Object?> args) callback,
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
      _transport.cancelFlag.value = 1;
      _streamRegistry.dispose();
      _sinkRegistry.dispose();
      _failAll(JsCancelledException());
      _disposeFuture = _sendRequest<void>(
        _disposeMessage,
      ).whenComplete(_closePorts);
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
  Future<void> stop() {
    if (_closed) {
      return _disposeFuture ?? Future<void>.value();
    }
    // C interrupt handler 会读取这个标记并中断正在执行的 JS。
    _transport.cancelFlag.value = 1;
    return dispose();
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
    if (_closed && type != _disposeMessage) {
      return Future<T>.error(JsRuntimeClosedException());
    }
    final requestId = _nextRequestId++;
    final completer = Completer<Object?>();
    _pending[requestId] = completer;
    // 所有 worker 命令都带 requestId，响应回来后用它完成对应 Future。
    _transport.send(<String, Object?>{
      _messageTypeKey: type,
      _messageIdKey: requestId,
      ...payload,
    });
    return completer.future.then((value) => value as T);
  }

  void _listenResponses() {
    _transport.listen(_handleWorkerMessage);
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
      _transport.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: false,
        _messagePayloadJsonKey: 'QuickJS callback $callbackId is not bound',
      });
      return;
    }

    final contextId = _callbackContextIds[callbackId];
    try {
      final decoded = jsonDecode(argsJson);
      final args = decoded is List
          ? [for (final item in decoded) decodeCallbackWireValue(item)]
          : <Object?>[];
      final result = await callback(args);
      if (!_isCallbackContextLive(contextId)) return;
      final encodedResult = result is Stream
          ? _encodeContextStream(contextId, result.cast<Object?>())
          : _streamRegistry.encodeCallbackResult(result);
      _transport.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: true,
        _messagePayloadJsonKey: jsonEncode(encodedResult),
      });
    } catch (error) {
      if (!_isCallbackContextLive(contextId)) return;
      _transport.send(<String, Object?>{
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: callbackRequestId,
        _messageSuccessKey: false,
        _messagePayloadJsonKey: '$error',
      });
    }
  }

  bool _isCallbackContextLive(int? contextId) =>
      !_closed &&
      (contextId == null || _contextCallbackIds.containsKey(contextId));

  Object _encodeContextStream(int? contextId, Stream<Object?> stream) {
    final streamId = _streamRegistry.register(stream);
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
    if (_portsClosed) return;
    _portsClosed = true;
    _callbacks.clear();
    _callbackContextIds.clear();
    _contextCallbackIds.clear();
    _contextStreamIds.clear();
    _contextSinkIds.clear();
    await _transport.close();
  }
}

/// Runs QuickJS directly in the caller isolate.
final class NativeJsLocalRuntime extends _NativeRuntime
    with _SynchronousNativeRuntime {
  NativeJsLocalRuntime._(_LocalTransport transport) : super(transport) {
    transport.executor = _NativeExecutor(
      transport.cancelFlag,
      (message) => scheduleMicrotask(() => _handleWorkerMessage(message)),
      transport.options,
      immediateCallback: _invokeImmediateCallback,
    );
    _listenResponses();
  }
  static Future<NativeJsLocalRuntime> create({
    JsOptions options = const JsOptions(),
  }) async {
    final transport = _LocalTransport(options);
    try {
      return NativeJsLocalRuntime._(transport);
    } catch (_) {
      calloc.free(transport.cancelFlag);
      rethrow;
    }
  }

  @override
  _NativeExecutor get _executor => (_transport as _LocalTransport).executor;
}

mixin _SynchronousNativeRuntime on _NativeRuntime
    implements JsSyncRuntimeBase, JsSyncMultiContextRuntimeBase {
  @override
  bool get supportsSync => true;
  _NativeExecutor get _executor;
  int _invokeImmediateCallback(int id, String argsJson) {
    try {
      final callback = _callbacks[id];
      if (_closed) throw JsRuntimeClosedException();
      if (callback == null) {
        throw StateError('QuickJS callback $id is not bound');
      }
      final args = (jsonDecode(argsJson) as List)
          .map(decodeCallbackWireValue)
          .toList();
      final contextId = _callbackContextIds[id];
      final result = callback(args);
      if (result is Future<Object?>) {
        final requestId = _executor.allocateHostRequestId();
        unawaited(_completeImmediateAsync(requestId, contextId, result));
        return requestId;
      }
      if (!_isCallbackContextLive(contextId)) throw JsRuntimeClosedException();
      _setImmediateResult(
        true,
        jsonEncode(_encodeCallbackResult(contextId, result)),
      );
    } catch (error) {
      _setImmediateResult(false, '$error');
    }
    return 0;
  }

  Object? _encodeCallbackResult(int? contextId, Object? result) =>
      result is Stream
      ? _encodeContextStream(contextId, result.cast<Object?>())
      : _streamRegistry.encodeCallbackResult(result);
  Future<void> _completeImmediateAsync(
    int requestId,
    int? contextId,
    Future<Object?> result,
  ) async {
    try {
      final value = await result;
      if (!_isCallbackContextLive(contextId)) return;
      _transport.send({
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: requestId,
        _messageSuccessKey: true,
        _messagePayloadJsonKey: jsonEncode(
          _encodeCallbackResult(contextId, value),
        ),
      });
    } catch (error) {
      if (!_isCallbackContextLive(contextId)) return;
      _transport.send({
        _messageTypeKey: _callbackResponseMessage,
        _messageCallbackRequestIdKey: requestId,
        _messageSuccessKey: false,
        _messagePayloadJsonKey: '$error',
      });
    }
  }

  void _setImmediateResult(bool success, String payload) {
    final ptr = payload.toNativeUtf8();
    try {
      _executor.bindings.runtimeSetCallbackResult(
        _executor.runtime,
        success ? 1 : 0,
        ptr,
      );
    } finally {
      calloc.free(ptr);
    }
  }

  @override
  String evaluateSync(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) {
    if (_closed) throw JsRuntimeClosedException();
    if (_executor.inHostCallback) {
      throw StateError(
        'Reentrant synchronous JavaScript execution is not supported',
      );
    }
    return _executor.access(
      () => _eval(
        _executor.bindings,
        _executor.runtime,
        code,
        name,
        timeout?.inMilliseconds,
      ),
    );
  }

  @override
  String invokeSync(String requestJson, {Duration? timeout}) =>
      _invokeSync(null, requestJson, timeout);
  @override
  String invokeContextSync(
    int contextId,
    String requestJson, {
    Duration? timeout,
  }) => _invokeSync(contextId, requestJson, timeout);

  String _invokeSync(int? contextId, String requestJson, Duration? timeout) {
    if (_closed) throw JsRuntimeClosedException();
    if (_executor.inHostCallback) {
      throw StateError(
        'Reentrant synchronous JavaScript execution is not supported',
      );
    }
    return _executor.access(() {
      final context = contextId == null
          ? nullptr.cast<JsContext>()
          : _executor.contextFor(contextId);
      if (context == null) throw JsRuntimeClosedException();
      return _invoke(
        _executor.bindings,
        _executor.runtime,
        context,
        requestJson,
        timeout?.inMilliseconds,
      );
    });
  }

  @override
  String evaluateContextSync(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<eval>',
  }) {
    if (_closed) throw JsRuntimeClosedException();
    if (_executor.inHostCallback) {
      throw StateError(
        'Reentrant synchronous JavaScript execution is not supported',
      );
    }
    return _executor.access(() {
      final context = _executor.contextFor(contextId);
      if (context == null) throw JsRuntimeClosedException();
      return _evalContext(
        _executor.bindings,
        context,
        code,
        name,
        timeout?.inMilliseconds,
      );
    });
  }
}

final class _LocalTransport implements _NativeTransport {
  _LocalTransport(this.options);
  final JsOptions options;
  late final _NativeExecutor executor;
  @override
  final Pointer<Int32> cancelFlag = calloc<Int32>();
  @override
  String get engineVersion => executor.engineVersion;
  @override
  void listen(void Function(dynamic) listener) {}
  @override
  void send(Map<String, Object?> message) {
    if (executor.inHostCallback) {
      scheduleMicrotask(() => unawaited(executor.handle(message)));
    } else {
      unawaited(executor.handle(message));
    }
  }

  @override
  Future<void> close() async {
    cancelFlag.value = 1;
    if (!executor.closed) {
      await executor.handle({
        _messageTypeKey: _disposeMessage,
        _messageIdKey: -1,
      });
    }
    await executor.whenIdle;
    executor.releaseCallbacks();
    calloc.free(cancelFlag);
  }
}

/// Executes a shared native heap under exclusive access with isolate-local callbacks.
final class _NativeExecutor {
  _NativeExecutor(
    this.cancelFlag,
    this._emit,
    JsOptions options, {
    this.immediateCallback,
    Pointer<JsRuntime>? borrowedRuntime,
    this.waitForAccess = false,
  }) {
    bindings = JsBindings(JsBindings.open());
    runtime = borrowedRuntime ?? bindings.runtimeNew();
    if (runtime == nullptr) {
      throw StateError('Failed to create QuickJS runtime');
    }
    if (options.memoryLimitBytes case final int limit
        when borrowedRuntime == null) {
      bindings.runtimeSetMemoryLimit(runtime, limit);
    }
    if (options.stackLimitBytes case final int limit
        when borrowedRuntime == null) {
      bindings.runtimeSetStackLimit(runtime, limit);
    }
    if (borrowedRuntime == null) {
      bindings.runtimeSetCancelFlag(runtime, cancelFlag);
    }
    hostCallback = NativeCallable<JsHostCallbackNative>.isolateLocal((
      int id,
      Pointer<Utf8> args,
    ) {
      if (immediateCallback != null) {
        inHostCallback = true;
        try {
          return immediateCallback!(id, args.toDartString());
        } finally {
          inHostCallback = false;
        }
      }
      final requestId = allocateHostRequestId();
      emit({
        _messageTypeKey: _callbackRequestMessage,
        _messageCallbackRequestIdKey: requestId,
        _messageCallbackIdKey: id,
        _messageArgsJsonKey: args.toDartString(),
      });
      return requestId;
    }, exceptionalReturn: -1);
    hostPull = NativeCallable<JsHostStreamPullNative>.isolateLocal((int id) {
      final requestId = allocateHostRequestId();
      emit({
        _messageTypeKey: _streamPullRequestMessage,
        _messagePullRequestIdKey: requestId,
        _messageStreamIdKey: id,
      });
      return requestId;
    }, exceptionalReturn: -1);
    hostCancel = NativeCallable<JsHostStreamCancelNative>.isolateLocal((
      int id,
    ) {
      emit({
        _messageTypeKey: _streamCancelRequestMessage,
        _messageStreamIdKey: id,
      });
    });
    hostSink = NativeCallable<JsHostSinkActionNative>.isolateLocal((
      int id,
      Pointer<Utf8> action,
      Pointer<Utf8> payload,
    ) {
      final requestId = allocateHostRequestId();
      emit({
        _messageTypeKey: _sinkActionRequestMessage,
        _messageActionRequestIdKey: requestId,
        _messageSinkIdKey: id,
        _messageSinkActionKey: action.toDartString(),
        _messagePayloadJsonKey: payload == nullptr
            ? null
            : payload.toDartString(),
      });
      return requestId;
    }, exceptionalReturn: -1);
    bindings.runtimeAccess = access;
  }
  final Pointer<Int32> cancelFlag;
  final void Function(Map<String, Object?>) _emit;
  final List<Map<String, Object?>> _deferredResponses = [];
  void emit(Map<String, Object?> message) {
    if (_accessDepth > 0 && message[_messageTypeKey] == _responseMessage) {
      _deferredResponses.add(message);
    } else {
      _emit(message);
    }
  }

  final int Function(int, String)? immediateCallback;
  late final JsBindings bindings;
  Pointer<JsRuntime> runtime = nullptr;
  final contexts = <int, Pointer<JsContext>>{};
  int nextContextId = 1;
  final bool waitForAccess;
  int _accessDepth = 0;
  int allocateHostRequestId() => bindings.nextRequestId(runtime);
  Pointer<JsContext>? contextFor(int id) {
    final context = contexts[id];
    return context != null && bindings.contextIsAlive(runtime, context) != 0
        ? context
        : null;
  }

  T access<T>(T Function() action) {
    if (_accessDepth > 0) return action();
    if (closed || runtime == nullptr) throw JsRuntimeClosedException();
    if (bindings.runtimeEnter(
          runtime,
          hostCallback.nativeFunction,
          hostPull.nativeFunction,
          hostCancel.nativeFunction,
          hostSink.nativeFunction,
          waitForAccess ? 1 : 0,
        ) ==
        0) {
      throw StateError('QuickJS runtime is busy executing on another thread');
    }
    _accessDepth++;
    try {
      return action();
    } finally {
      _accessDepth--;
      if (runtime != nullptr) bindings.runtimeLeave(runtime);
      if (_deferredResponses.isNotEmpty) {
        final responses = List<Map<String, Object?>>.of(_deferredResponses);
        _deferredResponses.clear();
        for (final response in responses) {
          _emit(response);
        }
      }
    }
  }

  bool closed = false;
  bool inHostCallback = false;
  int activeAsyncCalls = 0;
  Completer<void>? _idle;
  final Map<int, Map<Completer<void>, Timer>> _polls = {};
  Future<void> get whenIdle => activeAsyncCalls == 0
      ? Future<void>.value()
      : (_idle ??= Completer<void>()).future;
  Future<void> waitForPoll(int contextId) {
    final completion = Completer<void>();
    final polls = _polls.putIfAbsent(contextId, () => {});
    polls[completion] = Timer(const Duration(milliseconds: 1), () {
      polls.remove(completion);
      if (polls.isEmpty) _polls.remove(contextId);
      completion.complete();
    });
    return completion.future;
  }

  void cancelPolls(int contextId) {
    final polls = _polls.remove(contextId);
    if (polls == null) return;
    for (final entry in polls.entries) {
      entry.value.cancel();
      entry.key.complete();
    }
  }

  void finishAsyncCall() {
    activeAsyncCalls--;
    if (activeAsyncCalls == 0) {
      _idle?.complete();
      _idle = null;
    }
    pumpIdleJobs();
  }

  void pumpIdleJobs() {
    if (!closed && activeAsyncCalls == 0) {
      access(() => bindings.runtimePumpJobs(runtime));
    }
  }

  late final NativeCallable<JsHostCallbackNative> hostCallback;
  late final NativeCallable<JsHostStreamPullNative> hostPull;
  late final NativeCallable<JsHostStreamCancelNative> hostCancel;
  late final NativeCallable<JsHostSinkActionNative> hostSink;
  bool _callbacksReleased = false;
  String get engineVersion => bindings.version().toDartString();
  void releaseCallbacks() {
    if (_callbacksReleased) return;
    _callbacksReleased = true;
    hostCallback.close();
    hostPull.close();
    hostCancel.close();
    hostSink.close();
  }

  Future<void> handle(dynamic message) {
    if (closed) return _handle(message);
    return access(() => _handle(message));
  }

  Future<void> _handle(dynamic message) async {
    if (closed && message is Map && !message.containsKey(_messageIdKey)) return;
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
      pumpIdleJobs();
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
      pumpIdleJobs();
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
      pumpIdleJobs();
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
            _sendOk(
              emit,
              requestId,
              contextId,
              contextAddress: context.address,
            );
          case _disposeContextMessage:
            final contextId = message[_messageContextIdKey] as int;
            cancelPolls(contextId);
            final context = contexts.remove(contextId);
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            bindings.contextFree(context);
            _sendOk(emit, requestId, null, disposedContextId: contextId);
          case _invokeMessage:
            final contextId = message[_messageContextIdKey] as int?;
            final context = contextId == null
                ? nullptr.cast<JsContext>()
                : contexts[contextId];
            if (context == null) throw JsRuntimeClosedException();
            final request = message[_messageArgsJsonKey] as String;
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            late final String result;
            if (message['awaitResult'] == true) {
              activeAsyncCalls++;
              try {
                result = contextId == null
                    ? await _evalAsync(
                        bindings,
                        runtime,
                        '',
                        '<call>',
                        timeoutMs,
                        cancelFlag,
                        () => waitForPoll(0),
                        invocation: request,
                        isAlive: () => !closed,
                      )
                    : await _evalContextAsync(
                        bindings,
                        context,
                        runtime,
                        '',
                        '<call>',
                        timeoutMs,
                        cancelFlag,
                        () => contexts[contextId] == context,
                        () => waitForPoll(contextId),
                        invocation: request,
                      );
              } finally {
                finishAsyncCall();
              }
            } else {
              result = _invoke(bindings, runtime, context, request, timeoutMs);
            }
            _sendOk(emit, requestId, result);
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
            _sendOk(emit, requestId, result);
          case _evalContextAsyncMessage:
            final contextId = message[_messageContextIdKey] as int;
            final context = contexts[contextId];
            if (context == null) {
              throw StateError('Unknown QuickJS context: $contextId');
            }
            activeAsyncCalls++;
            late final String result;
            try {
              result = await _evalContextAsync(
                bindings,
                context,
                runtime,
                message[_messageCodeKey] as String,
                message[_messageSourceNameKey] as String? ?? '<context-run>',
                message[_messageTimeoutMsKey] as int?,
                cancelFlag,
                () => contexts[contextId] == context,
                () => waitForPoll(contextId),
              );
            } finally {
              finishAsyncCall();
            }
            _sendOk(emit, requestId, result);
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
            _sendOk(emit, requestId, result);
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
            _sendOk(emit, requestId, delay < 0 ? null : delay);
          case _pumpTimersMessage:
            final delay = bindings.runtimePumpTimers(runtime);
            if (delay < -1) {
              throw StateError('QuickJS timer pending job failed');
            }
            _sendOk(emit, requestId, delay < 0 ? null : delay);
          case _evalMessage:
            final code = message[_messageCodeKey] as String;
            final name = message[_messageSourceNameKey] as String? ?? '<eval>';
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            final result = _eval(bindings, runtime, code, name, timeoutMs);
            _sendOk(emit, requestId, result);
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
            _sendOk(emit, requestId, result);
          case _evalAsyncMessage:
            final code = message[_messageCodeKey] as String;
            final name = message[_messageSourceNameKey] as String? ?? '<run>';
            final timeoutMs = message[_messageTimeoutMsKey] as int?;
            activeAsyncCalls++;
            late final String result;
            try {
              result = await _evalAsync(
                bindings,
                runtime,
                code,
                name,
                timeoutMs,
                cancelFlag,
                () => waitForPoll(0),
                isAlive: () => !closed,
              );
            } finally {
              finishAsyncCall();
            }
            _sendOk(emit, requestId, result);
          case _bindCallbackMessage:
            final callbackId = message[_messageCallbackIdKey] as int;
            final name = message[_messageCallbackNameKey] as String;
            _bindCallback(
              bindings,
              runtime,
              callbackId,
              name,
              hostCallback.nativeFunction,
            );
            _sendOk(emit, requestId, null);
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
              hostCallback.nativeFunction,
            );
            _sendOk(emit, requestId, null);
          case _bindSinkMessage:
            final sinkId = message[_messageSinkIdKey] as int;
            final name = message[_messageCallbackNameKey] as String;
            _bindSink(bindings, runtime, sinkId, name);
            _sendOk(emit, requestId, null);
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
            _sendOk(emit, requestId, null);
          case _disposeMessage:
            // runtime 必须在持有它的 worker isolate 中释放。
            closed = true;
            for (final contextId in _polls.keys.toList()) {
              cancelPolls(contextId);
            }
            for (final context in contexts.values) {
              bindings.contextFree(context);
            }
            contexts.clear();
            bindings.runtimeFree(runtime);
            runtime = nullptr;
            _sendOk(emit, requestId, null);

          default:
            throw StateError('Unknown QuickJS worker command: $type');
        }
      } catch (error) {
        _sendError(emit, requestId, error);
      }
    }
  }
}

void _nativeJsWorkerMain(Map<String, Object> ports) {
  final ready = ports['readyPort']! as SendPort;
  final response = ports['responsePort']! as SendPort;
  final commands = ReceivePort();
  try {
    final executor = _NativeExecutor(
      Pointer<Int32>.fromAddress(ports['cancelFlagAddress']! as int),
      response.send,
      JsOptions(
        memoryLimitBytes: ports[_messageMemoryLimitBytesKey] as int?,
        stackLimitBytes: ports[_messageStackLimitBytesKey] as int?,
      ),
      waitForAccess: true,
    );
    ready.send({
      _messageTypeKey: _readyMessage,
      'sendPort': commands.sendPort,
      'engineVersion': executor.engineVersion,
      'runtimeAddress': executor.runtime.address,
    });
    commands.listen((dynamic message) async {
      await executor.handle(message);
      if (executor.closed) {
        await executor.whenIdle;
        executor.releaseCallbacks();
        commands.close();
      }
    });
  } catch (error) {
    ready.send({_messageTypeKey: _errorMessage, 'error': '$error'});
    commands.close();
  }
}

void _bindSink(
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
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
  JsBindings bindings,
  Pointer<JsContext> context,
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  int callbackId,
  String name,
  Pointer<NativeFunction<JsHostCallbackNative>> callback,
) {
  final namePtr = name.toNativeUtf8();
  try {
    final result = bindings.runtimeBindCallback(
      runtime,
      callbackId,
      namePtr,
      callback,
    );
    if (result < 0) {
      throw StateError('QuickJS callback binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _bindContextCallback(
  JsBindings bindings,
  Pointer<JsContext> context,
  int callbackId,
  String name,
  Pointer<NativeFunction<JsHostCallbackNative>> callback,
) {
  final namePtr = name.toNativeUtf8();
  try {
    final result = bindings.contextBindCallback(
      context,
      callbackId,
      namePtr,
      callback,
    );
    if (result < 0) {
      throw StateError('QuickJS context callback binding failed');
    }
  } finally {
    calloc.free(namePtr);
  }
}

void _resolveCallback(
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
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
  JsBindings bindings,
  Pointer<JsContext> context,
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  String code,
  String name,
  int? timeoutMs,
) {
  if (timeoutMs != null && timeoutMs <= 0) throw const JsTimeoutException();
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
  return _takeResult(bindings, resultPtr);
}

String _invoke(
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  Pointer<JsContext> context,
  String request,
  int? timeoutMs,
) {
  final pointer = request.toNativeUtf8();
  try {
    return _takeResult(
      bindings,
      _executeAsyncStep(
        bindings,
        runtime,
        timeoutMs,
        () => bindings.invoke(runtime, context, pointer, 0),
      ),
    );
  } finally {
    calloc.free(pointer);
  }
}

String _evalContext(
  JsBindings bindings,
  Pointer<JsContext> context,
  String code,
  String name,
  int? timeoutMs,
) {
  if (timeoutMs != null && timeoutMs <= 0) throw const JsTimeoutException();
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
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  String code,
  String name,
  int? timeoutMs,
  Pointer<Int32> cancelFlag,
  Future<void> Function() waitForPoll, {
  String? invocation,
  bool Function()? isAlive,
}) => _nativeAsyncEvaluation(
  bindings,
  runtime,
  nullptr,
  code,
  name,
  timeoutMs,
  cancelFlag,
  isAlive ?? () => true,
  waitForPoll,
  invocation,
);

Future<String> _evalContextAsync(
  JsBindings bindings,
  Pointer<JsContext> context,
  Pointer<JsRuntime> runtime,
  String code,
  String name,
  int? timeoutMs,
  Pointer<Int32> cancelFlag,
  bool Function() isAlive,
  Future<void> Function() waitForPoll, {
  String? invocation,
}) => _nativeAsyncEvaluation(
  bindings,
  runtime,
  context,
  code,
  name,
  timeoutMs,
  cancelFlag,
  isAlive,
  waitForPoll,
  invocation,
);

Future<String> _nativeAsyncEvaluation(
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  Pointer<JsContext> context,
  String code,
  String name,
  int? timeoutMs,
  Pointer<Int32> cancelFlag,
  bool Function() isAlive,
  Future<void> Function() waitForPoll,
  String? invocation,
) async {
  final codePtr = (invocation ?? code).toNativeUtf8();
  final namePtr = invocation == null
      ? name.toNativeUtf8()
      : nullptr.cast<Utf8>();
  final stopwatch = Stopwatch()..start();
  Pointer<Utf8> resultPtr = nullptr;
  try {
    try {
      resultPtr = _executeAsyncStep(
        bindings,
        runtime,
        timeoutMs,
        () => invocation != null
            ? bindings.invoke(runtime, context, codePtr, 1)
            : context == nullptr
            ? bindings.evalAsyncStartNamed(runtime, codePtr, namePtr)
            : bindings.contextEvalAsyncStartNamed(context, codePtr, namePtr),
      );
    } finally {
      calloc.free(codePtr);
      if (namePtr != nullptr) calloc.free(namePtr);
    }
    while (true) {
      if (cancelFlag.value != 0 || !isAlive()) throw JsCancelledException();
      final ownedResult = resultPtr;
      resultPtr = nullptr;
      final result = _takeResult(bindings, ownedResult);
      if (result != _pendingSentinel) return result;
      if (timeoutMs != null && stopwatch.elapsedMilliseconds >= timeoutMs) {
        throw const JsTimeoutException();
      }
      await waitForPoll();
      if (cancelFlag.value != 0 || !isAlive()) throw JsCancelledException();
      resultPtr = _executeAsyncStep(
        bindings,
        runtime,
        timeoutMs == null ? null : timeoutMs - stopwatch.elapsedMilliseconds,
        () => context == nullptr
            ? bindings.evalAsyncPoll(runtime)
            : bindings.contextEvalAsyncPoll(context),
      );
    }
  } on JsTimeoutException {
    if (isAlive()) {
      bindings.withAccess(() => bindings.asyncReset(runtime, context));
    }
    rethrow;
  } on JsCancelledException {
    if (isAlive()) {
      bindings.withAccess(() => bindings.asyncReset(runtime, context));
    }
    rethrow;
  } finally {
    if (resultPtr != nullptr) bindings.freeString(resultPtr);
  }
}

Pointer<Utf8> _executeAsyncStep(
  JsBindings bindings,
  Pointer<JsRuntime> runtime,
  int? remainingMs,
  Pointer<Utf8> Function() action,
) {
  return bindings.withAccess(() {
    if (remainingMs != null && remainingMs <= 0) {
      throw const JsTimeoutException();
    }
    bindings.runtimeBeginExecution(runtime, remainingMs ?? 0);
    Pointer<Utf8> result = nullptr;
    int status;
    try {
      result = action();
    } finally {
      status = bindings.runtimeEndExecution(runtime);
    }
    if (status != 0) {
      if (result != nullptr) bindings.freeString(result);
      if (status == 2) throw JsCancelledException();
      throw const JsTimeoutException();
    }
    return result;
  });
}

String _takeResult(JsBindings bindings, Pointer<Utf8> resultPtr) {
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

void _sendOk(
  void Function(Map<String, Object?>) emit,
  int requestId,
  Object? result, {
  int? contextAddress,
  int? disposedContextId,
}) {
  emit(<String, Object?>{
    _messageTypeKey: _responseMessage,
    _messageIdKey: requestId,
    'ok': true,
    'result': result,
    'contextAddress': ?contextAddress,
    'disposedContextId': ?disposedContextId,
  });
}

void _sendError(
  void Function(Map<String, Object?>) emit,
  int requestId,
  Object error,
) {
  // Dart 侧异常跨 isolate 发送时统一压成字符串，再由主 isolate 映射回异常类型。
  final message = switch (error) {
    JsThrownException() => '$_exceptionSentinel${_encodeJsException(error)}',
    _ => '$error',
  };
  emit(<String, Object?>{
    _messageTypeKey: _responseMessage,
    _messageIdKey: requestId,
    'ok': false,
    'error': message,
  });
}

String _encodeJsException(JsThrownException error) {
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
// ignore_for_file: public_member_api_docs
