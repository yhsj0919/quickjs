# 更新日志 / Changelog

## Unreleased

- 移除插件对 FVP 的直接依赖和自动注册；桌面后端与 Android 兼容版本均改由宿主应用选择。
- Removed the direct FVP dependency and automatic registration; host applications now choose the desktop backend and Android compatibility version.

## 0.2.1

- 升级 FVP 视频后端，并补充 Linux 与 Apple 平台的宿主依赖配置说明。
- 升级到 `lemon_js ^0.2.1` 与 `lemon_js_ui ^0.2.1`。
- Upgraded the FVP video backend and documented Linux and Apple host requirements.
- Upgraded to `lemon_js ^0.2.1` and `lemon_js_ui ^0.2.1`.

## 0.2.0

### 中文

- **破坏性更新：** 本版本随 `lemon_js` / `lemon_js_ui` 的公开 API 重构同步迁移，不提供旧
  API 兼容层；升级前请阅读
  [破坏性 API 迁移指南](../../docs/breaking_api_migration.md)。
- renderer builder 不再作为公开 API；视频组件统一通过 `JsUiPlugin` 注册。
- TypeScript props 删除任意属性索引签名，并补全 `showLoading` 和资源引用类型。
- 统一播放控制、事件载荷、进度节流和播放器生命周期约定。

### English

- **Breaking update:** This release follows the `lemon_js` / `lemon_js_ui` public API refactor and does
  not provide a legacy compatibility layer. Read the
  [breaking API migration guide](../../docs/breaking_api_migration.md) before upgrading.
- Removed the renderer builder from the public API; video components are now registered through
  `JsUiPlugin`.
- Removed the arbitrary TypeScript props index signature and added explicit `showLoading` and resource
  reference types.
- Standardized playback controls, event payloads, progress throttling, and player lifecycle behavior.

## 0.1.1

### 中文

- 重写 README，补充完整的 Flutter 插件注入、独立 JS 页面、代码提示配置和真实示例链接。

### English

- Reworked the README with complete Flutter plugin injection, a standalone JavaScript page, editor setup,
  and links to the runnable examples.

## 0.1.0

### 中文

- 提供 `quickjs_ui/video_player` JS 模块和 Flutter 原生视频播放器组件。
- 支持播放、暂停、循环、进度、跳转、倍速和视频画面适配。
- 支持 Android、iOS、macOS、Linux、Windows 和 Web 的 `video_player` 集成。
- 桌面端可选使用 FVP 后端，以兼容部分开发板的视频渲染问题。

### English

- Added the `quickjs_ui/video_player` JavaScript module and native Flutter video player component.
- Added playback, pause, looping, progress, seeking, playback speed, and video fitting support.
- Added `video_player` integration for Android, iOS, macOS, Linux, Windows, and Web.
- Added optional FVP desktop backend registration for video rendering compatibility on selected devices.
