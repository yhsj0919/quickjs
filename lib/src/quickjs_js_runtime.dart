import 'quickjs_runtime_base.dart';

/// An isolated QuickJS JavaScript runtime.
class QuickjsJsRuntime implements QuickjsJsRuntimeBase {
  QuickjsJsRuntime._(this._delegate);

  final QuickjsJsRuntimeBase _delegate;

  static QuickjsJsRuntime wrap(QuickjsJsRuntimeBase delegate) =>
      QuickjsJsRuntime._(delegate);

  @override
  Future<String> evaluate(String code) => _delegate.evaluate(code);

  @override
  Future<void> dispose() => _delegate.dispose();
}
