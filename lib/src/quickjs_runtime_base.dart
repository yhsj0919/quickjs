import 'dart:async';

/// Shared runtime contract for native and web backends.
///
/// `Quickjs` schedules work through this interface and does not expose backend
/// implementation details to the public API.
abstract class QuickjsJsRuntimeBase {
  /// Evaluates JavaScript in the current runtime.
  Future<String> evaluate(String code, {Duration? timeout});

  /// Evaluates JavaScript that returns a Promise in the current runtime.
  Future<String> evaluateAsync(String code, {Duration? timeout});

  /// Evaluates [source] as an ES module in the current runtime.
  Future<String> evaluateModule(
    String source, {
    required String name,
    Map<String, String> modules = const {},
    Duration? timeout,
  });

  /// Binds a Promise-based host callback on JS `globalThis`.
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  );

  /// Removes a Promise-based host callback from the runtime registry.
  Future<void> unbindCallback(int callbackId);

  /// Binds a `{ emit, close, error }` sink on JS `globalThis`.
  Future<Stream<Object?>> bindJsSink(String name);

  /// Attempts to stop the currently running runtime task.
  Future<void> stop();

  /// Releases resources owned by the current runtime.
  Future<void> dispose();
}
