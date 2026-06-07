/// Shared runtime interface for native and web backends.
abstract class QuickjsJsRuntimeBase {
  Future<String> evaluate(String code);
  Future<void> dispose();
}
