import 'dart:async';

/// Shared runtime contract for native and web backends.
///
/// `JsEngine` schedules work through this interface and does not expose backend
/// implementation details to the public API.
abstract class JsJsRuntimeBase {
  /// Evaluates JavaScript in the current runtime.
  Future<String> evaluate(
    String code, {
    Duration? timeout,
    String name = '<eval>',
  });

  /// Evaluates JavaScript that returns a Promise in the current runtime.
  Future<String> evaluateAsync(
    String code, {
    Duration? timeout,
    String name = '<run>',
  });

  /// Evaluates [source] as an ES module in the current runtime.
  Future<String> evaluateModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  });

  /// Binds a host callback; in-isolate native calls preserve values/Futures.
  Future<void> bindCallback(
    int callbackId,
    String name,
    FutureOr<Object?> Function(List<Object?> args) callback,
  );

  /// Removes a host callback from the runtime registry.
  Future<void> unbindCallback(int callbackId);

  /// Binds a `{ emit, close, error }` sink on JS `globalThis`.
  Future<Stream<Object?>> bindJsSink(String name);

  /// Attempts to stop the currently running runtime task.
  Future<void> stop();

  /// Releases resources owned by the current runtime.
  Future<void> dispose();
}

/// Optional backend capability for multiple isolated JS contexts in one runtime.
abstract interface class JsMultiContextRuntimeBase {
  Future<int> createContext();

  Future<String> evaluateContext(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<context-eval>',
  });

  Future<String> evaluateModuleContext(
    int contextId,
    String source, {
    required String name,
    Map<String, String> modules = const {},
  });

  Future<void> bindContextCallback(
    int contextId,
    int callbackId,
    String name,
    FutureOr<Object?> Function(List<Object?> args) callback,
  );

  Future<String> evaluateContextAsync(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<context-run>',
  });

  /// Runs timers due in [contextId] and returns the next delay in milliseconds.
  /// A null result means that the context has no scheduled timer.
  Future<int?> pumpContextTimers(int contextId);

  Future<void> unbindContextCallback(int contextId, int callbackId);

  Future<Stream<Object?>> bindContextJsSink(int contextId, String name);

  Future<void> disposeContext(int contextId);
}

/// Marker for a child-context adapter that can accept features in place.
abstract interface class JsInPlaceFeaturesRuntime {}

abstract interface class JsTimerRuntimeBase {
  Future<int?> pumpTimers();
}

/// Synchronous execution on an in-isolate backend.
abstract interface class JsSyncRuntimeBase {
  bool get supportsSync;
  String evaluateSync(String code, {Duration? timeout, String name = '<eval>'});
}

abstract interface class JsSyncMultiContextRuntimeBase {
  String evaluateContextSync(
    int contextId,
    String code, {
    Duration? timeout,
    String name = '<eval>',
  });
}

/// Calls the installed codec directly, without compiling source per invocation.
abstract interface class JsInvocationRuntimeBase {
  Future<String> invoke(
    String requestJson, {
    bool awaitResult = false,
    Duration? timeout,
  });
  String invokeSync(String requestJson, {Duration? timeout});
}

abstract interface class JsMultiContextInvocationRuntimeBase {
  Future<String> invokeContext(
    int contextId,
    String requestJson, {
    bool awaitResult = false,
    Duration? timeout,
  });
  String invokeContextSync(
    int contextId,
    String requestJson, {
    Duration? timeout,
  });
}
// ignore_for_file: public_member_api_docs
