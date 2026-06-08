import '../quickjs_backend.dart';
import '../quickjs_runtime_base.dart';
import 'quickjs_native_worker.dart';

/// FFI backend for mobile and desktop.
class NativeQuickjsBackend implements QuickjsBackend {
  String _quickjsVersion = 'unknown';

  @override
  String get quickjsVersion => _quickjsVersion;

  @override
  Future<QuickjsJsRuntimeBase> createRuntime() async {
    final runtime = await NativeQuickjsWorkerRuntime.create();
    _quickjsVersion = runtime.quickjsVersion;
    return runtime;
  }

  @override
  Future<String> evaluate(String code, {Duration? timeout}) async {
    final runtime = await createRuntime();
    try {
      return await runtime.evaluate(code, timeout: timeout);
    } finally {
      await runtime.dispose();
    }
  }
}
