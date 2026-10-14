import '../backend/backend.dart';
import '../runtime/runtime_base.dart';
import '../runtime/runtime_options.dart';
import 'native_runtime.dart';

/// mobile / desktop 平台使用的 FFI backend。
///
/// Runtime 默认在当前 isolate 执行，也可显式使用独立 worker。
class NativeJsBackend implements JsBackend {
  String _engineVersion = 'unknown';

  @override
  String get engineVersion => _engineVersion;

  @override
  Future<JsJsRuntimeBase> createRuntime(JsOptions options) async {
    if (options.execution == JsExecution.workerIsolate) {
      final runtime = await NativeJsWorkerRuntime.create(options: options);
      _engineVersion = runtime.engineVersion;
      return runtime;
    }
    final runtime = await NativeJsLocalRuntime.create(options: options);
    _engineVersion = runtime.engineVersion;
    return runtime;
  }
}
