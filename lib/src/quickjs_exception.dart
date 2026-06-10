/// QuickJS 插件对外暴露的异常基类。
sealed class QuickjsException implements Exception {
  String get message;
}

/// JavaScript 代码主动 throw 或求值异常时的错误。
final class JsException implements QuickjsException {
  const JsException(
    this.message, {
    this.stack,
    this.fileName,
    this.line,
    this.column,
  });

  @override
  final String message;
  final String? stack;
  final String? fileName;
  final int? line;
  final int? column;

  @override
  String toString() => message;
}

/// `evaluateValue()` 遇到无法直接映射为 Dart 值的 JS 值。
final class JsValueConversionException implements QuickjsException {
  const JsValueConversionException([
    this.message = 'QuickJS value cannot be converted to a Dart value',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行超过调用方指定的 timeout。
final class JsTimeoutException implements QuickjsException {
  const JsTimeoutException([this.message = 'QuickJS evaluation timed out']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行被 `stop()` 或后续取消机制中断。
final class JsCancelledException implements QuickjsException {
  const JsCancelledException([
    this.message = 'QuickJS evaluation was cancelled',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 已经关闭后继续调用 API。
final class JsRuntimeClosedException implements QuickjsException {
  const JsRuntimeClosedException([this.message = 'QuickJS runtime is closed']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime worker 崩溃或异常退出。
final class JsRuntimeCrashException implements QuickjsException {
  const JsRuntimeCrashException([
    this.message = 'QuickJS runtime worker crashed',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 分配内存超过配置限制。
final class JsOutOfMemoryException implements QuickjsException {
  const JsOutOfMemoryException([
    this.message = 'QuickJS runtime out of memory',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 调用栈超过配置限制。
final class JsStackOverflowException implements QuickjsException {
  const JsStackOverflowException([
    this.message = 'QuickJS runtime stack overflow',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}
