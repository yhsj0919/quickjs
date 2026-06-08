# quickjs 开发计划

当前项目已经完成最小闭环：创建 QuickJS runtime、执行一段 JavaScript、释放 runtime，并覆盖 native FFI 与 Web WASM。下一步不能继续堆功能，必须先解决两个基础问题：

- JS 执行耗时操作会占用 Flutter UI isolate / Web UI thread。
- runtime 生命周期、全局状态、回调、timer、模块缓存等边界还没有形成可验证的隔离模型。

因此本计划把执行模型和运行时隔离提前为 `0.2.0` 的核心目标。只有在这两项稳定之后，才继续推进类型互转、callback、Promise、module、Node/Web 生态兼容等功能。

## 总体原则

1. UI 线程不能直接执行不可控 JS。
   `while (true) {}`、大数组计算、同步 JSON 处理、复杂 bundle 初始化都必须可超时、可取消，且不能冻结 Flutter UI。

2. 每个 runtime 必须有明确所有权。
   runtime、context、handle、callback、timer、module cache、pending jobs 不能跨 runtime 混用。

3. 所有跨边界调用都要异步化。
   Dart API 可以提供方便封装，但底层必须以 request / response / cancel / dispose 的消息模型组织。

4. native 与 web 行为要尽量一致。
   native 优先使用 Dart Isolate + FFI worker；web 优先使用 Web Worker + WASM bridge。两端 API 语义保持一致，底层实现允许不同。

5. 先定义失败语义，再扩展功能。
   timeout、interrupt、dispose、OOM、JS exception、worker crash 都必须有稳定的错误类型和恢复策略。

6. JS API 形状要和实现解耦。
   允许通过宿主能力注入把部分 JS API 替换为 Dart / Flutter native / 平台原生实现，例如 crypto、hash、压缩、编解码等高开销能力；也允许在桌面端 / native 端补齐浏览器或 Node 风格 API，例如 `window`、`location`、`localStorage`、`navigator` 等。用户侧 JS 写法应保持稳定，替换和补齐策略必须受 runtime 隔离、权限配置和一致性测试约束。

7. 公开 API 只保留 `Quickjs` 一个系统入口。
   功能创建、执行、停止、销毁都必须从 `Quickjs` 实例进入；不要为了局部功能新增并列入口或要求用户直接管理底层 runtime 类型。

8. 每个新功能必须同步补齐 example 测试页面。
   example 页面必须能独立运行，进入页面时简单创建自己的 `Quickjs` 实例，退出页面时销毁该实例；页面之间不能共享 runtime 状态。

## 0.2.0：执行模型与 UI 线程解耦

目标：任何 JS 执行都不能阻塞 Flutter UI。当前 native 侧 `quickjs_eval()` 是同步 `JS_Eval`，必须改造成后台执行模型。

### 1. Dart API 异步化

将公开 API 统一成异步执行入口：

状态：已完成。

```dart
final engine = await Quickjs.create();
final result = await engine.eval('1 + 2');
```

要求：

- `Quickjs.create()` 创建一个后台 runtime worker。
- `engine.eval()` 只发送执行请求，不在 UI isolate 同步跑 FFI。
- `engine.dispose()` 关闭 worker，并释放 native runtime / web runtime。
- 禁止新增只为方便而暴露的同步执行 API。

验收：

- [x] Flutter 页面点击按钮执行 `while (Date.now() < start + 3000) {}` 时，UI 仍可响应。
  - example 已提供 `Runtime Worker` 页面；native 使用 Dart isolate，web 使用 Web Worker。
- [x] 多次并发 `eval()` 要么串行排队，要么明确拒绝并发，不能产生 native runtime 重入。
  - 当前策略为同一 `Quickjs` 实例 FIFO 串行排队。

### 2. Native FFI Worker

native 平台增加 runtime worker isolate：

状态：已完成。

- [x] UI isolate 负责 API、Future、状态管理。
- [x] worker isolate 负责持有 `DynamicLibrary`、`QuickjsRuntime*` 和所有 FFI 调用。
- [x] 每个 `QuickjsJsRuntime` 对应一个 worker 或一个 worker 内的独立 runtime。

建议消息协议：

```dart
sealed class RuntimeCommand {}

final class EvalCommand {
  final int requestId;
  final String code;
  final Duration? timeout;
}

final class CancelCommand {
  final int requestId;
}

final class DisposeCommand {}
```

验收：

- [x] `quickjs_eval()` 不再从 UI isolate 直接调用。
- [x] runtime 指针只存在于 worker isolate。
- [x] dispose 后继续 eval 必须抛出明确的 `StateError` 或自定义 closed error。

### 3. Web Worker 执行模型

web 平台不能在主线程直接跑 WASM QuickJS。需要把 `quickjs_web.js` / WASM bridge 移入 Web Worker，主线程只做消息转发。

状态：已完成。

要求：

- [x] 主线程加载 worker script。
- [x] worker 内初始化 WASM 和 QuickJS runtime。
- [x] `eval`、`dispose`、后续 `pumpJobs`、`callFunction` 都通过 `postMessage`。
  - 当前已覆盖 `eval` / `runtimeEval` / `runtimeNew` / `runtimeDispose`；`pumpJobs`、`callFunction` 后续新增时必须继续走同一消息通道。
- [x] 对浏览器不支持 Worker 的场景给出明确 fallback 或 unsupported error。

验收：

- [x] Web demo 执行长耗时 JS 时页面仍能点击、输入、重绘。
  - example 已提供 `Runtime Worker` 页面。
- [x] Worker crash / 初始化失败能传播为 Dart Future error。
  - 初始化失败、worker error、message error 会传播到 pending Future。

### 4. 执行队列与重入策略

QuickJS runtime 通常不应被多个线程同时进入。每个 runtime 要有单线程执行队列。

状态：部分完成。

策略：

- [x] 同一 runtime 内命令默认 FIFO 串行执行。
- [x] 当前命令运行时，后续命令排队。
- [x] `dispose()` 优先级高于普通 eval，会取消队列并释放资源。
  - 当前实现为 dispose 立即拒绝新请求、取消尚未开始的排队 eval，并等待正在执行的 eval 收尾后释放 runtime。
- [ ] `cancel(requestId)` 只能取消排队任务；正在执行的任务通过 interrupt handler 中断。

验收：

- [x] 同一 runtime 连续 100 次 eval 顺序稳定。
  - 已补 100 次并发 FIFO 单元测试，并新增 example `执行队列与重入策略` 页面。
- [x] eval 执行中调用 dispose 不会崩溃、不泄漏、不返回悬挂 Future。
  - 已补 dispose 取消排队任务单元测试，并新增 example 页面验证排队任务不会继续进入 runtime。

### 5. 超时与取消

实现基础超时和手动停止，这是解决死循环的关键。

native 侧：

- 使用 `JS_SetInterruptHandler`。
- runtime 结构体保存 `cancel_requested`、`deadline_ms` 等执行状态。
- interrupt handler 检查取消标记和 deadline。

web 侧：

- 优先使用 quickjs-wasi / bridge 已有 interrupt 或 execution limit 能力。
- 如果底层无法中断正在执行的 WASM，需要以 Worker terminate 作为最后兜底，并标记该 runtime 已失效。

目标 API：

```dart
await engine.eval(
  code,
  timeout: const Duration(seconds: 3),
);

await engine.stop();
```

验收：

- `while (true) {}` 在 timeout 后返回 `JsTimeoutException`。
- `engine.stop()` 能停止正在执行的 eval。
- 中断后 runtime 是否可继续使用必须被测试确认；如果不可恢复，API 必须将 runtime 标记为 closed。

### 6. 基础错误模型

先建立错误类型，避免后续功能把错误都压成字符串。

建议类型：

```dart
sealed class QuickjsException implements Exception {}

final class JsException implements QuickjsException {
  final String message;
  final String? stack;
  final String? fileName;
  final int? line;
  final int? column;
}

final class JsTimeoutException implements QuickjsException {}
final class JsCancelledException implements QuickjsException {}
final class JsRuntimeClosedException implements QuickjsException {}
final class JsRuntimeCrashException implements QuickjsException {}
```

验收：

- JS throw、timeout、manual cancel、dispose、worker crash 不能混成同一种字符串错误。
- Dart 侧测试可以精确匹配异常类型。

## 0.3.0：Runtime 隔离与资源边界

目标：多个 runtime 可以同时存在，互不污染，且资源限制明确。

### 1. 多 Runtime 隔离

支持：

```dart
final vm1 = await Quickjs.create();
final vm2 = await Quickjs.create();
```

要求：

- globals 隔离。
- callback registry 隔离。
- module cache 隔离。
- timer registry 隔离。
- pending job queue 隔离。
- dispose 一个 runtime 不影响其他 runtime。

验收：

- `vm1.eval('globalThis.x = 1')` 后，`vm2.eval('globalThis.x')` 返回 `undefined`。
- `vm1.dispose()` 后，`vm2` 仍可正常 eval。
- callback / function handle 不能跨 runtime 调用。

### 2. Runtime 生命周期状态机

明确状态：

```text
creating -> ready -> running -> stopping -> closed
                         -> failed
```

规则：

- `ready` 可以接收新命令。
- `running` 可以排队命令或 stop。
- `stopping` 只接受 dispose。
- `closed` 所有 API 抛 closed error。
- `failed` 表示 worker crash、不可恢复中断、native fatal error。

验收：

- 每个状态都有单元测试。
- Future 不允许永久 pending。

### 3. 内存与栈限制

native 使用 QuickJS 原生能力：

- `JS_SetMemoryLimit`
- `JS_SetMaxStackSize`

目标 API：

```dart
final engine = await Quickjs.create(
  limits: QuickjsLimits(
    memoryBytes: 64 * 1024 * 1024,
    stackBytes: 1024 * 1024,
  ),
);
```

验收：

- 超出内存限制返回明确异常。
- 深递归触发 stack limit，不崩溃进程。

### 4. Handle 所有权

后续 function/object handle 必须先设计所有权规则：

- handle 只在所属 runtime 内有效。
- Dart 侧只保存 handle id，不保存裸 `JSValue`。
- native/web worker 内维护 handle table。
- dispose runtime 时释放所有 handle。
- handle finalizer 只能作为兜底，不能代替显式 dispose。

验收：

- 跨 runtime 调用 handle 返回明确错误。
- 重复释放 handle 不崩溃。
- runtime dispose 后 handle 调用返回 closed error。

## 0.4.0：结构化结果、类型互转与异常

目标：从“字符串 eval”升级到结构化 Dart/JS 数据交换。

### 1. JS 到 Dart

支持：

- `number`
- `boolean`
- `string`
- `null`
- `undefined`
- `array`
- plain object
- `ArrayBuffer` / `Uint8Array`

验收：

- 不再把所有结果都转成字符串。
- 循环引用、symbol、function 等不可直接转换值要返回明确错误或 handle。

### 2. Dart 到 JS

支持：

- `int`
- `double`
- `bool`
- `String`
- `null`
- `Uint8List`
- `List`
- `Map<String, Object?>`
- `DateTime`

目标 API：

```dart
await engine.eval(
  'user.name',
  globals: {
    'user': {'name': 'Tom'},
  },
);
```

验收：

- 深层 List/Map 转换稳定。
- 不支持的 Dart 类型报错清晰。

### 3. 结构化 JS 异常

JS throw 必须提取：

- `message`
- `stack`
- `name`
- `fileName`
- `line`
- `column`

验收：

- `throw new Error("bad")` 在 Dart 侧是 `JsException`。
- stack 中能看到 eval 文件名。

## 0.5.0：Callback、Promise 与事件循环

目标：让 Dart 与 JS 可以稳定互调，并支持异步任务。

### 1. Dart Function 注入

目标 API：

```dart
engine.bind('toast', (String msg) {
  print(msg);
});
```

要求：

- callback 注册在 runtime worker 内。
- JS 调用 Dart callback 必须通过消息回 UI isolate。
- 同步 callback 与异步 callback 行为要分开定义。

验收：

- JS 调用 Dart 同步函数能返回值。
- callback 抛错能转换为 JS exception。
- dispose runtime 后 callback 不再触发。

### 2. Future 到 Promise

Dart async callback 在 JS 侧表现为 Promise：

```dart
engine.bind('loadUser', () async => {'name': 'Tom'});
```

```js
const user = await loadUser()
```

验收：

- Future resolve / reject 正确映射到 Promise resolve / reject。
- runtime dispose 时未完成 Promise 被 reject 或取消，不能悬挂。

### 3. Promise Job Pump

native 侧使用：

- `JS_ExecutePendingJob`
- runtime job pump
- job exception propagation

目标 API：

```dart
await engine.pumpJobs();
final result = await engine.evalAsync('await Promise.resolve(1)');
```

验收：

- microtask 顺序符合 JS 语义。
- Promise rejection 能传播到 Dart。

### 4. Timer

实现最小浏览器风格 timer：

- `setTimeout`
- `clearTimeout`
- `setInterval`
- `clearInterval`

要求：

- timer 属于 runtime。
- timer callback 进入 runtime worker 队列。
- dispose runtime 自动取消所有 timer。

## 0.6.0：Module 与 Asset

目标：支持真实项目脚本组织方式。

### 1. ES Module

支持：

- `import`
- `export`
- module parse / evaluate
- module cache
- module error location

目标 API：

```dart
await engine.evalModule(source, name: 'main.js');
```

### 2. Module Loader

目标 API：

```dart
engine.registerModuleLoader((name) {
  return assetBundle.loadString(name);
});
```

要求：

- loader callback 归属 runtime。
- module cache 归属 runtime。
- 相对路径解析可测试。

### 3. Asset Loader

目标 API：

```dart
await engine.evalAsset('assets/js/main.js');
```

要求：

- Flutter `AssetBundle`。
- package asset 路径。
- Web asset URL。
- module 相对路径解析。

### 4. CommonJS 最小兼容

提供最小 CommonJS 层：

- `require()`
- `module.exports`
- `exports`
- module cache
- relative path resolution

不在 runtime 内实现完整 npm resolver。npm 包优先推荐用户使用 esbuild / Rollup / webpack 预打包。

## 0.7.0：对象桥接与高级 Handle

目标：在基础执行模型稳定后，再提供更自然的对象访问。

### 1. JS Function Handle

```dart
final add = await engine.eval('''
function add(a, b) {
  return a + b
}
add
''');

final result = await add.call([1, 2]);
```

要求：

- function handle 绑定 runtime。
- call 通过 runtime worker 执行。
- call 支持 timeout / cancel。

### 2. Dart Object Proxy

```dart
final user = User(name: 'Tom');
engine.bindObject('user', user);
```

支持：

- property getter
- property setter
- method call
- readonly property
- async getter / method

### 3. Dart Class / Instance

```dart
engine.bindClass<User>('User', User.new);
```

要求：

- instance id 管理。
- finalizer 兜底清理。
- JS GC 与 Dart GC 的关系要有文档说明。

## 0.8.0：调试与开发体验

目标：提升定位问题的效率。

### 1. Console

支持：

- `console.log`
- `console.warn`
- `console.error`

目标 API：

```dart
final engine = await Quickjs.create(
  console: QuickjsConsole(
    log: debugPrint,
    warn: logger.warning,
    error: logger.severe,
  ),
);
```

要求：

- console callback 走 runtime worker 消息。
- dispose 后不再回调。

### 2. SourceMap 与 Stack

支持：

- source file name
- source map registry
- stack remap
- async stack 可解释输出

### 3. Inspector 原型

QuickJS 没有官方 Chrome DevTools inspector，可以提供 debug mode：

- 查看 globals。
- 查看 modules。
- 查看 memory。
- 查看 pending jobs。
- 查看 registered callbacks。
- 手动执行表达式。

## 0.9.0+：生态兼容能力

这些能力必须在执行隔离、Promise、module、资源限制稳定之后再做。

### 1. npm Bundle 支持

推荐通过预打包支持 npm：

- esbuild
- Rollup
- webpack

目标 API：

```dart
await engine.loadBundle('assets/js/bundle.js');
```

文档要明确：

- 不直接在 runtime 内跑完整 npm resolver。
- 推荐用户构建 bundle。
- 提供 CommonJS / ESM 打包配置示例。

### 2. 宿主能力注入与原生加速

目标：允许在不改变业务 JS 写法的前提下，把部分 JS API 的底层实现替换为更快的 Dart / Flutter native / 平台原生能力，或在当前平台缺失某些标准 API 时注入兼容实现。

典型场景：

- JS 侧仍然调用 `crypto.subtle.digest()`、`crypto.randomUUID()` 或项目约定的 `hash()`。
- native 侧可以把对应方法绑定到 Dart、Android/iOS 原生库、Flutter plugin 或 FFI 实现。
- Web 侧优先绑定浏览器原生 Web Crypto / CompressionStream 等能力。
- 桌面端 / native 端可以按需注入 `window`、`location`、`navigator`、`localStorage`、`sessionStorage` 等浏览器兼容对象。
- 需要运行偏 Node 生态脚本时，可以按需注入 `process.env`、`Buffer`、`setImmediate` 等最小兼容 API。
- 如果宿主未提供加速实现，则回退到 JS polyfill 或返回明确 unsupported error。

目标 API：

```dart
final engine = await Quickjs.create(
  hostModules: [
    QuickjsHostCrypto.native(),
    QuickjsHostBrowserCompat.window(),
  ],
);
```

设计要求：

- JS API 名称和参数语义先稳定下来，底层实现可替换。
- 注入能力必须归属单个 runtime，不能污染其他 runtime。
- 同步 API 只能绑定到确定不会长时间阻塞的实现；耗时实现必须返回 Promise。
- native / web 的返回值、异常、编码、大小端、随机数安全性等语义必须一致。
- 权限和可用能力要显式配置，不能默认暴露平台敏感能力。
- 浏览器兼容对象只能实现明确声明的最小子集，不能伪装成完整浏览器环境。
- `window` / `globalThis` / `self` 的别名关系要可配置并有文档说明，避免污染模块执行环境。

验收：

- 同一份 JS 加密 / hash 代码在纯 JS polyfill、native 加速、Web 原生加速下返回一致结果。
- 大数据 SHA-256 用 native 加速时性能明显优于 QuickJS 内纯 JS 实现，且不阻塞 UI。
- 同一份依赖 `window.location` 或 `localStorage` 的 JS 在桌面端通过注入能力可运行，未注入时返回明确错误。
- 未启用 host module 时，访问对应能力返回明确错误或按文档回退。
- dispose runtime 后，宿主能力回调不再触发，未完成 Promise 被 reject 或取消。

### 3. fetch

实现最小 `fetch`：

- native 使用 Dart `HttpClient`。
- Web 使用浏览器 fetch。
- 返回 Promise。
- 支持最小 Request / Response 兼容层。

### 4. crypto

优先支持：

- `crypto.randomUUID()`
- random bytes
- SHA-256
- 支持通过宿主能力注入替换为 native / Web Crypto 实现

### 5. Buffer

提供 Node `Buffer` 最小兼容：

- `Buffer.from`
- `Buffer.alloc`
- `toString`
- `Uint8List` 互转

## 测试策略

### 必须优先补齐的测试

1. [x] UI 不阻塞测试。
   长耗时 JS 执行时 Flutter UI 仍可响应。

2. [ ] timeout / stop 测试。
   `while (true) {}` 必须可停止。

3. [ ] runtime 隔离测试。
   globals、callbacks、timers、module cache 互不影响。

4. [x] dispose 测试。
   eval 中 dispose、排队中 dispose、重复 dispose 都不能崩溃。

5. [ ] worker crash 测试。
   worker 异常退出后 Future 必须完成为 error。

6. [ ] native / web 行为一致性测试。
   同一组 JS 用例在 native FFI 和 Web Worker WASM 下语义一致。

### 建议测试分层

- Dart unit test：状态机、队列、错误模型。
- Native integration test：FFI worker、interrupt、memory limit。
- Web integration test：Web Worker、WASM 初始化、长任务不阻塞。
- Example app smoke test：按钮触发长任务时 UI 仍响应。

## 实施顺序

1. [x] 重构 Dart runtime API 为异步消息模型。
2. [x] native 增加 runtime worker isolate，迁移所有 FFI 调用。
3. [ ] native 增加 interrupt handler、timeout、stop。
4. [x] web 增加 Web Worker bridge，迁移 WASM QuickJS 到 worker。
5. [~] 建立 runtime 状态机、执行队列、dispose 语义。
   - FIFO 队列、dispose 不悬挂、dispose 取消排队任务已完成；`cancel(requestId)` 与完整状态机待补。
6. [~] 补齐 UI 不阻塞、timeout、runtime 隔离测试。
   - UI 不阻塞、100 次 FIFO、dispose 取消排队任务测试已完成；timeout、runtime 隔离测试待补。
7. [ ] 通过后再做结构化类型互转和 `JsException`。
8. [ ] 再做 callback、Promise job pump、timer。
9. [ ] 再做 module、asset、CommonJS。
10. [ ] 最后推进对象桥接、调试工具和生态兼容。

## 下一版本范围

`0.2.0` 只做执行安全基础，不做类型系统和生态功能：

- [x] 异步 runtime worker。
- [x] UI isolate / Web UI thread 解耦。
- [x] 单 runtime FIFO 执行队列。
- [ ] `timeout`。
- [ ] `stop()`。
- [~] `dispose()` 状态机。
  - dispose 后拒绝新请求、eval 中 dispose 不悬挂、取消尚未开始的排队任务已完成；完整状态机待补。
- [ ] 基础错误类型。
- [~] native 与 web 的长任务不阻塞测试。
  - native 自动测试已完成；example demo 覆盖 native/web；Chrome 自动测试仍需稳定化。

`0.3.0` 只做运行时隔离和资源限制：

- 多 runtime 隔离。
- runtime 状态机完善。
- handle 所有权规则。
- memory limit。
- stack limit。
- dispose / crash / failed 状态测试。

`0.4.0` 之后再恢复功能开发：

- 结构化返回值。
- Dart/JS 类型互转。
- 结构化 JS exception。
- globals 注入。
- callback。
- Promise。
- timer。
- module。
- asset。
- CommonJS。
