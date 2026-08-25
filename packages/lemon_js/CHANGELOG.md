# 更新日志 / Changelog

## 0.3.0

### 中文

- 新增实验性 OpenHarmony FFI 适配，包括 OHOS 插件声明、`libquickjs.so` 动态加载和
  HarmonyOS 交叉编译所需的 CMake 配置。
- 新增 OHOS example 宿主工程，以及分别构建 ARM64 真机和 x64 模拟器 HAP、校验
  QuickJS FFI 导出符号的手动 CI 工作流。
- 补充 CPF Flutter 与 HarmonyOS SDK 的环境配置、构建方式和支持边界，记录 API 24
  自动填充编译冲突、第三方插件 ABI 及 x64 视频 Surface 等已知兼容问题。

### English

- Added experimental OpenHarmony FFI integration, including the OHOS plugin declaration,
  `libquickjs.so` loading, and CMake handling required by the HarmonyOS cross toolchain.
- Added an OHOS example host and a manually triggered CI workflow that builds ARM64 device and x64
  emulator HAPs and verifies the exported QuickJS FFI symbol.
- Documented the CPF Flutter and HarmonyOS SDK setup, build steps, and support boundaries, including
  known API 24 autofill compilation, third-party ABI, and x64 video Surface compatibility issues.

## 0.2.1

### 中文

- iOS 和 macOS 改为共享的 Swift Package Manager 集成，并修复 Apple 平台 Release
  构建中 QuickJS FFI 符号未链接的问题。
- 增加 Android、iOS、Linux、macOS、Web 和 Windows 的示例构建与启动验证，覆盖应用
  首帧、进程存活及启动诊断。
- 新增宿主平台配置文档，说明 Apple、Android、Linux、Windows 和 Web 引用插件时所需的
  构建依赖与工程设置。

### English

- Migrated iOS and macOS to a shared Swift Package Manager integration and fixed missing QuickJS FFI
  symbols in Apple release builds.
- Added example build and launch validation for Android, iOS, Linux, macOS, Web, and Windows, covering
  first-frame rendering, process liveness, and startup diagnostics.
- Added host-platform setup documentation for the build dependencies and project configuration required
  when integrating the plugin on Apple, Android, Linux, Windows, and Web.

## 0.2.0

### 中文

- **破坏性更新：** 本次重构系统性调整了公开 API、类型名、参数名和导入入口，且不提供
  旧名称兼容别名。升级前必须按照
  [破坏性 API 迁移指南](../../docs/breaking_api_migration.md) 修改调用代码。
- 主入口改为 `JsEngine`；多 Context 的 `JsRuntime` / `JsContext` 移至
  `package:lemon_js/lemon_js_context.dart`。
- 执行 API 统一为 `eval/evalRaw`、`run/runRaw`、`runModule`、`runCommonJs` 和
  `call/callRaw/callModule`。
- Dart → JavaScript 统一使用 `inject*`，JavaScript → Dart 统一使用 `bind*`；删除
  `JsFunctionHandle.cancel()`。
- 原 Mount/Capabilities 模型统一为 `JsFeatures`、`features` 和 `loadFeatures()`；内置能力
  统一使用 `*Features` 类型。
- 插件、脚本、模块、资源路径、队列限制及 KV Store 的公开名称已统一；其中 KV 实现改为
  `JsMemoryKvStore` 和 `JsSharedPreferencesKvStore`。
- 平台插件壳统一为 `LemonJsPlugin` / `lemon_js_plugin`，Android namespace 改为
  `xyz.yhsj.lemon_js`。
- 修复 WebSocket host script 调用错误事件方法导致连接 Promise 永久等待的问题。
- 增加 pub 包内的最小可运行示例，覆盖 Engine 创建、结构化求值和资源释放。

### English

- **Breaking update:** This refactor systematically changes public APIs, type names, parameter names, and
  import entry points. No compatibility aliases are provided. Update consumers using the
  [breaking API migration guide](../../docs/breaking_api_migration.md) before upgrading.
- Replaced the primary entry point with `JsEngine`; the multi-context `JsRuntime` / `JsContext` API now
  lives in `package:lemon_js/lemon_js_context.dart`.
- Standardized execution on `eval/evalRaw`, `run/runRaw`, `runModule`, `runCommonJs`, and
  `call/callRaw/callModule`.
- Standardized Dart-to-JavaScript interop on `inject*` and JavaScript-to-Dart interop on `bind*`, and
  removed `JsFunctionHandle.cancel()`.
- Replaced the Mount/Capabilities model with `JsFeatures`, `features`, and `loadFeatures()`; built-in
  capabilities now use `*Features` types.
- Standardized plugin, script, module, resource-path, queue-limit, and KV Store names, including
  `JsMemoryKvStore` and `JsSharedPreferencesKvStore`.
- Renamed platform plugin shells to `LemonJsPlugin` / `lemon_js_plugin` and changed the Android namespace
  to `xyz.yhsj.lemon_js`.
- Fixed a WebSocket host-script event dispatch error that left connection promises pending indefinitely.
- Added a minimal runnable Pub example covering engine creation, structured evaluation, and disposal.

## 0.1.1

### 中文

- 新增通用命名空间 KV 接口、SharedPreferencesAsync 默认实现和 `lemon_js/storage` 挂载。
- 新增可复用 `JsHttpSession`，供 Fetch、XHR 和 Axios 共享连接与网络配置。
- 新增调用队列上限和稳定的 `JsException.kind` 框架错误分类。
- 为 Dart/JS 双向值转换统一增加深度和容器数量预算，避免异常值图耗尽 Runtime 栈。
- 重写 README，补充安装、基础执行、Dart/JS 互调、模块、宿主能力和插件最小示例，并修正
  GitHub 文档链接。

### English

- Added a general namespaced KV interface, a default SharedPreferencesAsync implementation, and the
  `lemon_js/storage` mount.
- Added reusable `JsHttpSession` support for sharing connections and network configuration across
  Fetch, XHR, and Axios.
- Added bounded call queues and stable framework error categories through `JsException.kind`.
- Added shared depth and container-count budgets for Dart/JS value conversion to prevent malformed value
  graphs from exhausting the runtime stack.
- Reworked the README with installation, evaluation, Dart/JS interop, modules, host capabilities, and plugin
  examples, and corrected GitHub documentation links.

## 0.1.0

### 中文

- 提供 Flutter 原生平台上的 QuickJS FFI 运行时。
- 提供 Flutter Web 的 WASM/Web Worker 运行时。
- 支持 JavaScript 求值、异步任务、Promise、Timer、模块加载和结构化值转换。
- 支持 Dart 函数、对象、类、Stream、插件和宿主能力挂载。

### English

- Added the QuickJS FFI runtime for native Flutter platforms.
- Added the WASM/Web Worker runtime for Flutter Web.
- Added JavaScript evaluation, asynchronous jobs, Promises, timers, module loading, and structured value
  conversion.
- Added Dart function, object, class, stream, plugin, and host capability bindings.
