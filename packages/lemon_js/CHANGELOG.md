# 更新日志

## 0.1.1

- 新增通用命名空间 KV 接口、SharedPreferencesAsync 默认实现和 `lemon_js/storage` 挂载。
- 新增可复用 `QuickjsHttpSession`，供 Fetch、XHR 和 Axios 共享连接与网络配置。
- 新增调用队列上限和稳定的 `QuickjsException.kind` 框架错误分类。
- 为 Dart/JS 双向值转换统一增加深度和容器数量预算，避免异常值图耗尽 Runtime 栈。

## 0.1.0

- 提供 Flutter 原生平台上的 QuickJS FFI 运行时。
- 提供 Flutter Web 的 WASM/Web Worker 运行时。
- 支持 JavaScript 求值、异步任务、Promise、Timer、模块加载和结构化值转换。
- 支持 Dart 函数、对象、类、Stream、插件和宿主能力挂载。
