import 'quickjs_runtime_base.dart';

/// QuickJS 的平台 backend 抽象。
///
/// 上层只依赖创建 runtime 的能力，具体执行模型由 native/web 实现决定。
abstract class QuickjsBackend {
  /// 当前 backend 打包的 QuickJS 版本号。
  String get quickjsVersion;

  /// 创建一个隔离的 JavaScript runtime。
  Future<QuickjsJsRuntimeBase> createRuntime();
}
