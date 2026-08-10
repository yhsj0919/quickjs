# QuickJS 空闲后栈溢出问题复盘

## 现象

页面或插件空闲一段时间后，下一次调用 QuickJS 可能抛出：

```text
QuickJS_EXCEPTION{"message":"Maximum call stack size exceeded","name":"RangeError","stack":""}
```

最早在 `quickjs_ui` 的 video 页面复现，后来 custom components 页面也能复现。进一步用普通 `zipDemo` 插件验证后，UI 不参与也能复现：

```text
plugin=zipDemo method=hello idleMs=140186
QuickJS_EXCEPTION{"message":"Maximum call stack size exceeded","name":"RangeError","stack":""}
```

这说明根因不在 video 页面、custom components 页面，也不在 `quickjs_ui` 的事件合并策略。

## 为什么不是 timeout

日志里失败调用的 `timeoutMs=null`，`remainingTimeoutMs=null`，也没有出现 `eval.queue.timeout`。

Dart worker 的 `_evalAsync()` 只有在调用方传入 timeout，并且 stopwatch 超过 timeout 后，才会抛 `JsTimeoutException`。这次抛出的是 QuickJS 自己的 `RangeError: Maximum call stack size exceeded`。

所以这个问题不是“超时异常”，而是“空闲后第一次进入 QuickJS 时，QuickJS 的 native 栈检查误判为栈溢出”。

## 根因

QuickJS 的栈溢出检查依赖 `JSRuntime.stack_top`。QuickJS 头文件对 `JS_UpdateStackTop()` 的说明是：

```c
/* should be called when changing thread to update the stack top value
   used to check stack overflow. */
```

当前 native bridge 在创建 runtime 后设置过 stack limit，但后续从 Dart worker isolate 再次进入 QuickJS 时，没有调用 `JS_UpdateStackTop()`。

Dart isolate 在空闲、窗口暂停/恢复、系统调度后，不能假设永远运行在同一个 OS thread。只要后续 FFI 调用落到另一个线程，QuickJS 仍拿旧线程的 `stack_top` 做栈检查，就可能把一次正常调用误判成 `Maximum call stack size exceeded`。

这解释了几个关键现象：

- 为什么不是持续操作时必现，而是空闲一段时间后更容易触发。
- 为什么 UI 页面和普通 plugin 都能触发。
- 为什么重建 runtime 可以缓解：新 runtime 会在当前线程重新记录 stack top。
- 为什么日志里异常发生得很快，通常几毫秒内失败，而不是等待 timeout。

## 修复方案

native bridge 在每个从 Dart 进入 QuickJS 的入口刷新 stack top：

- `quickjs_eval_timeout_named`
- `quickjs_eval_module`
- `quickjs_eval_async_start_named`
- `quickjs_eval_async_poll`
- `quickjs_runtime_bind_callback`
- `quickjs_runtime_resolve_callback`
- `quickjs_runtime_resolve_stream_pull`
- `quickjs_runtime_resolve_sink_action`
- `quickjs_runtime_bind_sink`
- pending job pump `qjs_execute_pending_jobs`

同时在 `quickjs_runtime_set_stack_limit()` 里先调用 `JS_UpdateStackTop()`，再调用 `JS_SetMaxStackSize()`，避免 stack limit 基于过期 stack top 计算。

## 诊断修正

之前 Dart eval 队列日志有误导：`running.then(..., onError: ...)` 内部已经把错误转交给 request future，导致外层 `_running` future 本身完成成功，日志显示为 `eval.queue done`，但调用方随后仍然收到异常。

现在 `_QueuedEval` 会保存失败原因，外层日志会输出：

```text
[quickjs_diag/eval.queue ...] FAILED id=... name=... error=...
```

这能避免把 native/QuickJS 异常误判为 “eval 已成功，后面 Dart 转换失败”。

## 后续判断标准

如果修复后再次复现，需要优先看：

- 失败调用前是否仍有很大的 `idleMs`。
- 是否已经加载了重新编译后的 native DLL。
- `eval.queue` 是否显示 `FAILED` 而不是 `done`。
- 是否发生在 host callback、stream、timer 等其他 native 入口。

如果普通 plugin 长时间 idle 后不再复现，而 UI 页面仍复现，再回到 `quickjs_ui` 的事件流、生命周期、render 递归去查。
