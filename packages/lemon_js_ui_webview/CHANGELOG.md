# 更新日志 / Changelog

## 0.1.0

- 新增基于 `webview_all` 的跨平台 `WebView` 组件。
- 新增 Cookie 会话、双向 Promise 桥接和链式 DOM 查询修改 DSL。
- 新增主文档及子 frame 的 document-start 脚本注入。
- 插件实例独立持有 bridge broker，宿主必须显式注册插件实例。
- Windows 固定使用 `webview_all_windows 1.3.8`，规避部分 Windows 10
  环境的图形帧回调注册失败。
- Added a cross-platform `WebView` component backed by `webview_all`.
- Added cookie sessions, a bidirectional Promise bridge, and a fluent DOM rule DSL.
- Added document-start script injection for the main document and child frames.
- Scoped bridge brokers to explicit host-owned plugin instances.
