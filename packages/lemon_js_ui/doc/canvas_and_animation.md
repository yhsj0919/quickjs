# quickjs_ui Canvas 与动画契约

本文定义 Canvas、保留场景、Widget 效果和控件状态过渡的首版实验契约。这些 API 遵循
`quickjs_ui` 的 `0.1.x` 实验版本策略：兼容新增可以进入补丁版本；不兼容 Schema 变更
必须在更新日志中说明，并由 Schema/Runtime 兼容元数据保护。

## 执行模型

JavaScript 只记录一次可序列化值；Flutter 负责绘制、VSync、插值、命中测试和资源释放。
动画不得逐帧调用 QuickJS。`onFrame` 是可选且受节流的观察事件，不是动画驱动器。

`staticDraw`/`staticCommands` 缓存为 Flutter `ui.Picture`，不得包含动画值；
`draw`/`commands` 由 Painter 在每个本地帧求值。Canvas 通过 `RepaintBoundary` 隔离。

## Canvas 生命周期

- 有状态或保留式 Canvas 必须使用稳定节点 `key`。
- 没有 `sceneKey` 时，当前指令列表属于该 Canvas 节点。
- 首次使用 `sceneKey` 必须提供指令；后续可省略指令并解析页面级保留场景。
- 使用同一 `sceneKey` 重新提交指令会替换保留场景。
- 每个页面最多保留 32 个场景，优先淘汰最早条目；页面 Session 释放时清空。
- `playToken`、指令内容或 `reverse` 变化会启动新的本地播放代次。
- `paused: true` 停止计时并保留已用时间，恢复后从该时间继续。
- `reverse` 仅支持有限时间线；重复或 epoch 动画不允许反向播放。
- 每个有限播放代次在最终帧绘制后只发送一次 `onAnimationEnd`；重复及 epoch 动画不会完成。

Canvas 尺寸使用 Flutter 逻辑像素。Flutter 在光栅化时应用设备像素比，Schema 作者不应
自行将坐标乘以 DPR。

## 指令与限制

首版契约包括矩形、圆角矩形、圆、圆弧、直线、路径、文字、快照图像、粒子网格、
save/restore、平移、旋转、缩放、矩形裁剪、绘制透明度、描边/填充及受支持的混合模式。
本契约不承诺完整兼容浏览器 Canvas 2D。

安全限制属于协议的一部分：

- 每个已提交指令列表最多 10,000 条指令；
- 每个列表最多 20,000 个路径片段；
- 最多嵌套 128 次 `save()`，且 `save()`/`restore()` 必须配对；
- Canvas 的 `frameIntervalMs` 必须在 16 到 60,000 ms 之间；
- Canvas 的 `animationFrameIntervalMs` 必须在 4 到 1,000 ms 之间，用于限制动画时间线
  的本地推进频率；省略时直接跟随 VSync；
- 未知指令、无效颜色、非有限数值及缺失保留场景均作为 Schema/渲染错误拒绝。

优先使用 `drawSnapshotParticleGrid` 等专用指令，而不是数千条通用指令。不变内容放入
`staticDraw`；大型显示列表需要立即重放时使用保留式 `sceneKey`。

## 快照与图像

`SnapshotBoundary` 将子树捕获为不透明、不可变的页面级句柄。像素字节不会跨越
JavaScript Bridge。句柄仅在创建它的页面 Session 中有效，保留场景必须通过 Canvas
`resources` 插槽传递。快照存储受条目数和像素数限制，会淘汰旧的未引用条目，并随
Session 一起释放。

需要无捕获延迟启动播放时，应在交互前预先捕获。不要把快照句柄持久化到服务器 payload、
应用数据库或其他页面 Session。

## Widget 与控件动画

通用效果（`opacity`、`transform`、`clipRadius`、`blur`、`backdropBlur` 和
`colorFilter`）使用与 Canvas 相同的 `animate()` 数值描述及播放控制。播放状态需要跨
Schema 重建保留时，必须使用稳定节点 `key`。有限效果每个播放代次发送一次
`onAnimationEnd`。

控件状态过渡独立处理：`stateTransition` 在解析后的 `normal`、`hovered`、`focused`、
`selected`、`pressed` 和 `disabled` 样式间插值。`durationMs: 0` 或
`stateTransition: false` 会立即应用新状态。Flutter 的“减少动态效果”设置也会禁用
控件状态过渡。业务代码必须提供等价的静态最终状态，不能让语义只依赖动画。

## 保留式粒子流

`ParticleFlow` 是大量 Widget 粒子的首选载体，适合共享同一纵向循环运动的场景。
JavaScript 只提供一次可序列化轨迹和保留子 Widget；Flutter 用一个时钟推进所有粒子，
并重绘单个 `Flow` 图层，无需每帧重建各个子节点。

- `width` 和 `height` 是必填的逻辑像素边界。
- `particles.length` 必须等于 `children.length`。
- Each particle defines `fromX`, `toX`, `fromY`, `toY`, and `durationMs`.
  Optional start/end pairs interpolate opacity, scale, and rotation; `phaseMs`
  offsets its loop without creating another clock.
- `frameIntervalMs` 限制 JS `onFrame` 采样回调的绘制频率；省略时跟随显示器 VSync。
- `animationFrameIntervalMs` 限制 Canvas 动画时间线的本地推进频率；省略时每个 VSync
  推进一次。
- `paused` 保留已用时间；修改 `playToken` 会把全部粒子作为同一代次重启。

视觉元素必须保持普通 Flutter Widget（例如已解码图片精灵）时使用该组件；只有基础图元
时优先使用 Canvas。不要为每个粒子创建独立 Ticker，否则即使共用时间线也会成倍增加
监听、重建和图层工作。

## 性能验收

### 自适应效果质量

宿主可以保留完整质量，也可启用由帧耗时驱动的本地降级，且无需重建 JavaScript 页面：

```dart
final performance = JsUiPerformanceController(
  mode: JsUiPerformanceMode.auto,
);
final renderer = JsUiRenderer(
  onEvent: handleEvent,
  performanceController: performance,
);

// 所属页面/Session 结束时同时释放二者。
renderer.dispose();
performance.dispose();
```

`JsUiView` 默认创建 auto 控制器，读取 `View.of(context).display.refreshRate`，
并以一个刷新周期作为预算（120 Hz 为 8.33 ms、90 Hz 为 11.11 ms、60 Hz 为
16.67 ms）。显式传入 `targetFrameBudget` 可覆盖该推导。直接使用
`JsUiRenderer` 时为兼容性默认采用 `high`；注入控制器可启用自动采样。

默认模式为 `high`，用于保持兼容且不进行全局帧采样。`auto` 从 `high` 开始，连续
24 个慢帧后降级，连续 240 个稳定帧后才升级；非对称窗口用于避免质量振荡。宿主也可
强制指定 `high`、`balanced`、`low` 或 `off`。

质量变化只发生在 Flutter 内部：

- `high`：完整效果，最多 4,096 个快照粒子碎片；
- `balanced`：blur 上限为 12，粒子网格约 1,024 个碎片；
- `low`：移除背景模糊和颜色滤镜，blur 上限为 4，粒子网格聚合至约 256 个碎片；
- `off`：效果动画解析到有限最终状态、移除滤镜、停止 Canvas Ticker，并直接绘制
  快照粒子过渡的目标图像。

控制器取 Flutter build 与 raster 耗时中的较大值和预算比较。设备名称启发式判断不作为
主要信号，因为热降频和页面复杂度会在 Session 中变化。宿主拥有注入的控制器，必须在
所有使用它的 Renderer 释放后再释放控制器。

`MediaQuery.disableAnimations` 会暂时把 Canvas 和通用效果的有效质量强制设为 `off`，
但不会丢弃之前的自适应质量；系统设置取消后恢复原质量。Inspector 性能页签和导出的
页面快照会显示刷新率、预算、模式/质量、减少动态效果状态、build/raster P50/P90/P99、
连续慢帧/稳定帧数及最近一次切换原因。此外还显示 Canvas 数、动画 Canvas 数、指令与
Path 片段数、保留场景、快照数量/像素、请求与实际粒子数、重绘次数、Dart Painter CPU
P50/P90/P99、拒绝指令及原因，以及被限制或禁用的 blur、backdrop-blur、color-filter
和 Ticker 数量。Painter CPU 耗时衡量 Dart/UI 侧显示列表处理；GPU 成本以 Flutter
raster 耗时为准。

仓库中的 Widget 基准只用于发现回归，不代表 GPU 或设备基准。宣布版本可用于生产前，
应在有代表性的低端 60 Hz Android 设备和 120 Hz 目标设备上，以 Flutter Profile 模式
运行示例，并记录以下场景的 UI/raster 帧耗时和内存：

1. 1,000、5,000 和 10,000 个动画图元；
2. 多个同时可见的 Canvas 节点；
3. 大型快照捕获与粒子播放；
4. 重复进入/退出页面及前后台切换；
5. 40 个混合动画控件。

验收要求：不得持续超过帧预算（60 Hz 为 16.67 ms，120 Hz 为 8.33 ms）；页面释放后
不得残留 Ticker；重复导航后保留场景/快照内存不得单调增长。应使用 DevTools 的 Frame
Analysis 和 Memory；不得把 Widget 测试 Stopwatch 结果当作设备 raster 性能。

示例应用 Particle FX 的最后一个入口 **Performance Lab · 自适应效果质量**，组合了
1,000/5,000/10,000 个本地动画 Canvas 图元、通用滤镜、Widget 动画和快照粒子过渡。
Flutter 宿主持有性能控制器，支持手动选择 `auto/high/balanced/low/off`，并直接显示
实时序列化性能快照，不通过 JavaScript 传递帧统计。

使用 **开始采样** 排除两秒预热，停止后可复制带版本的 JSON 报告。报告包含帧数、慢帧/
严重慢帧、build/raster P50/P90/P99/max、质量切换及各质量持续时间、显示/构建元数据和
当前 Canvas/效果场景指标。宿主也可调用 `startSession(...)` 与 `stopSession()`；固定质量
模式同样会采样，便于重复进行 `high` 与 `low` 的 Profile 模式 A/B 对照。
`toJson()` 与平台无关，宿主可以保存、上传或复制结果。

常用本地回归命令：

```bash
.\tool\verify.cmd -Mode ui
.\tool\verify.cmd -Mode ui -Benchmark
```

请从仓库根目录运行这些命令。配置后脚本会使用 `QUICKJS_DLL_PATH`；否则会查找已有的
Windows 示例构建，并在必要时构建 Debug 示例。传入 `-SkipNativeBuild` 可在缺少构建时
直接失败，而不是触发构建。
