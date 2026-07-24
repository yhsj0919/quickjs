## Unreleased

### quickjs_ui

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
