# 更新日志 / Changelog

## 0.2.1

- 升级 `archive` 依赖，并要求 `lemon_js ^0.2.1`。
- Upgraded the `archive` dependency and now requires `lemon_js ^0.2.1`.

## 0.2.0

### 中文

- **破坏性更新：** 本次重构调整了公开类型、构造入口、参数和 JS helper，且不提供旧名称
  兼容别名。升级前必须阅读
  [破坏性 API 迁移指南](../../docs/breaking_api_migration.md)。
- 公开类型统一使用 `JsUi*`；低层 `JsUiSession` 移至独立的
  `package:lemon_js_ui/lemon_js_ui_session.dart` 入口。
- `JsUiView`、Bundle、Manifest、网络加载、资源引用、导航和生命周期 API 已简化并统一命名。
- 宿主注入模型统一为 `JsUiHostFeatures` 和 `JsUiCapabilityGroup.methods()`。
- 删除重复的 Snapshot Map、Inspector Map、网络刷新和事件合并入口。
- JS helper 删除 `defineComponent/action/event`，页面组件统一使用 `Component()` 和标准事件对象。
- 启用完整公开 API 文档检查，并明确区分稳定导出与内部 renderer/helper 实现。

### English

- **Breaking update:** This refactor changes public types, constructors, parameters, and JavaScript
  helpers. No compatibility aliases are provided. Read the
  [breaking API migration guide](../../docs/breaking_api_migration.md) before upgrading.
- Standardized public types on the `JsUi*` prefix and moved the low-level `JsUiSession` API to
  `package:lemon_js_ui/lemon_js_ui_session.dart`.
- Simplified and standardized `JsUiView`, bundle, manifest, network loading, resource reference,
  navigation, and lifecycle APIs.
- Replaced host injection with `JsUiHostFeatures` and `JsUiCapabilityGroup.methods()`.
- Removed duplicate snapshot-map, inspector-map, network-refresh, and event-coalescing entry points.
- Removed the `defineComponent/action/event` JavaScript helpers in favor of `Component()` and standard
  event objects.
- Enabled complete public API documentation checks and clarified stable exports versus internal
  renderer/helper implementations.

## 0.1.1

### 中文

- 重写 README，增加代码提示优先配置、最小 JS 页面和 Flutter 加载示例。
- 将包内文档迁移到 pub 标准的 `doc/` 目录，并同步修正文档链接。

### English

- Reworked the README with editor setup, a minimal JavaScript page, and Flutter loading examples.
- Moved package documentation to Pub's standard `doc/` directory and updated the related links.

## 0.1.0

### 中文

- 提供由 JavaScript 描述、Flutter 原生渲染的动态 UI 页面运行时。
- 提供 `Page`、内置布局/控件、事件分发、生命周期、导航和宿主能力注入。
- 提供 Canvas 2D、粒子、动画、快照、Overlay、滚动和通用控件效果。
- 提供页面资源包、manifest 校验、网络加载、诊断面板和性能质量降级。
- 提供 `quickjs_ui.d.ts`、Schema 和 `lemon_js_ui:codegen` 代码提示生成工具。

### English

- Added a dynamic UI runtime described in JavaScript and rendered with native Flutter widgets.
- Added `Page`, built-in layouts and controls, event dispatch, lifecycle handling, navigation, and host
  capability injection.
- Added Canvas 2D, particles, animation, snapshots, overlays, scrolling, and general widget effects.
- Added page bundles, manifest validation, network loading, diagnostics, and adaptive performance quality.
- Added `quickjs_ui.d.ts`, schemas, and the `lemon_js_ui:codegen` editor tooling.
