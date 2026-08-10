# Lemon JS 工作区

本仓库采用 Dart Pub Workspace 管理以下软件包：

- `packages/lemon_js`：面向 Flutter 的 QuickJS JavaScript 运行时；
- `packages/lemon_js_ui`：由 `lemon_js` 驱动的声明式动态 UI；
- `packages/lemon_js_ui_video_player`：供 `lemon_js_ui` 使用的视频播放器组件扩展。

完整示例位于 `examples/lemon_js_example`。仓库级检查可运行
`tool/verify.ps1` 或 `tool/verify.cmd`。

原生 Release 优化和 Android 16 KB 内存页支持说明见
[`docs/native_release_build.md`](docs/native_release_build.md)。

## 文档导航

- **核心运行时（`lemon_js`）**：从 [`packages/lemon_js/README.md`](packages/lemon_js/README.md) 开始，重点查看运行时、Context、模块加载、插件、宿主能力注入和类绑定生命周期。
- **动态 UI（`lemon_js_ui`）**：使用方法见 [`packages/lemon_js_ui/docs/usage.md`](packages/lemon_js_ui/docs/usage.md)，架构见 [`packages/lemon_js_ui/docs/architecture.md`](packages/lemon_js_ui/docs/architecture.md)，组件约定见 [`docs/quickjs_ui_components.md`](docs/quickjs_ui_components.md)，Canvas 与动画见 [`packages/lemon_js_ui/docs/canvas_and_animation.md`](packages/lemon_js_ui/docs/canvas_and_animation.md)。
- **UI 跨模块能力**：导航、事件、焦点、主题、资源和诊断等共性约定见 [`docs/quickjs_ui_cross_cutting.md`](docs/quickjs_ui_cross_cutting.md)。
- **插件与扩展**：基础清单格式见 [`docs/plugin_manifest.md`](docs/plugin_manifest.md)，混合插件方案见 [`docs/hybrid_plugin_design.md`](docs/hybrid_plugin_design.md)，npm 资源打包见 [`docs/npm_bundling.md`](docs/npm_bundling.md)。
- **发布与性能**：原生发布检查见 [`docs/native_release_build.md`](docs/native_release_build.md)，性能定位必须遵循 [`docs/performance_troubleshooting.md`](docs/performance_troubleshooting.md)。

## 文档约定

仓库自有文档默认使用中文描述。包名、API、协议字段、命令、代码示例和无法准确替换的
技术名词保留英文；引用的 QuickJS 上游及 `third_party` 文档保持原文，便于后续同步。
