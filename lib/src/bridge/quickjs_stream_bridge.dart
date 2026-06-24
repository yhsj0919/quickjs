import 'dart:async';
import 'dart:collection';
import 'dart:convert';

import 'quickjs_callback_codec.dart';

const String quickjsDartStreamWireType = 'dartStream';

Map<String, Object?> encodeDartStreamWire(int streamId) {
  return {'__quickjsType': quickjsDartStreamWireType, 'streamId': streamId};
}

String encodeStreamPullDone() => jsonEncode(<String, Object?>{'done': true});

String encodeStreamPullValue(Object? value) => jsonEncode(<String, Object?>{
  'done': false,
  'value': encodeCallbackWireValue(value),
});

final class QuickjsDartStreamRegistry {
  QuickjsDartStreamRegistry(this._onPullResponse, this._onPullError);

  final void Function(String pullRequestId, String payloadJson) _onPullResponse;
  final void Function(String pullRequestId, String message) _onPullError;

  int _nextStreamId = 1;
  final Map<int, _DartStreamSession> _sessions = <int, _DartStreamSession>{};

  Object? encodeCallbackResult(Object? result) {
    if (result is Stream) {
      return encodeDartStreamWire(register(result.cast<Object?>()));
    }
    return encodeCallbackWireValue(result);
  }

  int register(Stream<Object?> stream) {
    final streamId = _nextStreamId++;
    final session = _DartStreamSession(streamId, _remove);
    _sessions[streamId] = session;
    late final StreamSubscription<Object?> subscription;
    subscription = stream.listen(
      session.onData,
      onError: session.onError,
      onDone: session.onDone,
      cancelOnError: false,
    );
    session.subscription = subscription;
    subscription.pause();
    return streamId;
  }

  void handlePull(String pullRequestId, int streamId) {
    final session = _sessions[streamId];
    if (session == null || session.cancelled) {
      _onPullError(pullRequestId, 'QuickJS stream $streamId is not available');
      return;
    }
    session.enqueuePull(pullRequestId, _onPullResponse, _onPullError);
  }

  void handleCancel(int streamId) {
    _sessions.remove(streamId)?.cancel();
  }

  void dispose() {
    for (final session in _sessions.values) {
      session.cancel();
    }
    _sessions.clear();
  }

  void _remove(int streamId) {
    _sessions.remove(streamId);
  }
}

final class _DartStreamSession {
  _DartStreamSession(this.streamId, this._remove);

  final int streamId;
  final void Function(int streamId) _remove;
  StreamSubscription<Object?>? subscription;
  bool cancelled = false;
  bool done = false;
  Object? pendingError;
  final Queue<Object?> bufferedValues = Queue<Object?>();
  final Queue<_PendingStreamPull> pendingPulls = Queue<_PendingStreamPull>();

  void onData(Object? value) {
    if (cancelled) {
      return;
    }
    if (pendingPulls.isNotEmpty) {
      pendingPulls.removeFirst().completeValue(value);
      subscription?.pause();
    } else {
      bufferedValues.addLast(value);
      subscription?.pause();
    }
  }

  void onError(Object error, StackTrace stackTrace) {
    if (cancelled) {
      return;
    }
    pendingError = error;
    while (pendingPulls.isNotEmpty) {
      pendingPulls.removeFirst().completeError('$error');
    }
    _remove(streamId);
  }

  void onDone() {
    if (cancelled) {
      return;
    }
    done = true;
    if (bufferedValues.isNotEmpty) {
      return;
    }
    while (pendingPulls.isNotEmpty) {
      pendingPulls.removeFirst().completeDone();
    }
    _remove(streamId);
  }

  void enqueuePull(
    String pullRequestId,
    void Function(String pullRequestId, String payloadJson) onResponse,
    void Function(String pullRequestId, String message) onError,
  ) {
    final pull = _PendingStreamPull(pullRequestId, onResponse, onError);
    if (pendingError != null) {
      pull.completeError('$pendingError');
      return;
    }
    if (bufferedValues.isNotEmpty) {
      pull.completeValue(bufferedValues.removeFirst());
      if (done && bufferedValues.isEmpty) {
        _remove(streamId);
      }
      return;
    }
    if (done) {
      pull.completeDone();
      _remove(streamId);
      return;
    }
    pendingPulls.add(pull);
    subscription?.resume();
  }

  void cancel() {
    if (cancelled) {
      return;
    }
    cancelled = true;
    while (pendingPulls.isNotEmpty) {
      pendingPulls.removeFirst().completeError('QuickJS stream cancelled');
    }
    subscription?.cancel();
    subscription = null;
  }
}

final class _PendingStreamPull {
  _PendingStreamPull(this.pullRequestId, this._onResponse, this._onError);

  final String pullRequestId;
  final void Function(String pullRequestId, String payloadJson) _onResponse;
  final void Function(String pullRequestId, String message) _onError;

  void completeValue(Object? value) {
    _onResponse(pullRequestId, encodeStreamPullValue(value));
  }

  void completeDone() {
    _onResponse(pullRequestId, encodeStreamPullDone());
  }

  void completeError(String message) {
    _onError(pullRequestId, message);
  }
}

final class QuickjsJsSinkRegistry {
  QuickjsJsSinkRegistry(this._onActionComplete, this._onActionError);

  final void Function(String actionRequestId) _onActionComplete;
  final void Function(String actionRequestId, String message) _onActionError;

  int _nextSinkId = 1;
  final Map<int, StreamController<Object?>> _controllers =
      <int, StreamController<Object?>>{};

  ({int sinkId, Stream<Object?> stream}) createSink() {
    final sinkId = _nextSinkId++;
    late final StreamController<Object?> controller;
    controller = StreamController<Object?>(
      onCancel: () {
        _controllers.remove(sinkId);
      },
    );
    _controllers[sinkId] = controller;
    return (sinkId: sinkId, stream: controller.stream);
  }

  void handleAction(
    String actionRequestId,
    int sinkId,
    String action,
    String? payloadJson,
  ) {
    final controller = _controllers[sinkId];
    if (controller == null || controller.isClosed) {
      _onActionError(actionRequestId, 'QuickJS sink $sinkId is not available');
      return;
    }

    try {
      switch (action) {
        case 'emit':
          final decoded = payloadJson == null
              ? null
              : decodeCallbackWireValue(jsonDecode(payloadJson));
          controller.add(decoded);
        case 'close':
          unawaited(controller.close());
          _controllers.remove(sinkId);
        case 'error':
          controller.addError(payloadJson ?? 'QuickJS sink error');
          unawaited(controller.close());
          _controllers.remove(sinkId);
        default:
          _onActionError(
            actionRequestId,
            'Unknown QuickJS sink action: $action',
          );
          return;
      }
      _onActionComplete(actionRequestId);
    } catch (error) {
      _onActionError(actionRequestId, '$error');
    }
  }

  void dispose() {
    for (final controller in _controllers.values) {
      if (!controller.isClosed) {
        unawaited(controller.close());
      }
    }
    _controllers.clear();
  }
}
