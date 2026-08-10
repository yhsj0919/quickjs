import '../backend/quickjs_backend.dart';
import '../runtime/quickjs_runtime_base.dart';
import '../runtime/quickjs_runtime_options.dart';
import 'quickjs_native_worker.dart';

/// mobile / desktop 平台使用的 FFI backend。
///
/// 每次创建 runtime 都会启动一个持有 QuickJS 指针的 Dart isolate worker。
class NativeQuickjsBackend implements QuickjsBackend {
  String _quickjsVersion = 'unknown';

  @override
  String get quickjsVersion => _quickjsVersion;

  @override
  Future<QuickjsJsRuntimeBase> createRuntime(
    QuickjsRuntimeOptions options,
  ) async {
    final runtime = await NativeQuickjsWorkerRuntime.create(options: options);
    _quickjsVersion = runtime.quickjsVersion;
    return runtime;
  }
}
