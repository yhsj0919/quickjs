import 'quickjs_runtime_base.dart';

/// An isolated QuickJS JavaScript runtime.
class QuickjsJsRuntime implements QuickjsJsRuntimeBase {
  QuickjsJsRuntime._(this._delegate);

  final QuickjsJsRuntimeBase _delegate;

  static QuickjsJsRuntime wrap(QuickjsJsRuntimeBase delegate) =>
      QuickjsJsRuntime._(delegate);

  @override
  Future<String> evaluate(String code, {Duration? timeout}) =>
      _delegate.evaluate(code, timeout: timeout);

  @override
  Future<void> stop() => _delegate.stop();

  @override
  Future<void> dispose() => _delegate.dispose();
}
