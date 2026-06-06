import 'quickjs_runtime_base.dart';

/// Platform backend for QuickJS.
abstract class QuickjsBackend {
  /// QuickJS version bundled with this plugin.
  String get quickjsVersion;

  /// Creates an isolated JavaScript runtime.
  Future<QuickjsJsRuntimeBase> createRuntime();

  /// Evaluates [code] in a short-lived runtime.
  Future<String> evaluate(String code);
}
