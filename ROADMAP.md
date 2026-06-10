# quickjs 开发路线图

当前项目已经完成最小 runtime 闭环：创建 QuickJS runtime、执行一段
JavaScript、释放 runtime，并覆盖 native FFI 与 Web WASM。下一步继续扩展功能前，
需要优先把执行模型、runtime 隔离、错误语义和资源边界固定下来。

## 总体原则

1. UI 线程不直接执行不可控 JS。
   `while (true) {}`、大数组计算、同步 JSON 处理、复杂 bundle 初始化都必须可超时、
   可取消，并且不能冻结 Flutter UI / Web UI thread。

2. 每个 runtime 必须有明确所有权。
   runtime、context、handle、callback、timer、module cache、pending jobs 不能跨
   runtime 混用。

3. 跨边界调用统一异步化。
   Dart API 可以提供便利封装，但底层必须按 request / response / stop / dispose
   的消息模型组织。

4. native 与 web 语义尽量一致。
   native 使用 Dart isolate + FFI worker；web 使用 Web Worker + WASM bridge。
   API 语义保持一致，底层实现允许不同。

5. 先定义失败语义，再扩展功能。
   timeout、interrupt、dispose、OOM、JS exception、worker crash 都必须有稳定错误类型
   和恢复策略。

6. 公开 API 只保留 `Quickjs` 一个系统入口。
   创建、执行、停止、销毁都从 `Quickjs` 实例进入，不要求用户直接管理底层 runtime。

7. 每个新功能同步补 example 页面和测试。
   example 页面必须能独立创建和销毁自己的 `Quickjs` 实例，页面之间不共享 runtime
   状态。

## 当前完成状态

### 已完成

- [x] `Quickjs.create()` / `eval()` / `evaluate()` / `stop()` / `dispose()`
  已异步化。
- [x] native FFI 调用已迁移到 Dart isolate worker。
- [x] Web WASM 调用已迁移到 Web Worker。
- [x] 同一 `Quickjs` 实例内的 eval 请求按 FIFO 串行执行。
- [x] 长耗时 JS 不阻塞 Flutter UI isolate。
- [x] `dispose()` 后继续 eval 会抛出 `JsRuntimeClosedException`。
- [x] `stop()` 可以取消当前 eval，并取消队列中的 eval。
- [x] `eval(timeout:)` 可以触发 `JsTimeoutException`。
- [x] timeout / stop 后同一个 `Quickjs` 实例可以继续 eval。
- [x] 重复 `dispose()`、closed 后 `stop()`、stop 过程中入队 eval 等状态边界已有测试。
- [x] 多 runtime 的基础 global 状态已隔离。
- [x] dispose 一个 runtime 不影响另一个 runtime。
- [x] 基础错误类型已存在：
  `JsException`、`JsTimeoutException`、`JsCancelledException`、
  `JsRuntimeClosedException`、`JsRuntimeCrashException`。
- [x] worker crash 后 pending Future 会完成为 `JsRuntimeCrashException`，后续请求返回
  closed error。
- [x] 公开 `QuickjsRuntimeState` 与 `engine.state`，可观测 ready、running、stopping、
  closed、failed 等生命周期状态。
- [x] memory limit：基于 native `JS_SetMemoryLimit` 与 web `quickjs-wasi`
  `memoryLimit`，超限映射为 `JsOutOfMemoryException`。
- [x] native stack limit：基于 `JS_SetMaxStackSize`，超限映射为
  `JsStackOverflowException`；Web 侧底层暂未暴露等价选项。
- [x] native / web 基础一致性测试已覆盖 eval、throw、FIFO、runtime 隔离、
  timeout、stop、dispose、memory limit、web worker terminate 后的 peer runtime 恢复。
- [x] example 已覆盖 basic eval、async API、runtime worker、queue/reentry、
  runtime isolation、exception model、resource limit 页面。
- [x] 当前 `flutter analyze`、根项目 `flutter test`、`example/flutter test`
  已通过。

### 部分完成

- [~] `timeout`
  - native 使用 `JS_SetInterruptHandler`。
  - web 在同步 WASM 无法中断时 terminate worker 并重建 runtime。
  - web timeout / stop 后 JS global 状态会丢失；已有测试固定 peer runtime 可恢复但
    globals 丢失的语义。

- [~] `stop()`
  - 已取消当前 eval 和队列 eval。
  - 已通过后台重建 runtime 恢复可用状态。
  - 公开 `cancel(requestId)` 尚未实现。

- [~] runtime 状态机
  - `Quickjs` 内部已使用显式 `ready / running / stopping / closed / failed` 状态枚举。
  - `QuickjsRuntimeState` 与 `engine.state` 已公开。
  - closed / dispose / queue / stop / crash 语义已有测试。
  - `creating` 阶段的实际可观测创建流程和更完整的全状态转换测试仍待补。

- [~] 错误模型
  - timeout、cancel、closed、基础 JS throw 映射已覆盖。
  - JS exception 的 stack/name/file/line/column 仍待结构化。
  - worker crash 已有 native 测试覆盖；OOM、stack overflow 仍需专门测试和错误类型映射。

- [~] runtime 隔离
  - globals 与 dispose 隔离已覆盖。
  - callbacks、timers、module cache、handles、resource limits 的隔离仍待实现。

## 0.2.0：执行安全基础

目标：任何 JS 执行都不能阻塞 Flutter UI，并且必须具备可取消、可超时、可释放的基础语义。

### 范围

- [x] 异步 `Quickjs` API。
- [x] native runtime worker isolate。
- [x] Web Worker WASM bridge。
- [x] 单 runtime FIFO 执行队列。
- [x] dispose 取消队列并释放 runtime。
- [x] timeout 基础能力。
- [x] stop 基础能力。
- [x] 基础错误类型。
- [x] runtime 基础隔离测试。
- [x] worker crash 测试。
- [x] native / web 基础行为一致性自动化测试。
- [x] runtime 状态边界测试。

### 验收

- [x] 点击 example 长耗时 JS 页面时 UI 仍可响应。
- [x] 同一 runtime 连续 100 次并发 eval 顺序稳定。
- [x] eval 执行中调用 dispose 不崩溃、不泄漏、不悬挂 Future。
- [x] dispose 取消尚未开始的队列 eval。
- [x] `while (true) {}` 在 timeout 后返回 `JsTimeoutException`。
- [x] `stop()` 能停止当前 eval。
- [x] `stop()` 能取消队列 eval。
- [x] timeout / stop 后 runtime 可恢复使用。
- [x] JS throw 在 Dart 侧是 `JsException`。
- [x] worker crash 后 pending Future 必须完成为 error。
- [x] 重复 dispose、closed 后 stop、stop 过程中入队 eval 不会悬挂。
- [x] native 与 web 对基础 JS 用例的语义保持一致。

## 0.3.0：runtime 隔离与资源边界

目标：多个 runtime 可以同时存在、互不污染，并且资源限制和生命周期状态明确。

### 计划范围

- [~] 完整 runtime 状态机：
  内部 `ready -> running -> stopping -> closed / failed` 已实现并公开状态观测；`creating`
  阶段的实际可观测创建流程待补。
- [~] failed / crash 状态语义。
- [x] memory limit：基于 `JS_SetMemoryLimit`。
- [~] stack limit：native 基于 `JS_SetMaxStackSize`；Web 等价能力待底层支持。
- [ ] handle 所有权规则。
- [~] dispose / crash / failed 状态测试。
- [x] web 多 runtime 在 worker terminate 后的恢复策略。

### 设计约束

- handle 只在所属 runtime 内有效。
- Dart 侧只保存 handle id，不保存裸 `JSValue`。
- native/web worker 内维护 handle table。
- dispose runtime 时释放所有 handle。
- 重复释放 handle 不崩溃。
- runtime dispose 后 handle 调用返回 closed error。

## 0.4.0：结构化结果、类型互转与异常

目标：从字符串 eval 结果升级到结构化 Dart / JS 数据交换。

### JS 到 Dart

- [ ] number
- [ ] boolean
- [ ] string
- [ ] null
- [ ] undefined
- [ ] array
- [ ] plain object
- [ ] ArrayBuffer / Uint8Array
- [ ] 循环引用、symbol、function 等不可直接转换值返回明确错误或 handle。

### Dart 到 JS

- [ ] int
- [ ] double
- [ ] bool
- [ ] String
- [ ] null
- [ ] Uint8List
- [ ] List
- [ ] Map<String, Object?>
- [ ] DateTime
- [ ] `eval(..., globals: {...})`

### 结构化 JS 异常

- [ ] message
- [ ] stack
- [ ] name
- [ ] fileName
- [ ] line
- [ ] column

## 0.5.0：callback、Promise 与事件循环

目标：Dart 与 JS 可以稳定互调，并支持异步任务。

- [ ] Dart function 注入：`engine.bind(...)`。
- [ ] 同步 callback 返回值映射。
- [ ] callback 抛错映射为 JS exception。
- [ ] Dart Future 映射为 JS Promise。
- [ ] Promise resolve / reject 映射。
- [ ] native `JS_ExecutePendingJob` job pump。
- [ ] `evalAsync` / top-level await 支持。
- [ ] `setTimeout` / `clearTimeout` / `setInterval` / `clearInterval`。
- [ ] dispose runtime 时取消 timer 和未完成 Promise。

## 0.6.0：module 与 asset

目标：支持真实项目脚本组织方式。

- [ ] `evalModule(source, name: ...)`
- [ ] ES module parse / evaluate。
- [ ] module cache。
- [ ] relative path resolution。
- [ ] runtime 级 module loader。
- [ ] Flutter `AssetBundle` asset loader。
- [ ] package asset 路径。
- [ ] Web asset URL。
- [ ] 最小 CommonJS 兼容层：
  `require()`、`module.exports`、`exports`、module cache、relative path resolution。

不在 runtime 内实现完整 npm resolver。npm 包优先推荐用户通过 esbuild / Rollup /
webpack 预打包。

## 0.7.0：对象桥接与高级 handle

- [ ] JS function handle。
- [ ] handle 调用支持 timeout / cancel。
- [ ] Dart object proxy。
- [ ] property getter / setter。
- [ ] method call。
- [ ] readonly property。
- [ ] async getter / method。
- [ ] Dart class / instance binding。
- [ ] JS GC 与 Dart GC 关系文档。

## 0.8.0：调试与开发体验

- [ ] `console.log`
- [ ] `console.warn`
- [ ] `console.error`
- [ ] source file name。
- [ ] sourcemap registry。
- [ ] stack remap。
- [ ] debug mode / inspector 原型：
  globals、modules、memory、pending jobs、registered callbacks、手动执行表达式。

## 0.9.0+：生态兼容能力

这些能力必须在执行隔离、Promise、module、资源限制稳定之后再做。

- [ ] npm bundle 支持文档。
- [ ] host capability 注入。
- [ ] native / Web Crypto 加速。
- [ ] `fetch` 最小兼容层。
- [ ] `crypto.randomUUID()`。
- [ ] random bytes。
- [ ] SHA-256。
- [ ] Node `Buffer` 最小兼容层。
- [ ] 可选浏览器兼容对象：`window`、`location`、`navigator`、`localStorage`。
- [ ] 可选 Node 兼容对象：`process.env`、`Buffer`、`setImmediate`。

## 测试策略

### 当前必须保持通过

```powershell
flutter analyze
flutter test
flutter test test\quickjs_consistency_test.dart -d chrome
cd example
flutter test
```

Windows FFI 相关改动后，需要刷新 native DLL：

```powershell
cd example
flutter build windows --debug
flutter build windows
```

### 后续需要补齐

- [x] worker crash 测试。
- [x] native / web 基础一致性测试。
- [x] runtime 状态边界测试。
- [~] runtime 显式状态机全状态测试。
- [~] memory limit / stack limit 测试。
- [ ] callback / timer / module cache runtime 隔离测试。
- [ ] example app smoke 自动化测试。
