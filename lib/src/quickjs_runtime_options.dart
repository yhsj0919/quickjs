/// 创建 QuickJS runtime 时使用的资源边界配置。
final class QuickjsRuntimeOptions {
  const QuickjsRuntimeOptions({this.memoryLimitBytes, this.stackLimitBytes});

  /// 单个 runtime 可使用的最大内存，单位是字节。
  ///
  /// 例如 `1024 * 1024` 表示 1 MiB，`16 * 1024 * 1024` 表示 16 MiB。
  /// 这个限制只作用于当前 `Quickjs` 实例底层的单个 QuickJS runtime；
  /// 多个 `Quickjs` 实例不会共享同一个限制计数。
  ///
  /// `null` 表示使用 QuickJS 默认限制。执行中超过限制时，Dart 侧会抛出
  /// `JsOutOfMemoryException`。
  final int? memoryLimitBytes;

  /// 单个 runtime 可使用的最大调用栈大小，单位是字节。
  ///
  /// 例如 `64 * 1024` 表示 64 KiB。这个限制只作用于当前 `Quickjs` 实例
  /// 底层的单个 QuickJS runtime。
  ///
  /// `null` 表示使用 QuickJS 默认限制。native 侧基于 `JS_SetMaxStackSize`；
  /// Flutter Web 当前底层 `quickjs-wasi` 没有暴露等价选项，因此该参数暂不影响
  /// Web runtime。执行中超过限制时，Dart 侧会抛出 `JsStackOverflowException`。
  final int? stackLimitBytes;
}
