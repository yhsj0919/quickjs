# Runtime 执行方式

原生平台按 API 类型选择执行路径：Future API 默认在后台 worker 执行，同步 API 在调用方
当前线程执行。同一个 runtime 的两种入口共享 JS 堆，保留全局变量、闭包、模块与子 Context
状态；不会建立两份环境，也不会通过序列化复制状态。

```dart
final runtime = await JsRuntime.create();
final context = await runtime.createContext();
context.evalRawSync('globalThis.count = 1'); // 当前线程
await context.eval('++count');              // 默认后台
final value = context.evalSync('count');    // 2，同一份状态

final local = await JsRuntime.create(
  options: const JsOptions(execution: JsExecution.currentIsolate),
);
// local 的 Future API 也在当前 isolate 执行；同步 API 的执行位置保持不变。
```

`JsEngine` 与 `JsContext` 提供 `evalSync`、`evalRawSync` 和 `callSync`。
`JsFunctionHandle` 提供 `callSync` 和 `callRawSync`，用于重复调用保留闭包的函数引用。
结构化同步调用遇到 Promise 时抛出值转换错误，不等待 Promise。同步执行中的宿主方法、
对象 getter/setter、类构造器与成员方法直接返回；真正返回 Future 的回调转为 Promise。
后台执行时，JS 与 Dart 宿主通过异步桥接通信。

同一原生 runtime 只允许一个线程进入 QuickJS。每次进入时选择当前 isolate 的宿主回调，
更新栈顶，退出后释放访问权；后台请求的完成响应在释放访问权后发送。
后台正在执行 JS 或推进 Promise jobs 时，同步入口抛出 `StateError`，不会等待后台计算
结束。要避免争用，可先 await 已提交的后台操作，或使用 Future API 通过队列执行。
需要在异步等待期间确定性地立即同步访问的场景，可显式选择 `currentIsolate`。
宿主回调中同步重入同一个 runtime 会明确失败。

`JsOptions.execution` 只控制原生 Future API 的执行位置，并由所有子 Context 继承。
Future API 继续通过队列调度，`run` 等待 JS Promise。默认后台路径中的长 JS 计算不阻塞
创建 runtime 的 UI isolate；但显式 `currentIsolate` 和所有同步 API 都会占用调用方。
同步入口可传 timeout，由原生 interrupt handler 中断。超时覆盖后台调用的初始同步阶段与
Promise jobs 检查点；Context 释放后取消等待，丢弃迟到的宿主结果，其他 Context 继续运行。

Web 仍通过 WASM/Web Worker 执行，`supportsSync` 为 false，同步入口明确报告不支持。
`execution` 不会将 Web 调用变成 Dart isolate 调用。JSUI 自建 runtime 显式使用
`currentIsolate` 保持渲染调度兼容，与默认后台 Core service 通过异步桥接通信。

## 参数调用与批量调用

原生的全局函数、函数句柄和模块/插件导出调用使用 `JS_Call` 执行已安装的调用器，
不再为每次调用拼接、编译参数还原与结果转换脚本。
编解码器按 Context 安装并复用；JS→Dart 回调的 native wire codec 也按 Context 缓存和释放。
两种 wire 格式各自保留既有的值语义，没有合并成新的协议。
全局函数仍在每次调用时读取当前属性，替换全局函数后立即生效；函数句柄保留绑定时的函数和闭包。
全局函数 receiver 为 globalThis，模块导出和函数句柄保持原有 receiver 语义。

结构化 `eval/evalSync` 和带临时 globals 的 `evalRaw/evalRawSync` 复用预装执行器，
原生通过直接调用传入源码和参数，不再重复编译包装层。临时 globals 的注入与恢复、
结果转换在执行器中完成，异常携带显式源码名称；重复执行仍产生正常副作用。
不带 globals 的 raw eval 保留直接 `JS_Eval` 路径。`run` 的临时 globals 复用相同求值逻辑。
调用方的任意新源码仍需要解析和编译，本轮没有缓存脚本字节码或求值结果。
固定逻辑反复执行可用 `bindFunction` 编译成函数句柄，再传不同参数调用。
Web 复用执行器，调用仍经过其 evaluate/Worker 路径；
原生的直接 FFI 调用能力没有被声称为 Web 已实现的能力。

`JsEngine` 和 `JsContext` 提供对同一个全局函数的批量调用：

```dart
final rows = engine.callBatchSync('row', [[0], [1], [2]]);
final asyncRows = await engine.callBatch('row', [[0], [1], [2]]);
```

一批只经过一次 native/worker 请求，批内按顺序执行。异步版本逐项等待真实 Promise，
不是并行启动所有项；首次异常或结果转换失败会停止后续调用，已完成项的副作用不会回滚。
同步版本不等待 Promise，遇到 Promise 返回值会报转换错误并停止后续项。
超时覆盖整个批次；异步版本也包含队列等待时间，同步版本立即执行。
异步超时后释放本次桥接等待槽，后续调用可继续执行；超时不会自动取消任意外部 Future，
也不会回滚副作用。宿主任务需要合作式取消，销毁 Context/runtime 会丢弃迟到结果。
沿用原生 interrupt、取消、销毁及 Context 隔离规则。
空批次返回空列表。结果仍遵守原有转换深度和节点数量上限，批次不能无限扩大。

JSUI 原有批量事件与列表范围请求通过插件导出调用，因此直接使用核心优化路径，
无需在生产页面叠加独立的调用缓存或更改现有列表策略。
Release 单次与批量调用数据见 [调用基准](invocation_benchmark.md)。
