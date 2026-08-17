# lemon_js_ui（quickjs_ui）架构说明

本文说明 `quickjs_ui` 当前的运行栈、路由、事件流、生命周期模型，以及这次 `Maximum call stack size exceeded` 问题的根因和重构方案。

## 命名边界

- Dart 公开 API 统一使用 `JsUi*`，项目自有类型、方法和变量不使用
  `Quickjs` / `quickjs` 前缀。
- `quickjs_ui` 是已经发布的包名、JavaScript 模块名和协议命名空间，继续保留在
  Dart import、JS import、协议字符串、权限名、资源路径和面向用户的错误信息中。
- `QuickJS` 只用于描述实际 JavaScript 引擎及其原生限制，不作为本项目功能类型的
  命名前缀。
- `mount` 只表示页面或原生组件进入已挂载生命周期；宿主能力进入 JavaScript 使用
  `features` / `inject`，不能再把 `mount` 用作能力注入的同义词。

## 运行栈

`quickjs_ui` 分为五层：

1. JavaScript 页面层

   页面从 `quickjs_ui` 导入 `Page` 和 UI helper，并导出 `Page({...})`。`Page()` 会创建一个有状态的页面运行时对象，负责持有页面 state、props、事件方法、生命周期 hook 和 build commit。

2. Page adapter plugin

   `JsUiPagePlugin` 和 `JsUiBundle.toPlugin()` 把页面模块包装成 QuickJS plugin。现在只暴露 v1 运行时协议：

   - `capabilities()`
   - `mount(props)`
   - `handleEvent(event)`
   - `commit()`
   - `setState(patch)`
   - `lifecycle(event)`
   - `snapshot()`
   - `dispose()`

   旧的 `init/render/dispatch/lifecycleTypes/session*` 协议已移除。重构目标是避免 Dart 和 JS 之间反复传递完整 state，并让调用边界更像原生 UI 框架中的 mounted element/state object。

3. Runtime session

   `JsUiSession` 持有 plugin client、props、Dart 侧 state 快照、当前渲染出的 node tree、生命周期能力和事件队列。权威 state 在 JS 页面运行时中，Dart 只在需要公开 `session.state` 或刷新诊断时同步快照。

4. Controller 和 View

   `JsUiController` 提供 loading/error/node 通知。`JsUiView` 负责加载 asset/file/network/plugin 页面，监听 controller，并把当前 `JsUiNode` 渲染到 Flutter。

5. Renderer

   `JsUiRenderer` 和 `JsUiComponentRegistry` 把 schema node 转成 Flutter widget。内置控件走默认 registry，自定义控件由 Dart 侧注册。

## 页面协议

页面通常这样写：

```js
import { Page, Text, ElevatedButton, Column } from 'quickjs_ui';

export default Page({
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  build(state, props, actions) {
    return Column({
      children: [
        Text(`Count: ${state.count}`),
        ElevatedButton({
          child: Text('Add'),
          onPressed: actions.increment()
        })
      ]
    });
  },

  increment(state) {
    return { count: state.count + 1 };
  }
});
```

页面事件方法和生命周期 hook 返回的是 state patch，不是完整替换后的 state。返回 `null` 或 `undefined` 表示没有状态变化。`Page()` 在 JS 内部合并 patch，并只把 `{ changed, version }` 返回给 Dart。

## v1 运行时协议

`Page()` 返回的运行时对象是唯一协议入口：

- `capabilities()` 返回协议版本和页面声明的 lifecycle hook 列表。
- `mount(props)` 初始化 props/state，返回 `{ version, state }` 快照。
- `handleEvent(event)` 调用页面事件方法，更新 JS 内部 state，只返回 `{ changed, version }`。
- `commit()` 在 dirty 时调用 `build(state, props, actions)`，返回新的 UI node；未 dirty 时返回 `{ changed: false, version }`。
- `setState(patch)` 给宿主侧保留显式 patch 入口。
- `lifecycle(event)` 只处理页面声明过的 hook。
- `snapshot()` 返回 Dart 侧需要的 state 快照。
- `dispose()` 释放 JS 页面运行时内部引用。

这个协议刻意把 dispatch、lifecycle、render 拆开：事件只改状态，commit 才构建 UI，snapshot 单独诊断状态。这样错误位置会落在明确的调用边界上。

## 路由

路由由 `JsUiNavigator` 和 `JsUiRouteRegistry` 处理。目前有两类 route：

- Native route：注册在 `nativeRoutes` 里的 Flutter builder。
- JavaScript asset route：注册在 `jsRoutes` 里的 quickjs_ui 页面。

导航请求是普通 intent。JS 页面可以发出事件，由宿主把它解释成导航 intent。宿主随后通过 route registry 解析 route 名称、参数和页面来源，再创建对应的 Flutter route 或 `JsUiView.asset(...)`。

Route lifecycle 和普通页面事件分离。`JsUiSession.lifecycle(...)` 和 `routeLifecycle(...)` 使用不同队列，避免页面事件、route 通知和 Flutter frame 回调在同一个调用栈中互相重入。

## 事件流

Flutter 到 JS 的事件流程如下：

1. Flutter widget callback 触发。
2. `JsUiRenderContext.dispatch(...)` 包装事件。
3. `JsUiEventDispatcher` 应用 widget 级事件策略：command 保序发送，sample 可以按 key 合并，`throttleMs/debounceMs/dropMs` 按策略处理。
4. `JsUiEventIngress` 把事件排到当前 Flutter frame 之后 flush。
5. `JsUiController.dispatch(...)` 调用 `JsUiSession.dispatch(...)`。
6. `JsUiSession` 调用 JS `handleEvent(event)`。
7. JS 更新内部 state，只返回 `{ changed, version }`。
8. 如果状态变化，Dart 调用 `snapshot()` 同步快照，再调用 `commit()` 生成新 UI tree。

ingress 必须保持 frame-based。flush 过程中产生的 reentrant event 会被延后到下一帧，不能在同一个调用栈里递归处理。

## 生命周期

支持的生命周期 hook：

- `onMount`
- `onShow`
- `onHide`
- `onPause`
- `onResume`
- `onRouteEnter`
- `onRouteLeave`
- `onRouteResult`
- `onDispose`

页面能力由 `capabilities().lifecycle` 显式声明。`JsUiSession` 在调用 JS 前检查 hook 是否存在，未声明的 hook 不会调用 JS。dispose lifecycle 只发送一次，之后再调用 `dispose()` 释放页面运行时。

## 栈溢出问题

观察到的错误是：

```text
QuickJS_EXCEPTION{"message":"Maximum call stack size exceeded","name":"RangeError","stack":""}
```

它最早在 video 页面出现，后来 custom components 页面也能复现。错误位置从 `call=lifecycle` 移到 `call=dispatch detail=method=setExpanded`，说明根因不是播放器本身，而是运行时协议、事件流和生命周期边界在高频场景下不够稳定。

## 根因

主要问题有四个：

1. 旧协议把完整 `state/event/props` 反复跨 QuickJS 边界传递。高频 slider、video progress、展开/收起事件会让转换层成为热点。
2. 旧 dispatch 返回完整 state。即使 state 已经应该由 JS 持有，Dart 仍要在每次 dispatch 后转换完整对象。
3. lifecycle 能力不够显式。页面没有 hook 时也可能进入 JS no-op lifecycle，增加无意义调用和转换。
4. 事件 flush 中可能产生 reentrant event。如果同栈递归处理，会把 Flutter callback、Dart session、QuickJS call 和 render 串成越来越深的调用栈。

## 解决方案

这次处理是协议级重构：

1. JS 页面运行时持有权威 state，Dart 不再在每次事件中传完整 state。
2. `handleEvent()` 和 `lifecycle()` 只返回 `{ changed, version }`，高频调用保持小返回值。
3. `commit()` 独立负责 build，只有 dirty 页面才重新构建 node tree。
4. `snapshot()` 独立同步 state 快照，诊断时能明确区分 state 转换问题和 dispatch 问题。
5. `capabilities()` 显式声明 lifecycle，未声明 hook 不进入 JS。
6. `JsUiEventIngress` 保持 frame-based flush，reentrant event 延后一帧。
7. JS component、page render、dispatch 都保留递归深度保护，错误会在更接近真实问题的位置暴露。

## 诊断方式

runtime 会把 JS 失败包装成：

```text
quickjs_ui runtime call failed call=<call> detail=<detail> ...
```

常见 `call` 值：

- `dispatch`：页面事件方法或事件 payload 问题。
- `render`：`build()` 输出、JS component 递归或 UI node 转换问题。
- `lifecycle`：生命周期 hook 或 route/page lifecycle 流程问题。
- `state`：`snapshot()` 状态快照过深、过大或不可序列化。
- `setState`：宿主侧 patch 合并问题。

排查时先看 `call`，再看 `detail`。如果同一页面同时在 video 和 custom components 复现，优先怀疑协议边界、事件队列或渲染递归，不要继续在单个业务页面上打补丁。

## 窗口大小变化复盘

custom components 页面后续又出现了 `call=dispatch detail=method=setExpanded value=true` 的栈溢出。结合复现方式判断，它大概率和调整窗口大小有关，但不是 resize 直接调用 QuickJS，而是 resize 放大了渲染和事件流里的两个问题。

第一，示例页在 `build()` 中调用 `_customComponentsRegistry()`，每次 Flutter rebuild 都会创建新的 `JsUiComponentRegistry`。窗口大小变化会触发父级 rebuild，`JsUiView.didUpdateWidget()` 看到 registry 引用变化后会 dispose 旧 renderer 并创建新 renderer。这个过程本身不应该调用 JS，但它会和未 flush 的控件事件交错，增加 renderer、event ingress、controller、session 之间的状态切换频率。

第二，`Switch`、`Checkbox`、`Radio`、`DropdownButton` 的 `onChanged` 原来按 command 事件发送。窗口调整期间快速点击 `Switch` 时，日志显示会排入多条 `setExpanded` command，而且可能是重复 value。command 的语义是必须保序、不能合并，适合按钮点击、提交、导航这类离散动作；但 value change 是采样型事件，更接近 slider progress，应该允许同一帧按 key 合并。

处理方式：

1. custom components 示例页的 registry 改成稳定实例，不再在 `build()` 中创建。
2. `Switch`、`Checkbox`、`Radio`、`DropdownButton` 的 `onChanged` 改成 sample/coalesced 事件。
3. 新增 widget 回归测试，模拟反复改变测试窗口尺寸并点击 `Switch`，再等待 ingress flush 完成。

修复后的关键日志应类似：

```text
[quickjs_ui_diag/ingress.flush] ... commands=0 samples=1
[quickjs_ui_diag/ingress.coalesced] ... key=Switch:...:onChanged
```

这说明 resize 期间的重复 value change 已经被合并，不再作为一串 command 压到 JS dispatch 队列。后续规则是：稳定依赖对象不要在 Flutter `build()` 中临时创建；所有连续值变化控件默认走 sample，只有明确的一次性操作才走 command。

video player plugin 页面后续又以 `call=dispatch detail=method=togglePlay` 复现过一次。这个问题和 custom components 的窗口变化问题同源，但触发条件更复杂：

1. example 页面在 `build()` 中调用 `JsUiVideoPlayerPlugin.registry()`，窗口变化或父级 rebuild 会让 `JsUiView` 看到新的 registry 引用，从而重建 renderer。
2. video 页面虽然已经走 v1 协议，但页面 handler 仍大量返回 `{ ...state, ...patch }`。这和新协议的 patch 语义冲突，会让 `togglePlay`、`onProgress`、`onReady`、`seek` 等高频交错事件继续在 JS 内部复制完整 state。
3. 播放器原生控制器会在 `didUpdateWidget`、初始化完成、post-frame、progress listener 中同步播放状态。它们本身不应该直接触发 `togglePlay`，但会增加 render/update 的密度，使排队的 button command 更容易撞上 progress sample 和 renderer 重建。

对应处理：

- video plugin example 的 registry 改成稳定实例。
- video 页面所有 handler 改为只返回 patch；无变化时返回 `null`。
- 增加 video plugin 包内压力测试：加载真实 `video_player_plugin_page.mjs`，先触发 `onReady`，再用大量 `onProgress` 事件穿插 `togglePlay`。

这个案例确认了一条边界：v1 协议只是让 runtime 支持 patch，不会自动阻止页面继续返回完整 state。示例页、文档和类型提示必须持续强调 handler 返回 patch，否则高频页面仍会把旧协议的压力带回来。

custom components 页面随后又复现了一次 `setExpanded`。原因同样是页面 handler 仍返回完整 state：

```js
setExpanded(state, _payload, _props, event) {
  return { ...state, expanded: event.value === true };
}
```

这在低频测试下可能看不出来，但 resize、动画、控件 value change 合并、renderer rebuild 叠加后，完整 state 返回仍会让 dispatch 承担旧协议的复制压力。修复方式是所有 handler 只返回实际变化字段：

```js
setExpanded(state, _payload, _props, event) {
  return { expanded: event.value === true };
}
```

`setEnabled`、`setSize`、`reset` 也按同一规则处理。对应回归测试不再只循环 `setExpanded`，而是混合 `setExpanded/setEnabled/setSize/reset`，更接近真实页面交互。

随后对 `examples/lemon_js_example/assets/quickjs_ui` 和 quickjs_ui 相关测试做了全量清理：所有 handler 中的 `return { ...state, ... }` 和 no-op `return state` 都移除。保留的 `...state.xxx` 只允许用于数组展开或构造校验用的局部对象，不能作为 handler 的返回对象。

`reset` 仍然能够触发 `call=dispatch` 后，说明问题不应继续归因到单个页面方法。后续又做了两处 core 级重构：

1. `JsUiSession` 的操作队列从连续 `.then()` 链改为显式 FIFO drain。高频 dispatch 不再构造越来越长的 Dart Future 链。
2. JS `Page()` runtime 内部增加 event queue 和 async drain。`handleEvent(event)` 只入队事件；真正执行 handler 时由页面运行时循环 drain，reentrant event 不再递归进入 handler。

同时，JS runtime 明确拒绝 handler 返回当前 state 对象：如果 `patch === state`，会抛出“必须返回 state patch”的类型错误。这让旧协议写法更早暴露，不再伪装成普通 dispatch 问题。

## 后续设计规则

- 页面 state 权威归 JS 页面运行时所有。
- 高频调用返回 primitive 或小对象，不返回完整 state/tree。
- 页面事件方法和生命周期 hook 必须返回 patch；不要返回 `{ ...state, ...patch }`。
- no-op 必须返回 `null` 或 `undefined`，不要返回当前 state。
- lifecycle 必须基于显式能力判断。
- event ingress 必须跨 frame flush，禁止同栈递归 flush。
- runtime/session 内部事件队列必须用显式 FIFO drain，避免用递归或不断增长的 Future 链承载高频事件。
- resize/rebuild 不能导致 controller、registry、renderer 等稳定对象无意义重建。
- value change 类控件事件默认按 sample/coalesced 处理，按钮点击、提交、导航等离散动作才按 command 处理。
- core 诊断保持通用，业务日志留在页面或插件内部。
- 协议变更优先整体重构，不保留会拖回旧路径的兼容分支。
