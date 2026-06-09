sealed class QuickjsException implements Exception {
  String get message;
}

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

final class JsTimeoutException implements QuickjsException {
  const JsTimeoutException([this.message = 'QuickJS evaluation timed out']);

  @override
  final String message;

  @override
  String toString() => message;
}

final class JsCancelledException implements QuickjsException {
  const JsCancelledException([
    this.message = 'QuickJS evaluation was cancelled',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

final class JsRuntimeClosedException implements QuickjsException {
  const JsRuntimeClosedException([this.message = 'QuickJS runtime is closed']);

  @override
  final String message;

  @override
  String toString() => message;
}

final class JsRuntimeCrashException implements QuickjsException {
  const JsRuntimeCrashException([
    this.message = 'QuickJS runtime worker crashed',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}
