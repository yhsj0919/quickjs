# Runtime 执行方式

原生平台默认在创建 runtime 的 Dart isolate 中执行 QuickJS。Flutter UI isolate 创建的
runtime 可以直接同步调用 JS；网络等宿主能力返回 Future 时仍通过 Promise 异步等待。
执行位置在创建时确定，所有子 Context 跟随 runtime，不在运行期间迁移。

```dart
final runtime = await JsRuntime.create();
final context = await runtime.createContext();
final value = context.evalSync('1 + 2');

final worker = await JsRuntime.create(
  options: const JsOptions(execution: JsExecution.workerIsolate),
);
```

`JsEngine` 与 `JsContext` 提供 `evalSync`、`evalRawSync` 和 `callSync`。
`JsFunctionHandle` 提供 `callSync` 和 `callRawSync`，用于重复调用保留闭包的函数引用。
结构化同步调用遇到 Promise 时抛出值转换错误，不等待 Promise。
同步宿主方法、对象 getter/setter、类构造器与成员方法直接返回；真正返回 Future 的回调
转为 Promise。worker 内仍遵循 JS 同步语义，但 Dart 调用跨越消息边界，只能异步返回。

现有 `eval`、`call` 等 Future API 继续通过执行队列调度；`run` 等待 JS Promise。
同步入口立即执行，可在异步操作等待期间使用同一 Context。它不会打断正在运行的 JS；
宿主回调中同步重入同一 runtime 会明确失败。等待期间其他事件可以改变 Context 中的状态，
恢复后可观察这些变化，符合正常的异步代码语义。

Future/Promise 不会自动把同步计算移到后台。长同步计算会占用所属 isolate；
需要可响应、可由调用方取消的独立计算时显式选择 worker，输入和输出按数据传输。
当前 isolate 中的无超时死循环会阻止 Dart Timer 或取消代码执行；同步入口可以显式传 timeout，
由原生 interrupt handler 中断。异步执行的初始同步阶段与 Promise jobs 检查点同样受执行时限约束。

Promise 返回所属 Context，保留对象、闭包和模块状态。Context 释放后不接收迟到结果，
等待中的调用取消，其他 Context 继续运行。原生回调按 executor 注册，不使用 isolate 全局端口，
同一 isolate 可以同时拥有多个 runtime。

本轮同步入口适用于原生 FFI 后端。Web 仍通过 WASM/Web Worker 执行，
`supportsSync` 为 false；同步调用明确报告不支持。JSUI 现有批次列表协议尚未迁移，
后续可以使用函数引用的同步入口实现真正的 Flutter itemBuilder。

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
