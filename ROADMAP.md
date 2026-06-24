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
- [x] `Quickjs.create(onConsole:)` 支持接收 `console.log` / `console.warn` /
  `console.error` 事件；未配置 sink 时默认注入 no-op console。
- [x] JS exception 已结构化为 `JsException.message/name/stack/fileName/line/column`；
  eval 场景下 location 字段按 native / web 底层能力 nullable 暴露。
- [x] example 已覆盖 basic eval、async API、runtime worker、queue/reentry、
  runtime isolation、exception model、resource limit、structured values、callback bridge、
  timer/event-loop、stream callback、module、host modules、function handle、object proxy、class binding、
  console 页面入口；其中 exception model 页面已覆盖基础错误类型与 `JsException`
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
  - 已覆盖静态 import 依赖加载、相对路径解析与 imported module cache 复用。
- [x] module cache。
- [x] relative path resolution。
- [x] runtime 级 module loader。
- [x] Flutter `AssetBundle` asset loader。
- [x] package asset 路径。
- [x] Web asset URL。
- [x] 最小 CommonJS 兼容层：
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

- [x] `evaluateHandle()` / 等价 API：从 JS 表达式取得 function handle。
- [x] `handle.call(args, {timeout})` / `handle.callAsync(args, {timeout})`：通过 runtime worker 执行，支持 timeout / cancel。
  `call` 保留同步 interrupt 语义；`callAsync` await Promise-returning function。
- [x] `callAsync` timeout 语义已文档化：覆盖 Promise pending 阶段；返回 Promise 前的同步长任务应使用 `call`。
- [x] handle 绑定所属 runtime；跨 runtime 调用返回明确错误。
- [x] `handle.dispose()` 显式释放 runtime 内 function registry entry；重复释放不报错。
- [x] runtime dispose 后 handle 调用返回 closed error。

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

- [x] `engine.bindObject(name, proxy)`：通过显式 `QuickjsObjectProxy` descriptor 注册 Dart proxy。
- [x] property getter / setter：支持显式 `QuickjsObjectAccessor` descriptor；getter 在 JS 侧表现为 Promise，setter 通过 callback 派发。
- [x] method call（同步与 async method 分开定义语义）：method 走 Promise callback bridge。
- [x] readonly property。
- [x] async getter / method：method 与 getter 已表现为 Promise；setter assignment 不返回 Promise（JS accessor 语义限制）。
- [x] proxy 归属 runtime；dispose 后新绑定返回 closed error，已绑定 JS proxy 随 runtime 释放，泄漏 proxy/method/accessor 引用会返回明确 disposed error。
- [x] `QuickjsObjectHandle.dispose()`：显式删除 JS global proxy 和隐藏 method/accessor callback globals；重复释放不报错。
- [x] runtime-level callback unregister：proxy dispose 后即使 JS 持有泄漏的 method/accessor 引用，也不能再触发 Dart callback。

### Dart class / instance binding

支持 JS `new` 构造 Dart 侧管理的实例：

```dart
engine.bindClass<User>('User', User.new);
```

```js
const user = new User('Tom')
```

计划范围：

- [x] `engine.bindClass<T>(jsName, constructor)`：通过显式 `QuickjsClass<T>` descriptor 注册可构造类型。
- [x] instance id 管理：JS 侧 instance proxy 只保存 id，Dart 侧按 runtime/class 维护 instance table。
- [-] instance finalizer：暂不实现；当前版本只承诺显式 `QuickjsClassHandle.dispose()` / `Quickjs.dispose()` / runtime rebuild 清理，
  JS GC 不驱动 Dart instance 回收。
- [x] JS GC 与 Dart GC 关系文档：`docs/class_binding_lifecycle.md` 已说明 instance 生命周期、dispose 批量释放、跨 runtime 混用禁止规则，
  以及当前不承诺 JS GC 驱动 Dart instance 回收。

## 0.8.0：调试与开发体验

- [x] `console.log`
- [x] `console.warn`
- [x] `console.error`
- [x] source file name：`eval` / `evaluate` / `evalAsync` / `evaluateAsync` /
  `evaluateValue` / `evaluateHandle` 支持 `name:`，native 与 web 异常栈可指向该 source name。
- [x] sourcemap registry：`QuickjsSourceMap` 与 runtime 级注册表已支持按 source name
  注册、查询、清理，并在匹配的 `JsException.sourceMap` 上附加元数据；stack 重写留给下一步。
- [x] stack remap：注册 sourcemap 后，匹配 source name 的 `JsException.stack` 会重写为原始
  source 位置，并同步更新 `fileName` / `line` / `column`。
- [x] debug mode / inspector 原型：`debugInspect()` 可快照 globals、module names、
  resource limits、pending evals、registered callbacks、source maps；`debugEvaluateValue()`
  支持手动执行表达式。当前为 API 原型，非交互式 inspector UI。

## 0.9.0：生态兼容能力

这些能力必须在执行隔离、Promise、module、资源限制稳定之后再做。实现须遵循总体原则
第 6 条：JS API 形状稳定，底层实现可替换；注入能力归属单个 runtime，未启用时返回明确
错误或按文档回退到 JS polyfill。

### 能力分级

- Core required：Promise job pump、async/await、module cache / resolver 基础、structured value
  codec、exception model、stop / dispose / runtime rebuild 生命周期。这些是执行模型的一部分，
  不做成可选 host environment。
- Core default：no-op `console.log` / `console.warn` / `console.error`、source name / stack 信息、
  debug inspect 原型。默认可用；配置 `onConsole` 后才把日志转发到 Flutter。
- Opt-in host environment：`fetch`、`window` / `location` / `navigator` / storage、Web Crypto、
  Node `Buffer` / `crypto` / `path`、文件系统、网络和平台能力。默认不暴露。

### 宿主能力模型

0.9.0 的核心不是继续内置 `fetch`、`Buffer`、`crypto` 等具体 API，而是建立一套可组合的
宿主环境注入模型。框架只提供生命周期、隔离、安装顺序、模块解析、回调桥接和错误语义；
具体能力优先由用户注入。框架可以提供少量预制包作为示例和常用组合，但预制包必须仍然走同一套
注入接口，不能成为写死在 `quickjs.dart` 里的特殊能力。

宿主能力按语义分为四类：

- [x] 环境补全：创建 runtime 后安装 `globalThis` 上的对象、alias 或 polyfill，例如
  `window`、`self`、`location`、`navigator`、storage、`crypto`、`fetch`。当前由
  `QuickjsRuntimeOptions.environmentPatches`、`hostCapabilities` 和 `QuickjsHostMount.web()`
  承载，并会在 stop 重建 runtime 后重新安装。`QuickjsHostScript.globals` 可显式声明脚本安装的
  global，供初始化及运行时 mount 在重建前检测冲突。
- [x] 模块加载：按 specifier 注册 ES module / CommonJS module，只有 JS 侧 `import` / `require`
  时才加载，不自动污染 `globalThis`。当前由 `QuickjsRuntimeOptions.modules` 和
  `QuickjsHostModule.esModule/commonJs` 承载。
- [~] 方法注入 / provider：注册由 Dart/Flutter、JS 或平台能力实现的函数入口。provider 本身不决定
  JS API 形状；JS 侧由环境补全脚本或 host module 包装成标准 API。当前已支持 async Dart/Flutter
  provider、Promise 映射、debug 可见性和 runtime 隔离；JS provider、worker-local sync provider
  与更完整的取消语义后续补齐。
- [~] 批量挂载 / bundle：把环境补全、模块加载、方法注入组合成一个可复用能力包，例如 `web()`、
  `node()`、`essential()`、`webCrypto()` 或用户自定义业务能力包。preset 不是功能扩展的唯一入口；
  用户应能用同样的底层接口注入框架没有预置的模块或 global API。

推荐术语与现有 API 对照：

| 语义 | 推荐命名 | 当前 API |
| --- | --- | --- |
| 环境补全 | `environmentPatches` / `QuickjsEnvironmentPatch` | `environmentPatches` / `QuickjsHostScript` |
| 模块加载 | `modules` / `QuickjsModuleDefinition` | `modules` / `QuickjsHostModule` |
| 方法注入 | `methods` / `QuickjsInjectedMethod` 或 `providers` / `QuickjsHostProvider` | `providers` / `QuickjsHostProvider` |
| 批量挂载 | `mounts` / `QuickjsHostMount` | `mounts` / `QuickjsHostMount` |

当前版本允许破坏性 API 调整：旧 `QuickjsHostEnvironment` / `hostEnvironments` 已删除，所有 preset、
示例和测试统一迁移到 `QuickjsHostMount` / `mounts`。其余低层字段是否改名，以实际可读性为准，
不再为了旧代码保留重复入口。

provider 实现类型只描述能力来源，不改变 JS API 形状：

- JS provider：实现完全运行在 QuickJS 内，适合纯 JS polyfill、同步短耗时函数和不需要平台能力的逻辑。
- Dart/Flutter provider：通过 callback bridge 进入宿主侧，适合 hash、fetch、文件、数据库、平台能力等。
  这类能力默认映射为 Promise，不提供跨 isolate 的同步调用语义。
- platform/web provider：在 web 端可包装浏览器原生能力，在 native 端可包装 Flutter/Dart 能力；同一个
  JS API 可以按平台选择不同 provider，但 JS 侧调用方式保持稳定。

同步 / 异步语义按 JS API 形态决定，而不是按实现偏好决定：

- 同步 JS API 只能由 JS provider 或 worker-local、确定短耗时实现提供，例如纯 JS polyfill。
- 跨 Dart 主 isolate、网络、文件系统、数据库、平台通道或可能长耗时计算的 provider 必须返回 Promise。
- 标准本身是 Promise 的 API，例如 `fetch()`、`crypto.subtle.digest()`，应天然走异步 provider。
- 标准本身是同步的 API，例如 `crypto.getRandomValues()`，如果无法提供 worker-local 同步实现，就不要用
  异步 provider 伪装成同步 API，应改为用户显式注入自定义异步 API 或选择 JS fallback。

### 批量挂载模型

用户不应该被迫在 `QuickjsRuntimeOptions` 里一条条拼 `environmentPatches`、`modules`、`providers`。
需要提供一个批量挂载对象，把相关能力作为一个整体安装：

```dart
final appApi = QuickjsHostMount(
  name: 'app-api',
  environmentPatches: [
    QuickjsHostScript(
      name: 'app-global.js',
      globals: ['app'],
      source: 'globalThis.app = ...',
    ),
  ],
  modules: [
    QuickjsHostModule.esModule(
      specifier: 'app/api',
      source: 'export function hello() { ... }',
    ),
  ],
  providers: [
    QuickjsHostProvider.async(
      name: 'app.hello',
      callback: (args, context) async {
        context.throwIfCancelled();
        return 'hello';
      },
    ),
  ],
);
```

挂载入口分两种：

- 初始化挂载：创建 runtime 时传入一组 mount，适合固定能力和 preset。

  ```dart
  final engine = await Quickjs.create(
    options: QuickjsRuntimeOptions(
      mounts: [
        QuickjsHostMount.web(),
        appApi,
      ],
    ),
  );
  ```

- 运行时挂载：runtime 创建后批量安装一组能力，适合插件、用户安装包、按业务对象选择 API。

  ```dart
  await engine.mount(appApi);
  ```

  当前第一版已实现，要求 runtime 处于 idle 状态，并通过重建 runtime 原子生效。挂载后原有 JS globals、
  module cache、手动绑定 callback 和 handle 不保留；挂载成功后，该 mount 会在后续 stop 重建时继续安装。

运行时挂载默认拒绝同名 mount、global、provider 和 module。显式传入
`QuickjsHostMountConflictPolicy.replace` 时，只替换之前通过 `Quickjs.mount()` 安装的同名完整 bundle，
并通过重建 runtime 清空旧 module cache 后生效；初始化 mounts 不可替换，与其他 mounts 的资源冲突
仍会拒绝。替换安装失败时恢复旧 mount 配置和可用 runtime。

### 能力归属

按 JS 生态里的自然使用方式划分能力，不按实现难度划分：

- [x] `window` / `self`：global alias capability。当前通过 `QuickjsBrowserGlobals` 显式开启，
  默认不注入。
- [x] `location` / `navigator` / `localStorage` / `sessionStorage`：环境补全。
  只实现明确声明的最小子集，不伪装成完整浏览器环境。
- [ ] `fetch`：环境补全，JS 侧直接 `await fetch(url, init)`；底层实现必须返回
  Promise，native 可走 Dart `HttpClient`，web 可走浏览器 `fetch`。
- [~] Web Crypto：环境补全 `globalThis.crypto`；`QuickjsWebCryptoMount()`
  已覆盖 `crypto.randomUUID()`、`crypto.getRandomValues()`，并通过 async provider 支持
  `crypto.subtle.digest()` 的 SHA-1 / SHA-256 / SHA-384 / SHA-512。该 preset 只作为最小兼容示例，
  不继续按 Web Crypto 标准全量内置；后续新增算法或能力应优先暴露为用户可注入的方法/provider，
  再由环境补全或模块加载包装成 JS API。
- [~] Node `Buffer`：优先作为 `buffer` / `node:buffer` 模块加载；preset 可额外安装
  global `Buffer`；当前 `essential()` / `node()` 已提供最小实现。
- [ ] Node `crypto`：作为 `crypto` / `node:crypto` 模块加载，覆盖 `randomBytes`、hash、
  HMAC 等 Node 风格 API。Web `globalThis.crypto` 与 Node `crypto` 模块是两套入口。
- [~] Node 兼容模块：`process` / `node:process`、`path` / `node:path`、
  `timers` / `node:timers` 已按模块加载注册；`util` 等后续按需补齐。必要时 preset
  再安装对应 global。

### API 设计约束

- [x] 权限与可用能力显式配置，不默认暴露平台敏感能力。
- [x] 具体生态 API 不硬编码进 `quickjs.dart`；`crypto.randomUUID()` 当前已迁移为
  `QuickjsWebCryptoMount()` preset，用户仍可通过环境补全脚本手动注入自定义实现。
- [ ] 把需要 Dart/Flutter 实现的生态能力抽象成通用 host callback/provider 注入接口；框架预制
  `crypto.subtle.digest()`、`fetch` 等能力时也应复用该接口，而不是为每个 API 在 runtime 内部
  增加专用分支。
- [x] provider 声明已包含名称、async 调用模式、structured value codec、每次调用独立的
  `QuickjsHostProviderContext` 取消语义、debug 名称和 `QuickjsHostProviderImplementation` 实现来源；
  `debugInspect().providerDetails` 可读取结构化 metadata。名称可以被环境补全脚本绑定到 global API，
  也可以被模块加载包装成 module export。
- [x] 不允许配置出语义不成立的组合，例如 `sync + Dart/Flutter callback + 跨 isolate/平台能力`。
  这类能力必须显式建模为 async provider，并在 JS 包装层返回 Promise。
- [x] `crypto.subtle.digest()` 的 Flutter 实现已迁移为 `QuickjsWebCryptoMount` 内部注册的 async
  provider，并进一步拆分到 `quickjs_web_crypto_mount.dart`；`quickjs.dart` 不再 import
  `package:crypto`，也不再包含 Web Crypto 专用安装分支。
- [x] runtime options 与 mount 已统一使用 `environmentPatches` 表示环境补全脚本，不再保留
  `hostScripts` 重复入口。
- [x] 新增 `modules`，模块源至少支持 inline source；后续可扩展 asset/file/bytes。
- [x] host module 支持 ES module 和 CommonJS 两种形态，CommonJS 兼容层继续保持最小实现。
- [x] ES module 注入属于 host module registry，而不是 startup script。被注入的 ES module
  不会自动执行；只有 `import` / dynamic `import()` 命中该 specifier 时才 parse/evaluate。
- [x] CommonJS 注入同样属于 host module registry；只有 `require()` 命中该 specifier 时才执行。
- [x] host module 可声明依赖其他 host module、`moduleLoader` 模块或相对模块；依赖解析和 cache
  语义必须与 0.6.0 的 `evalModule` / CommonJS cache 对齐。
- [x] 支持 `node:` 前缀归一化：`node:buffer` 可解析到 `buffer`，但文档必须说明 canonical
  module name。
- [x] 明确 `moduleLoader` 与 `modules` 的组合顺序。当前实现优先级为：显式 host module、
  runtime `moduleLoader`、相对依赖图、内置兼容层；host 与 loader 同名时优先使用 host module，
  重复注册的显式 host module 必须抛出明确错误。
- [x] 模块 cache 语义固定：模块一旦被当前 runtime import / require，就不能在同一 runtime
  中替换；需要重建 runtime 才能替换。
- [x] 提供 debug inspector 等价能力，能看到 host module、provider、已加载模块和已通过动态 loader
  解析过的模块名。
- [x] 同步宿主 API 只能来自 JS startup script 或 worker-local 的确定短耗时实现；跨 Dart 主
  isolate、网络、文件系统或平台异步边界的能力必须返回 Promise。
- [x] dispose / stop / runtime 重建会取消 pending provider bridge，并完成每次调用 context 的
  `cancelled` Future；JS Promise 会 reject，provider 可通过 context 协作停止底层任务。

### 与既有 API 的边界

- 0.5.0 的 `engine.bind(...)`、0.7.0 的 `bindObject()` / `bindClass()` 继续作为直接 global bridge
  API：用户显式把 Dart 函数或对象暴露到 `globalThis`，JS 侧直接调用。
- 0.9.0 的方法注入/provider 复用 callback bridge，但不要求用户手动暴露隐藏 callback。
  预制 `fetch`、storage、Web Crypto 等能力需要 Dart/平台异步实现时，由 preset 内部注册 provider，
  再通过环境补全或模块加载包装成标准 JS API。
- 如果某个能力天然是模块形态，优先迁移到模块加载，不要再要求用户通过 `bind()` 暴露一组 global
  方法。例如 `Buffer`、`node:crypto`、`node:path` 应是 module；`fetch`、`window` 应是 global。
- 0.6.0 的 `moduleLoader` 仍用于项目脚本/asset/package asset 加载；0.9.0 的 `modules`
  用于显式注入宿主能力模块。两者共享解析/cache 规则，但职责不同。

### 预制包顺序

先实现通用机制，再提供预制能力：

1. [x] 模块加载：`QuickjsHostModule` / `modules` 已支持注册、解析、缓存、冲突检测、debug 可见性。
2. [~] 方法注入 / provider：已支持 async Dart/Flutter provider、Promise、
   structured value codec、debug 名称和 runtime 重建重装；dispose/stop 取消语义、JS provider
   与 worker-local sync provider 后续补齐。
3. [x] 迁移现有预制实现：`crypto.subtle.digest()` 已改为 `webCrypto()` preset 内部使用 provider
   注入；后续 `fetch`、Node `crypto` 等能力都复用同一套 provider 机制。
4. [~] 环境补全：`QuickjsHostMount.web()` 已提供 `URL`、`location`、`navigator`、storage
   等 Web 风格最小集；`fetch` 后续按显式能力继续补。
5. [~] 批量挂载：已新增 `QuickjsHostMount`、`QuickjsRuntimeOptions.mounts` 和 `Quickjs.mount(...)`，
   支持初始化及运行时批量组合 capabilities、environment patches、modules、providers 和 Web Crypto
   preset。旧 `QuickjsHostEnvironment` / `hostEnvironments` 已删除。运行时挂载当前通过重建生效，
   热挂载和 replace 策略后续评估。
6. [x] 命名整理：批量入口使用 `mounts` / `QuickjsHostMount`，直接配置统一为
   `environmentPatches`、`modules`、`providers`。
7. [~] `QuickjsWebCryptoMount()`：已提供 `crypto.randomUUID()`、
   `crypto.getRandomValues()` 和 Flutter 原生 `crypto.subtle.digest()` 作为最小示例；不在
   0.9.0 内继续补齐 encrypt/decrypt/sign/verify 等完整 `SubtleCrypto` API。后续如需扩展，
   应先提供用户可复用的 callback/provider 注入接口，再由用户或独立预制包组合具体能力。
8. [~] `QuickjsHostMount.node()`：已提供 `buffer`、`path`、`process`、`timers` 的 ES module
   与 CommonJS host module；可显式安装 global `Buffer` / `process`。`crypto`、`fs`、网络和完整
   npm resolver 不在第一版内。
9. [~] `QuickjsHostMount.essential()`：已提供最小 `buffer` / `node:buffer` ES module 与
   CommonJS module，并可显式安装 global `Buffer`；timers、JSON/URL 等后续按需补齐。console
   不放在 preset 中，因为 no-op console 是 core default。
10. [ ] 文档化 npm bundle 策略：完整 npm resolver 不放进 runtime，推荐用户用 esbuild/Rollup
   预打包；`modules` 只负责显式注册的模块。

### 验收

- [x] 未启用任何 host environment 时，`fetch`、`window`、`Buffer`、`crypto` 等不可见，或按文档
  返回明确错误。
- [~] global 能力不需要 import：`window.location`、`navigator`、storage、`crypto.randomUUID()`
  在启用对应 global 后可用。
- [x] module 能力必须 import / require：`import { Buffer } from "node:buffer"`、
  `import crypto from "node:crypto"` 在启用对应 module 后可用。
- [x] 同一能力的 global 入口和 module 入口互不混淆；例如 Web `crypto` global 不等同于 Node
  `node:crypto` 模块。
- [ ] 同一份用户注入的 hash/random 能力在 native / web 后端下结果一致。
- [ ] 大数据 SHA-256 使用用户注入的 Flutter/web 实现时不阻塞 UI，且性能明显优于 QuickJS 内纯 JS
  实现。
- [~] provider 已支持 Dart/Flutter 异步实现；JS 实现和 platform/web 实现的同一 API 替换后续补齐，
  JS 侧调用方式不应随 provider 来源改变。
- [x] 已支持初始化时通过 options 或运行时通过 `engine.mount(...)` 批量挂载能力包，并覆盖安装顺序、
  冲突检测、debug 可见性和 stop 重建语义。运行时挂载要求 idle，并通过重建 runtime 生效。
- [x] `QuickjsHostMountConflictPolicy.replace` 支持原子替换同名 runtime mount；初始化 mount 不可替换，
  无关资源冲突仍拒绝，安装失败会回滚旧 mount 并恢复 runtime。
- [~] 运行时挂载模块时必须遵守 cache 规则：同名 provider、同格式 module 和显式声明的 global
  已在重建前报错；动态 loader 已加载模块与未声明 global 的冲突仍需调用方避免。
- [x] async provider 在 stop / dispose / runtime 重建时不会悬挂 bridge Future；JS 侧 Promise 会
  reject，provider 通过 `QuickjsHostProviderContext` 接收取消信号，后续新 runtime 重新安装 provider。
- [~] stop 重建 runtime 后，startup scripts 和 host modules 重新可用；已加载模块 cache 的替换
  规则保持一致。
- [~] native / web 一致性测试覆盖 global 注入、host module 注入、`node:` 前缀、node preset、
  runtime 隔离、dispose cancellation 和模块冲突错误。
- [x] host modules example 页面覆盖 ES module、CommonJS、`node:` 前缀、相对依赖、
  global 污染检查、cache、debug 模块列表、essential Buffer、node preset 和 stop 重建后恢复。
- [x] 能力批量挂载 example 页面覆盖初始化 mounts、运行时 `Quickjs.mount()`、同名 mount 原子替换、
  环境补全、module、provider、冲突回滚、debug 挂载列表和 stop 重建后恢复。
- [x] Web 宿主环境 example 页面覆盖 `QuickjsHostMount.web()`、默认未启用检查、
  `window` / `self` / `location` / `navigator`、内存版 storage、轻量 `URL` 和 stop 重建后恢复。
- [x] Web Crypto example 页面覆盖 `QuickjsWebCryptoMount()`、默认未启用检查、
  `crypto.randomUUID()`、`crypto.getRandomValues()`、Flutter 原生 `crypto.subtle.digest()` 和 stop
  重建后恢复。

## 0.10.0：JS 插件入口与模块包

目标：在 0.9.0 的 `modules` 稳定后，支持把一段 JS 或一组 JS 模块作为可选择的业务
API provider 装载到 runtime。quickjs 核心只负责运行插件入口、模块注册、调用导出函数和
runtime 替换语义；zip 解压、插件目录、签名、更新源等安装管理能力可以由应用层或独立包实现。

### 插件形态

- [ ] 单文件插件：一个 JS 文件就是一个 entry module，可直接导出业务函数，例如 `hello()`。
- [ ] 插件包：多个 JS module 组成一个模块图，包含 entry module、内部依赖模块和可选资源描述。
- [ ] 插件模块必须带 namespace，例如 `api1/main`、`api1/xx`，避免不同插件之间 specifier 冲突。
- [ ] 插件内部可使用相对 import；框架负责把插件模块图映射到 `modules` 并复用 0.9.0 的
  解析和 cache 规则。
- [ ] 插件来源可以是 inline source、asset、file、bytes 或外层安装器解包后的目录；quickjs
  不要求用户把多文件插件预打包成单个 JS 文件。
- [ ] 复杂 npm 依赖仍推荐插件作者预打包；quickjs 插件包只承诺显式模块图，不实现完整 npm resolver。

### 插件模板与契约

- [ ] 提供推荐模板，而不是强制 JS 继承某个基类。插件默认通过 ES module exports 暴露能力。
- [ ] manifest 声明插件契约：`id`、`version`、`entry`、`exports`、可选 `permissions`、可选
  `metadata`。
- [ ] `exports` 声明 Flutter 侧可调用的方法名，例如 `hello`、`translate`、`summarize`。
- [ ] 可选生命周期导出：`init(context)`、`dispose()`；未导出时跳过，不影响普通函数调用。
- [ ] quickjs 可在装载时校验 manifest 声明的 exports 是否存在且为 function，失败返回明确错误。
- [ ] 不要求插件引入 quickjs JS SDK；后续可提供可选 helper SDK，但 SDK 不是运行必需依赖。
- [ ] 插件参数和返回值必须符合 structured value codec；不支持的 JS 值按现有转换错误处理。

### Runtime 装载与调用

- [ ] 插件数据来源与 runtime 装载分离：应用层决定插件从哪里来，runtime 创建时显式选择要启用的
  单文件插件或插件包。
- [ ] 同一插件可以装载到多个 runtime；不同业务对象可以选择不同 runtime、不同 plugin id 或不同
  entry module。
- [ ] Flutter 侧提供面向业务的调用入口，例如按插件 entry 调用导出函数：
  `callPlugin(pluginId, method, args)` 或 `callModule(module, method, args)`。
- [ ] `api1`、`api2`、`api3` 可以导出同名 `hello()`；业务端选择不同插件对象或 runtime，
  即可调用不同实现。
- [ ] 插件导出的函数走现有 structured value codec；Promise 返回值、异常、Uint8List 等语义复用
  0.4.0 / 0.5.0 的转换和错误模型。
- [ ] 插件需要网络、存储、文件系统等能力时，只能通过 0.9.0 host environment 显式启用；
  quickjs 核心不默认继承平台敏感能力。

### 替换与升级语义

- [ ] 插件模块不热替换已加载模块。由于 QuickJS module cache 存在，已 import / require 的插件
  模块只能在新 runtime 或重建 runtime 后生效。
- [ ] 提供明确的替换策略：保留当前 runtime 继续跑旧版本；新建 runtime 使用新版本；或 dispose
  当前 runtime 后重建并重新装载插件。
- [ ] 如果业务需要无缝切换，由上层持有插件 API 对象并在 runtime 重建后替换该对象引用。
- [ ] 外层插件管理器可以提供安装、查询、启用、禁用、卸载、版本更新、hash / 签名校验等能力；
  这些不是 quickjs 核心包的必需职责。

### 文档与测试

- [ ] 单文件插件示例：一个 asset JS 文件导出 `hello()`，Flutter 侧直接调用。
- [ ] 多文件插件包示例：`main.js` import `modules/xx.js`，Flutter 侧调用 entry 的导出函数。
- [ ] 插件模板示例：`manifest.json` + `main.js` + `modules/helper.js`，展示 exports 契约。
- [ ] 三个 provider 示例：`api1`、`api2`、`api3` 都导出 `hello()`，Flutter 侧选择不同 provider。
- [ ] manifest exports 声明缺失、entry 未找到、导出不是 function 时都有明确错误。
- [ ] 插件内部依赖未声明模块时返回明确 module resolve error。
- [ ] 插件 namespace 冲突、重复 entry、runtime 重建后新版本生效都有测试覆盖。

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
- [x] callback / timer / module cache runtime 隔离测试。
- [ ] example app smoke 自动化测试。
