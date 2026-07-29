## Unreleased

### quickjs_ui

* 新增 `QuickjsUiPerformanceController`，支持 high/balanced/low/off 和基于 Flutter
  build/raster FrameTiming、带迟滞窗口的自动效果质量回退。
* Canvas 粒子、blur、backdrop blur、color filter 和本地动画可随质量等级降级，过程不触发
  JavaScript rebuild 或逐帧 Bridge。
* `QuickjsUiView` 自动按显示器刷新率计算帧预算并合并系统 reduced motion；Inspector 新增
  性能页及 build/raster P50/P90/P99、质量等级和降级原因快照。
* Inspector 性能快照增加 Canvas command/Path、scene/snapshot、粒子、重绘、painter CPU
  分位数、命令拒绝原因，以及 blur/filter/ticker 降级计数。
* example 末尾新增自适应性能实验室，集中验证 1k/5k/10k Canvas 图元、Snapshot 粒子、
  通用滤镜、质量手动切换和实时性能指标。
* 性能实验室增加带预热的采样会话和 JSON 报告，记录慢帧、耗时分位数、质量切换时间线、
  设备环境与场景指标；固定质量档位也可采样，供后续 Profile A/B 自动验收使用。
* 新增受控 Canvas 2D display list、静态 Picture 缓存、保留场景和 Flutter VSync 本地动画。
* 新增页面级快照资源、粒子网格绘制，以及 Canvas 手势和可选帧采样事件。
* 新增任意组件通用特效、控件状态样式/过渡、结构化 slot 和统一 Overlay 动画层。
* 增加 Canvas/动画生命周期、协议限制、性能建议和真机验收说明。

## 0.1.1

* 修复 Web 端 callback Promise handle 生命周期问题，避免 `console.*` 连续运行时触发 WASM memory access out of bounds。
* 修复 Web 端 Dart Stream callback 的 async iterator 返回值，避免 `for await` 在第二次 pull 后提前结束。
* 修复 Web 端 `evalAsync` pending jobs pump 与 class binding 连续异步访问卡住的问题。

## 0.1.0

* 集成 QuickJS（原生 FFI + Web WASM）
* 移除 Method Channel / getPlatformVersion 等模板代码
* Web 端基于 quickjs-wasi 实现 `evaluate` 与 `createRuntime`
