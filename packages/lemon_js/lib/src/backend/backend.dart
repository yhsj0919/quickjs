import '../runtime/runtime_base.dart';
import '../runtime/runtime_options.dart';

/// QuickJS 的平台 backend 抽象。
///
/// 上层只依赖创建 runtime 的能力，具体执行模型由 native/web 实现决定。
abstract class JsBackend {
  /// 当前 backend 打包的 QuickJS 版本号。
  String get engineVersion;

  /// 创建一个隔离的 JavaScript runtime。
  Future<JsJsRuntimeBase> createRuntime(JsOptions options);
}
