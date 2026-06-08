sealed class QuickjsException implements Exception {
  String get message;
}

final class JsTimeoutException implements QuickjsException {
  const JsTimeoutException([this.message = 'QuickJS evaluation timed out']);

  @override
  final String message;

  @override
  String toString() => message;
}

final class JsCancelledException extends StateError
    implements QuickjsException {
  JsCancelledException([String message = 'QuickJS evaluation was cancelled'])
    : super(message);
}

final class JsRuntimeClosedException extends StateError
    implements QuickjsException {
  JsRuntimeClosedException([String message = 'QuickJS runtime is closed'])
    : super(message);
}
