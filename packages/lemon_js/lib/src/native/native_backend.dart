import '../backend/backend.dart';
import '../runtime/runtime_base.dart';
import '../runtime/runtime_options.dart';
import 'native_worker.dart';

/// mobile / desktop 平台使用的 FFI backend。
///
/// 每次创建 runtime 都会启动一个持有 QuickJS 指针的 Dart isolate worker。
class NativeJsBackend implements JsBackend {
  String _engineVersion = 'unknown';

  @override
  String get engineVersion => _engineVersion;

  @override
  Future<JsJsRuntimeBase> createRuntime(JsOptions options) async {
    final runtime = await NativeJsWorkerRuntime.create(options: options);
    _engineVersion = runtime.engineVersion;
    return runtime;
  }
}
