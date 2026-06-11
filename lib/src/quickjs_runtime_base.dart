import 'dart:async';

/// native 与 web runtime 的最小公共接口。
///
/// `Quickjs` 只通过这个接口调度执行、停止和释放，不直接接触平台细节。
abstract class QuickjsJsRuntimeBase {
  /// 在当前 runtime 中执行 JS。
  Future<String> evaluate(String code, {Duration? timeout});

  /// 在当前 runtime 中执行返回 Promise 的 JS。
  Future<String> evaluateAsync(String code, {Duration? timeout});

  /// 在当前 runtime 的 JS globalThis 上绑定一个 Promise-based host callback。
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  );

  /// 在当前 runtime 的 JS globalThis 上绑定 `{ emit, close, error }` sink。
  Future<Stream<Object?>> bindJsSink(String name);

  /// 尝试停止当前 runtime 中正在执行的任务。
  Future<void> stop();

  /// 释放当前 runtime 持有的底层资源。
  Future<void> dispose();
}
