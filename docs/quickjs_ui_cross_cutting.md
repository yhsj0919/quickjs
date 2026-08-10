# quickjs_ui 跨模块设计

本文记录横跨 Schema、Renderer、自定义组件、导航、资源加载和工具链的设计约束。
这些能力不是某个单独 Widget 的特性，应在拥有边界的架构层统一实现。

## 设计原则

每个跨模块能力都应从 Flutter 原生模型出发，只向 JS 暴露适合 quickjs_ui 的可序列化
子集。当 Flutter 已经提供更可靠的原语时，不复制 Web/DOM 概念，也不创建平行 UI
Runtime。

Flutter 对应原语包括：

- 无障碍：`Semantics`、`SemanticsProperties`、`Tooltip`；
- 主题：`ThemeData`、`ColorScheme`、`TextTheme`；
- 焦点与键盘：`FocusNode`、`FocusTraversalPolicy`、`Actions`、`Shortcuts`；
- 表单：`Form`、`FormField` 和受控输入控件；
- 滚动：`ScrollController`、`ScrollNotification`；
- 动画：`ImplicitlyAnimatedWidget`、`AnimatedContainer`、`AnimatedList`。

### 修复与重构策略

> 功能修复允许重构，不要持续在错误的生命周期或所有权边界上叠加补丁。

性能问题必须先遵循
[`performance_troubleshooting.md`](performance_troubleshooting.md)：开启统一检测、建立
原生基线、进行分层单变量对照并确认根因，之后才允许修改生产实现。

发现 Bug 时依次确认：

1. 明确被破坏的不变量，例如 Renderer 回调不得在 Flutter build 期间同步重建页面。
2. 问题横跨多层时，在拥有边界的层修复，不增加零散的 `addPostFrameCallback`、延迟
   `setState` 或重复 `notifyListeners`。
3. 结构修复完成后删除被替代的临时分支和逐组件帧时序补丁。
4. 在本文及 `docs/quickjs_ui_components.md` 中记录新契约。

## 无障碍与语义

UI Schema 应携带足够信息，使 Flutter 能生成可用的无障碍树。规划字段包括
`semanticLabel`、`tooltip`、`role`、`enabled`、`selected`、焦点顺序及遍历提示。
图片、按钮、表单、自定义 Renderer 和列表项都应提供语义测试。

边界：JS 只返回可序列化 Schema，不接收 Flutter `SemanticsNode` 或平台无障碍句柄。

## 主题与设计令牌

页面应引用宿主提供的稳定设计令牌，而不是依赖 Flutter 主题对象的内部结构。令牌范围
包括颜色、文字、间距、圆角、海拔和动效，并支持深色、高对比度、品牌注入、校验与
回退。Schema 可以引用 `$colors.primary`、`$text.titleMedium` 等名称，但不得依赖
`ThemeData` 的对象形状。

## Renderer → Page 事件管线

所有 Renderer 产生的 UI 事件都必须安全跨越 JS 边界，不能破坏 Flutter build/layout
不变量。统一管线如下：

```text
Widget build / gesture / media callback
  -> QuickjsUiRenderContext.dispatch / dispatchEvent
  -> QuickjsUiEventDispatcher（合并、节流、防抖）
  -> QuickjsUiEventIngress.submit（入队）
  -> 帧结束后刷新
  -> QuickjsUiController.dispatch
  -> QuickjsUiSession.dispatch
  -> notifyListeners
  -> QuickjsUiView setState
```

职责划分：

| 层 | 职责 |
| --- | --- |
| `QuickjsUiEventDispatcher` | 高频事件进入页面 Session 前的 Renderer 侧背压。 |
| `QuickjsUiEventIngress` | 按帧安全投递到 Controller，并保持单次刷新内的事件顺序。 |
| `QuickjsUiController` | Session 串行化、错误呈现，以及 dispatch 完成后一次通知。 |
| `QuickjsUiView` | Controller 变化时执行普通 `setState`，不维护帧时序重建链。 |
| 自定义 Renderer | 只发送可序列化事件，不增加自己的帧后延迟补丁。 |

### 通过 JS state 进行命令式控制

JS state 需要触发 seek、restart、replace source 等原生副作用时，应使用显式可序列化
props 加单调递增 token，而不是隐藏 Renderer 状态。例如：

- `seekPositionMs` 携带目标位置；
- `seekToken` 每次请求 seek 时递增；
- `restartToken` 使用同一模式表示“从头播放”。

这样媒体控制仍然是声明式、可测试的，并与 Renderer → Page 事件入口分离。

## 焦点、键盘与 IME

表单和文字输入应映射到 Flutter `FocusNode`、焦点遍历、`Actions` 与 `Shortcuts`。
JS 接收 `onFocus`、`onBlur`、键盘动作、提交及可序列化组合输入事件，不持有焦点句柄。
`onChanged` 和 IME 高频事件必须使用明确的事件策略。

## Schema 版本与兼容性

发布包和宿主应能协商 quickjs_ui 协议版本。新增 props 必须有安全默认值；弃用 props
应保留到明确的移除版本；未知类型和未知字段按显式策略忽略或失败。版本信息属于
quickjs_ui 和发布包元数据，不应要求 quickjs core 理解 UI Schema。

## 自定义 Renderer 生命周期

视频、地图、相机和平台 View 等自定义 Renderer 应像 `StatefulWidget` 一样管理资源：
初始化时创建，Schema 变化时更新，响应 show/hide、pause/resume，并确定性 dispose。
高频回调统一通过 `QuickjsUiRenderContext.dispatchEvent()`，不得自行增加帧后回调。

边界：自定义 Renderer 可以持有 Flutter/Dart 资源；JS 只能观察可序列化状态和事件。
Stream 只用于真正的数据流，不作为普通 UI 事件的默认通道。

## 资源与媒体模型

asset、file、network、zip 发布包和自定义媒体组件应使用一致的资源解析模型。
`QuickjsUiResourceReference` 将资源分类为 `asset`、`file`、`network`、`data` 或
`custom`，校验 scheme，并携带缓存、校验和及诊断元数据。

资源属性可使用旧字符串，也可使用对象：

```js
Image({
  src: {
    uri: 'https://example.com/avatar.png',
    kind: 'network',
    mimeType: 'image/png',
    sha256: '...',
    cacheKey: 'avatar-v1',
    headers: { Authorization: 'Bearer ...' }
  }
});
```

发布包入口固定为包根 `main.mjs`，`manifest.json` 负责描述与校验，可包含 `modules`、
`resources`、`routes`、`permissions`、`cache` 和 `metadata`。资源元数据不会授予新的
宿主能力；文件、网络、Stream 或 DRM 访问仍需显式宿主策略。完整格式见
[`quickjs_ui_package_format.md`](quickjs_ui_package_format.md)。

核心 Stream 传输只用于响应体、字幕、定时元数据或长期宿主数据源。普通 Widget 事件
和媒体进度继续通过 `QuickjsUiEventIngress`。

## 滚动、手势与列表过渡模型

可滚动节点支持 `initialScrollOffset`、`scrollToOffset`、`scrollToKey`、`scrollToken`、
`scrollDurationMs`、`scrollCurve` 和 `onScroll`。`scrollToken` 是命令式动作边界：JS
更新 token 与目标，Flutter 在下一帧应用命令；JS 不持有 `ScrollController`。

手势只使用结构化描述：`onTap`、`onLongPress`、`onDoubleTap`、`onDragStart`、
`onDragUpdate`、`onDragEnd` 和 `onSwipe`。拖动更新可由事件分发器合并；Swipe 只发送
方向、速度和总位移，不传递原始指针对象。

`ListView.animateItems` 依赖直接子节点的稳定字符串 key，实现基础进入、退出与重排。
JS 始终拥有列表状态，只返回下一份 Schema。

## 开发工具与网络检查器

开发工具按需启用，位于 quickjs_ui diagnostics 模块，不进入 quickjs core。

`QuickjsUiDevOptions` 控制错误浮层、热重载状态保留及 Schema/Diff/资源日志。
`QuickjsUiInspector` 记录生命周期、最近 Action、Renderer Diff 和资源日志。
`exportPageSnapshot()` 导出可 JSON 序列化的 props、state、Schema、manifest、资源、宿主
API、生命周期及 Diff，仅用于调试和问题复现，不用于跨启动持久化。

`QuickjsUiNetworkJournal` 统一记录发布包加载和经过埋点的宿主网络请求，包括 method、
URI、状态、耗时、Body 大小、缓存阶段及结构化错误。它只提供开发期可观测性，不改变
权限、缓存或生产网络语义。

## 一致性测试

一致性测试应覆盖：

- Schema fixture 与旧版本发布包兼容；
- Renderer 冒烟、语义及必要的稳定 Golden 测试；
- mount/show/hide/dispose 和路由生命周期顺序；
- push/replace/pop/result 导航顺序；
- drop/throttle/debounce 和队列上限背压；
- manifest、资源和旧 Schema 版本兼容。

测试应保持确定性；只有确实需要完整 Flutter 应用接线时才依赖示例应用。
