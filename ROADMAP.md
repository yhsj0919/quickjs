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

6. JS API 形状与底层实现解耦。
   允许通过宿主能力注入，在不改变业务 JS 写法的前提下替换高开销 JS API 的底层实现，
   例如 crypto、hash、压缩、编解码等；也允许在 native / 桌面端按需注入浏览器或 Node
   风格兼容对象，例如 `window`、`location`、`navigator`、`localStorage`、`process.env`、
   `Buffer` 等。用户侧 JS 调用方式应保持稳定；注入范围、权限配置、runtime 隔离和
   native / web 一致性测试必须约束替换与补齐策略。

7. 公开 API 只保留 `Quickjs` 一个系统入口。
   创建、执行、停止、销毁都从 `Quickjs` 实例进入，不要求用户直接管理底层 runtime。

8. 每个新功能同步补 example 页面和测试。
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
  `JsException`、`JsValueConversionException`、`JsTimeoutException`、
  `JsCancelledException`、`JsRuntimeClosedException`、`JsRuntimeCrashException`。
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
- [x] `evaluateValue()` 已支持 JS primitives 到 Dart 值：number、boolean、string、
  null、undefined、bigint、array、plain object、ArrayBuffer、Uint8Array。
- [x] `evaluateValue()` 对循环引用、symbol、function 等不可直接转换值会抛出
  `JsValueConversionException`。
- [x] `eval()` / `evaluate()` / `evaluateValue()` 支持通过 `globals` 临时注入 Dart
  值：int、double、bool、String、null、Uint8List、List、Map、DateTime。
- [x] JS exception 已结构化为 `JsException.message/name/stack/fileName/line/column`；
  eval 场景下 location 字段按 native / web 底层能力 nullable 暴露。
- [x] example 已覆盖 basic eval、async API、runtime worker、queue/reentry、
  runtime isolation、exception model、resource limit、structured values、callback bridge、
  timer/event-loop 页面入口；其中 exception model 页面已覆盖基础错误类型与 `JsException`
  结构化字段展示。
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
  - ready / running / stopping / closed / failed 的可观察状态转换已有确定性测试覆盖。
  - closed / dispose / queue / stop / crash 语义已有测试。
  - `creating` 阶段的实际可观测创建流程仍待补。

- [~] 错误模型
  - timeout、cancel、closed、基础 JS throw 映射已覆盖。
  - JS exception 的 message/name/stack/fileName/line/column 已结构化；eval 场景下
    location 字段可能为空。
  - exception model example 已显式展示 `JsException` 的 name、message、stack、fileName、
    line、column。
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

- [x] number
- [x] boolean
- [x] string
- [x] null
- [x] undefined
- [x] BigInt
- [x] array
- [x] plain object
- [x] ArrayBuffer / Uint8Array
- [x] 循环引用、symbol、function 等不可直接转换值返回明确错误或 handle。

### Dart 到 JS

- [x] int
- [x] double
- [x] bool
- [x] String
- [x] null
- [x] Uint8List
- [x] List
- [x] Map<String, Object?>
- [x] DateTime
- [x] `eval(..., globals: {...})`

### 结构化 JS 异常

- [x] message
- [x] stack
- [x] name
- [x] fileName
- [x] line
- [x] column
- [x] example 中显式展示 `JsException.name/message/stack/fileName/line/column`。

说明：`fileName` / `line` / `column` 按 native QuickJS 与 web quickjs-wasi 底层能力
nullable 暴露；`eval` 场景不强制保证所有位置字段都存在。

## 0.5.0：callback、Promise 与事件循环

目标：Dart 与 JS 可以稳定互调，并支持异步任务。由于 native / web 都在 worker
中执行 JS，主 isolate 的 Dart 闭包不能被 JS 同步调用并立即返回值；因此 0.5.0
优先实现 Promise-based callback bridge，同步 callback 仅作为后续可选能力评估。

- [x] Promise-based Dart function 注入：`engine.bind(...)`，JS 侧调用返回 Promise。
- [x] Dart callback 参数映射：native / web 已覆盖 JSON-compatible primitives、array、plain object、
  ArrayBuffer、Uint8Array。
- [x] Dart callback 返回值映射为 JS Promise resolve 值：native / web 已覆盖 JSON-compatible 值与
  `Uint8List -> Uint8Array`。
- [x] Dart callback 抛错映射为 JS Promise reject / JS exception。
- [x] native `JS_ExecutePendingJob` job pump。
- [x] Web quickjs-wasi Promise job pump 对齐。
- [~] `evalAsync` 支持：native / web 已支持 async 函数体语义；top-level await 待补。
- [x] dispose runtime 时取消 pending callback 和未完成 Promise。
- [x] callback runtime 隔离：绑定只在所属 `Quickjs` 实例内有效。
- [x] callback example 页面：绑定 Dart 函数，JS `await` 调用并展示返回值和错误。
- [x] timer/event-loop example 页面：展示 `setTimeout`、`clearTimeout`、`setInterval`
  与 Promise job pump。
- [x] `setTimeout` / `clearTimeout` / `setInterval` / `clearInterval`。
- [ ] 同步 callback 返回值映射：仅在不破坏 worker 隔离模型时评估实现。

## 0.5.1：流式 callback 与增量结果

目标：在 Promise-based callback bridge 稳定后，支持长任务的增量数据回传与取消。
该能力依赖 0.5.0 的 callback、Promise job pump、timer 和 dispose cancellation，
因此放在 module 阶段之前实现。

- [x] Dart `Stream<T>` 返回值映射：JS 侧获得 async iterable，可通过
  `for await (...)` 消费增量结果。
- [x] JS sink callback 映射：Dart 侧提供 `emit(value)` / `close()` / `error(e)`
  语义，JS 可多次向 Dart 推送进度或分片。
- [x] stream payload 映射复用 callback codec：JSON-compatible 值与
  `Uint8List` / `Uint8Array`。
- [x] backpressure 策略：先实现串行 await ack，避免 worker message 队列无界增长。
- [x] cancel / dispose 语义：JS 停止消费、runtime dispose、Dart stream cancel
  都必须释放 pending stream 与 timer / callback 资源。
- [x] native / web 一致性测试：多 chunk、错误、取消、runtime 隔离。
- [x] 验收：JS 使用标准事件循环每秒向 Dart 推送一个递增数字：
  `await new Promise(resolve => setTimeout(resolve, 1000)); await progress.emit(++n);`；
  推送期间同 runtime 的其他异步 job / callback 不应被 pending timer 或 pending emit 饿死。
- [x] 事件循环语义文档：timer 不抢占正在运行的同步 JS；长同步 JS 阻塞 timer、Promise
  job 和同 runtime 后续 eval 符合 JS 单线程事件循环语义。
- [x] stream callback example 页面：展示 JS `for await` 消费 Dart stream，以及 JS
  分片推送到 Dart 日志。

## 0.6.0：module 与 asset

目标：支持真实项目脚本组织方式。

- [x] `evalModule(source, name: ...)`
- [x] ES module parse / evaluate：native / web 已支持单个 module source 执行与异常映射。
  - 当前验收使用唯一 module name；同名 module 的缓存、复用与重复执行语义并入
    `module cache` 阶段处理。
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

目标：在基础执行模型稳定后，提供更自然的 JS function / Dart object 访问方式。handle
与 proxy 绑定 runtime，调用走 worker 消息模型，并复用 timeout / cancel 语义。

### JS function handle

从 eval 取得 JS 函数引用，并在 Dart 侧重复调用：

```dart
final add = await engine.evaluateHandle('''
function add(a, b) {
  return a + b
}
add
''');

final result = await add.call([1, 2]);
final slow = await add.call(
  [1, 2],
  timeout: const Duration(seconds: 3),
);
await add.cancel(); // 取消当前 call，语义对齐 eval stop / cancel
```

计划范围：

- [ ] `evaluateHandle()` / 等价 API：从 JS 表达式取得 function handle。
- [ ] `handle.call(args, {timeout})`：通过 runtime worker 执行，支持 timeout / cancel。
- [ ] handle 绑定所属 runtime；跨 runtime 调用返回明确错误。
- [ ] runtime dispose 后 handle 调用返回 closed error。

### Dart object proxy

将 Dart 实例暴露给 JS，按属性 / 方法名桥接：

```dart
final user = User(name: 'Tom');
engine.bindObject('user', user);
```

```js
user.name = 'Jerry'
await user.save()
```

计划范围：

- [ ] `engine.bindObject(name, instance)`：注册 Dart 实例 proxy。
- [ ] property getter / setter。
- [ ] method call（同步与 async method 分开定义语义）。
- [ ] readonly property。
- [ ] async getter / method：JS 侧表现为 Promise。
- [ ] proxy 归属 runtime；dispose 后 JS 访问返回 closed error 或明确异常。

### Dart class / instance binding

支持 JS `new` 构造 Dart 侧管理的实例：

```dart
engine.bindClass<User>('User', User.new);
```

```js
const user = new User('Tom')
```

计划范围：

- [ ] `engine.bindClass<T>(jsName, constructor)`：注册可构造类型。
- [ ] instance id 管理：worker 内维护 instance table，Dart 侧只保存 id，不保存裸对象引用。
- [ ] instance finalizer 仅作兜底清理，不代替显式 dispose / runtime 释放。
- [ ] JS GC 与 Dart GC 关系文档：说明 instance 生命周期、dispose 时批量释放、跨
  runtime 混用的禁止规则。

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

这些能力必须在执行隔离、Promise、module、资源限制稳定之后再做。实现须遵循总体原则
第 6 条：JS API 形状稳定，底层实现可替换；注入能力归属单个 runtime，未启用时返回明确
错误或按文档回退到 JS polyfill。

### 宿主能力注入

- [ ] `Quickjs.create(...)` 支持显式配置宿主模块，例如 crypto 加速、浏览器兼容层。
- [ ] 高开销能力替换：JS 侧仍调用 `crypto.subtle.digest()`、`crypto.randomUUID()` 或
  项目约定的 `hash()` 等 API；native 侧可绑定到 Dart、平台原生库或 FFI；Web 侧优先
  绑定浏览器 Web Crypto 等原生能力。
- [ ] 浏览器兼容对象（可选注入）：`window`、`location`、`navigator`、`localStorage`、
  `sessionStorage` 等；只实现明确声明的最小子集，不伪装成完整浏览器环境。
- [ ] Node 兼容对象（可选注入）：`process.env`、`Buffer`、`setImmediate` 等最小子集。
- [ ] 同步宿主 API 只能绑定确定不会长时间阻塞的实现；耗时实现必须返回 Promise。
- [ ] 权限与可用能力显式配置，不默认暴露平台敏感能力。
- [ ] `window` / `globalThis` / `self` 的别名关系可配置并有文档说明。
- [ ] dispose runtime 后，宿主能力回调不再触发，未完成 Promise 被 reject 或取消。

### 内置与文档

- [ ] npm bundle 支持文档。
- [ ] native / Web Crypto 加速（可通过宿主注入替换默认实现）。
- [ ] `fetch` 最小兼容层：native 使用 Dart `HttpClient`，Web 使用浏览器 fetch。
- [ ] `crypto.randomUUID()`。
- [ ] random bytes。
- [ ] SHA-256。
- [ ] Node `Buffer` 最小兼容层：`Buffer.from`、`Buffer.alloc`、`toString`、
  `Uint8List` 互转。

### 验收

- [ ] 同一份 JS 加密 / hash 代码在纯 JS polyfill、native 加速、Web 原生加速下结果一致。
- [ ] 大数据 SHA-256 使用 native 加速时性能明显优于 QuickJS 内纯 JS 实现，且不阻塞 UI。
- [ ] 依赖 `window.location` 或 `localStorage` 的 JS 在桌面端通过注入能力可运行；未注入
  时返回明确错误。
- [ ] 未启用 host module 时，访问对应能力返回明确错误或按文档回退。

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
- [x] runtime 显式状态机全状态测试。
- [~] memory limit / stack limit 测试。
- [x] exception model example 补齐结构化 `JsException` 字段展示。
- [~] callback / timer / module cache runtime 隔离测试：callback / timer 已覆盖，module cache 待补。
- [ ] example app smoke 自动化测试。
