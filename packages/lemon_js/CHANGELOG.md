# 更新日志 / Changelog

## Unreleased

### 中文

- 增加 pub 包内的最小可运行示例，覆盖 Runtime 创建、结构化求值和资源释放。

### English

- Added a minimal runnable Pub example covering runtime creation, structured evaluation, and disposal.

## 0.1.1

### 中文

- 新增通用命名空间 KV 接口、SharedPreferencesAsync 默认实现和 `lemon_js/storage` 挂载。
- 新增可复用 `QuickjsHttpSession`，供 Fetch、XHR 和 Axios 共享连接与网络配置。
- 新增调用队列上限和稳定的 `QuickjsException.kind` 框架错误分类。
- 为 Dart/JS 双向值转换统一增加深度和容器数量预算，避免异常值图耗尽 Runtime 栈。
- 重写 README，补充安装、基础执行、Dart/JS 互调、模块、宿主能力和插件最小示例，并修正
  GitHub 文档链接。

### English

- Added a general namespaced KV interface, a default SharedPreferencesAsync implementation, and the
  `lemon_js/storage` mount.
- Added reusable `QuickjsHttpSession` support for sharing connections and network configuration across
  Fetch, XHR, and Axios.
- Added bounded call queues and stable framework error categories through `QuickjsException.kind`.
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
