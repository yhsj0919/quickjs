/// Shared runtime interface for native and web backends.
abstract class QuickjsJsRuntimeBase {
  String evaluate(String code);
  void dispose();
}
