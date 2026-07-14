# QuickJS 与 quickjs_ui 性能优化路线

本文记录 2026-07-14 对 core 与 quickjs_ui 的性能审查结果，作为后续重构依据。

## 当前基线

共享 Runtime、独立 Context、首载 `bootstrap(props)` 重构完成后，计数器页面表现为：

- 热启动通常为 40–44ms。
- schema 就绪通常为 24–27ms。
- Asset 资源加载通常为 12–15ms。
- Context 获取通常约 3ms。
- bootstrap QuickJS 调用通常约 9ms。
- Flutter Renderer 热构建约 0.1ms。
- 冷启动仍可能达到 200ms 以上，主要受资源、Runtime/Context 初始化和 Flutter 首帧影响。

当前阶段不应优先优化 Flutter Renderer。主要成本来自 Dart UI isolate、Runtime worker 和 QuickJS 之间的调用边界，以及资源重复加载。

## P0：合并 UI 状态变更调用（已完成）

当前一次发生状态变化的事件通常需要：

```text
handleEvent → snapshot → commit
```

`dispatchBatch` 仍会逐个调用 `handleEvent`，因此 N 个事件需要 `N + 2` 次 worker 往返。

quickjs_ui 页面适配器现已提供统一 `mutate` 协议：

```js
dispatch(events) => {
  changed,
  snapshot,
  commit
}

applyState(patch) => {
  changed,
  snapshot,
  commit
}

lifecycle(event) => {
  changed,
  snapshot,
  commit
}
```

实际实现还包含超大事件批次保护：普通批次一次完成；超过 128 条时分块更新 JS 状态，中间不生成 snapshot/schema，最后通过一次 `finalize` 返回最终 snapshot 和 commit。旧自定义 runtime 插件继续使用原协议。

无变化时允许省略 snapshot 和 commit。单事件、批量事件、setState 和 lifecycle 应共享同一结果结构。

预期收益：

- 普通点击由 3 次 worker 往返降为 1 次。
- 批量事件由 `N + 2` 次降为 1 次。
- 减少事件响应中的随机调度尖峰。

验收指标：

- 对单次点击和 100 次批量事件分别统计端到端耗时与 worker 请求数。
- 无状态变化时不得触发 schema decode 或 Flutter notify。
- 保持事件顺序、异步 handler、嵌套 dispatch 和生命周期测试通过。

## P0：core 原生模块调用通道（暂缓）

当前 `Quickjs.callModule()` 每次调用都会动态生成 JS 包装代码，并重复注入 `inflate()`、`convert()`、breadcrumb 和 JSON 转换逻辑，然后通过 `evalAsync` 执行。

2026-07-14 使用 50 次 warm-up、500 次空模块调用测得：

| Native DLL | Median | P95 | P99 | Max | Average |
| --- | ---: | ---: | ---: | ---: | ---: |
| Debug | 1.568ms | 1.959ms | 2.530ms | 3.755ms | 1.588ms |
| Release | 0.913ms | 1.199ms | 1.657ms | 3.387ms | 0.943ms |

Release 中位数低于 1ms，P95 与中位数相差约 0.286ms，暂未显示明显的稳定性问题。该测量运行在 Flutter test VM 中，并非完整 AOT Release runner。当前不实施 native ABI 重构；保留 `benchmark/call_module_benchmark_test.dart`，待真实交互 P95 出现问题或 AOT 基准确认固定开销超过约 1ms 后再启动。

建议增加 worker/native 级模块调用命令：

```dart
Future<Object?> callModule(
  String module,
  String method,
  List<Object?> args,
);
```

底层目标协议：

```text
callModuleContext(contextId, moduleHandle, method, encodedArgs)
```

实现方向：

- 首次解析模块后缓存 namespace 或函数引用。
- 后续直接使用 QuickJS C API 查找函数并执行 `JS_Call`。
- 转换 helper 在 Context 初始化时安装一次，不再随每次调用发送源码。
- 保留超时、中断、breadcrumb 和转换错误语义。
- Context 释放时同步清理 module handle。

预期收益：降低所有插件调用、事件、生命周期和 bootstrap 的固定开销，并减少 QuickJS 重复解析临时代码。

验收指标：

- 对比现有 `callModule` 与原生通道的空函数、简单对象和大型 schema 调用。
- 单独统计 Dart 编码、isolate 往返、JS 执行和结果转换。
- API 错误类型、堆栈、超时和 Context 隔离行为保持一致。

## P1：可失效的动态 UI 资源缓存（已完成）

Asset 页面热加载仍会重复执行资源读取、Bundle 解析以及 Plugin/Module 对象构建。缓存不得要求 Runtime 初始化时声明页面，也不得破坏动态更新模式。

现已提供默认启用的独立资源缓存：

```dart
QuickjsUiResourceCache.shared.loadAsset(path: path, bundleRoot: ...)
QuickjsUiResourceCache.shared.invalidate(path)
QuickjsUiResourceCache.shared.clear()
```

实际公开类型为 `QuickjsUiResourceCache`，默认边界为 10 分钟、16MiB、64 条，采用最大存活时间 TTL 与 LRU 容量淘汰。相同 key 的并发加载共享 Future；失败和超过总字节上限的单项不入缓存。缓存仅持有 JS module 文本和 Plugin 描述，不缓存 Context、页面状态、Widget 或图片字节。

缓存策略：

- Asset：以 `AssetBundle identity + path + bundleRoot` 为 key。
- File：依据规范路径、修改时间和文件大小失效。
- Network：沿用 ETag、Last-Modified 和 304 重验证。
- 开发模式允许禁用缓存或显式 invalidate。
- 缓存资源或解析后的 Bundle，不缓存页面 Context 和模块实例。

目标是将常见 Asset 热加载从 12–15ms 降至约 1–3ms。

## P1：批量 Context 初始化

创建 Context 后当前会依次安装 console、text encoding、capabilities、providers、provider registry、environment patches 和 mounts。多个步骤会形成独立 worker 请求。

建议将 Context 创建配置整体发送给 worker：

```text
createContext + bind callbacks + install environment + register modules
```

可先在 Dart 层完成配置校验和源码加载，再一次提交安装计划；worker 内顺序执行并保持失败时原子释放 Context。

该优化主要改善冷启动和 capabilities 较多页面的 `runtimeAcquire`，基础页面收益预计较小。

## P1：事件驱动的 timer/job pump（第一阶段已完成）

当前 Controller 每 500ms 固定执行 timer pump。即使没有 timer 或状态变化，也可能发生 eval、snapshot、commit 和 Flutter notify。

第一阶段现已实现：

```dart
context.pumpJobs() => { didRun, changed, snapshot?, commit? }
```

只有 `changed == true` 时更新 schema 和通知 Flutter。

自动 Page/Bundle 适配器通过 `poll(lastVersion)` 在 JS 内先比较 state version。空闲 tick 只返回 unchanged 标记，不传输 snapshot/schema，也不触发 Controller listener。timer/job 修改状态时，一次 poll 返回最终 snapshot 和 commit。旧自定义 runtime 插件继续使用原 pump 路径。

2026-07-14 使用 Release native DLL 模拟默认 500ms 周期下 60 秒的 120 次空闲 tick：

| 协议 | Median | P95 | Max | 120 ticks 总计 | Worker 请求 | Flutter 通知 |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| version poll | 1.360ms | 1.773ms | 3.254ms | 167.056ms | 240 | 0 |
| legacy | 2.291ms | 2.814ms | 4.446ms | 281.401ms | 360 | 120 |

第一阶段将空闲执行时间降低约 40.6%，并消除了空闲 Flutter rebuild。剩余成本主要是每个 tick 的 timer eval 与 poll 两次 worker 往返；基准入口为 `packages/quickjs_ui/benchmark/timer_pump_benchmark_test.dart`。

长期方案：由 QuickJS timer 调度主动通知 Dart，在下一个到期时间触发 pump，取消固定轮询。

验收指标：

- 空闲页面不产生周期性 schema decode 和 Flutter rebuild。
- 定时器触发时间、Promise jobs、取消和 dispose 行为保持正确。

## P2：Renderer 与 schema 树优化

当前 Renderer 每次构建会递归校验 sibling key、生成完整字符串 signature，并再次遍历树收集 overlay intents。嵌套 keyed tree 可能重复计算子树。

可选方向：

- `QuickjsUiNode` 解码时自底向上计算结构 hash。
- Renderer 使用结构 hash 替代递归字符串 signature。
- schema decode 与 overlay intent 提取合并为一次遍历。
- Inspector 未启用时避免 `node.toMap()`。
- 仅对大型页面基准确认收益后实施。

计数器页面 Renderer 约 0.1ms，因此该项不应早于调用边界和资源缓存优化。

## 推荐实施顺序

1. quickjs_ui mutation 合并返回 snapshot 与 commit。
2. core 原生 `callModuleContext`。
3. Asset/Bundle 可失效缓存。
4. 批量 Context 初始化。
5. 事件驱动 timer/job pump。
6. Node 结构 hash 与树遍历合并。

前两项应作为同一阶段设计：目标是系统性减少 Dart isolate、worker 与 QuickJS 之间的调用边界，而不是继续针对单个页面增加特殊预热逻辑。

## 基准与回归要求

每项优化实施前后至少记录：

- 冷启动首次页面。
- Runtime 已初始化后的首次页面。
- 同一资源重复打开。
- 单次点击状态更新。
- 100 次批量事件。
- 大型 schema 首次构建和局部更新。
- 空闲页面 60 秒 CPU、worker 请求数和 Flutter rebuild 数。

性能测试应使用 profile/release 构建，分别报告中位数、P95 和最大值。功能回归至少覆盖 core 全部测试与 `quickjs_ui_node_test.dart`。
