# 更新日志 / Changelog

## 0.3.1

- 网页到宿主的请求与响应绑定文档身份，防止旧响应完成新文档的同编号请求。
- 配置观察规则支持替换与撤销，避免自身 DOM 修改触发执行循环。
- 初始化、配置更新、导航命令和加载完成处理按顺序执行，初始化失败时阻止后续命令误用控制器。
- 普通组件重建不再重复执行 DOM 规则，也不会覆盖 `loadUrl` / `loadHtml` 打开的文档；脚本更新重新加载当前显式来源。
- 拒绝重复 bridge ID，取消网页调用监听后允许重新注册。
- 要求 `lemon_js ^0.3.1` 与 `lemon_js_ui ^0.3.1`。

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
