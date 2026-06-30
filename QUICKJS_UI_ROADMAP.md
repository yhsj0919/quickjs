# quickjs_ui Roadmap

## quickjs_ui：独立 UI 包开发计划

目标：新建独立包 `quickjs_ui`，把 JS 写成页面逻辑和 UI 描述，再由 Flutter 原生 Widget 渲染。
`quickjs_ui` 依赖 `quickjs`，但不把 UI 协议、渲染器、组件库、页面路由、资源加载策略并入
`quickjs` core。

### 设计原则

- [ ] JS 是页面的主控制方：负责页面结构、状态、事件处理、业务控制流和页面间行为决策。
- [ ] Flutter 默认只负责页面绘制：把 JS 返回的 UI schema 渲染为原生 Widget，并处理 layout、paint、
  input bridge 和生命周期挂接。
- [ ] Flutter 不默认接管业务状态；除非宿主显式暴露 provider / host API，否则状态来源只在 JS 页面内。
- [ ] JS 与 Flutter 可以互相调用，但必须通过显式注册的 host API、action handler、route registry 或
  `QuickjsHostMount`，不做隐式全局能力注入。
- [ ] 双向调用只传递 structured value，不传递 Flutter Widget、Dart object handle、JS function handle
  或不可序列化对象。

### 核心边界

- [ ] `quickjs` core 只继续提供 runtime、plugin、module、host mount、structured value codec 和 debug 能力。
- [ ] `quickjs_ui` 独立承载页面协议、UI schema、Flutter renderer、组件库、事件分发和页面生命周期。
- [ ] JS 不直接操作 Flutter Widget，不暴露 DOM/CSSOM/WebView，也不把 Flutter class 暴露给 JS 页面。
- [ ] JS 页面默认没有网络、存储、文件系统等能力；需要时由宿主显式传入 `QuickjsHostMount` / provider。
- [ ] 第一版先做协议和渲染，不先做 `.ux` / template 语法；后续 DSL 只作为编译到协议的语法糖。

### 页面协议

第一版 JS 页面使用普通 ES module，不引入模板文件。页面默认导出一个对象描述，便于开发工具做
类型提示、自动补全和静态检查：

```js
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'CounterPage',
  props: {
    title: 'string'
  },
  createState(props) {
    return { count: 0 };
  },
  build(state, props, page) {
    return Column({
      mainAxisAlignment: 'center',
      crossAxisAlignment: 'stretch',
      children: [
        Text(`Count: ${state.count}`),
        ElevatedButton({ child: Text('Add'), onPressed: page.increment() })
      ]
    });
  },

  increment(state) {
    return { ...state, count: state.count + 1 };
  }
});
```

- [ ] 固定页面对象协议：`default export` 为 page object，包含可选 `name`、`props`、`metadata`，
  以及 `createState(props) -> state`、`build(state, props, page) -> UiNode` 和页面方法。
- [ ] `build()` 返回 JSON-compatible UI schema，不返回 JS function、handle、Dart 对象或 Flutter Widget。
- [ ] 事件绑定使用 `page.methodName()` 生成可序列化 descriptor；页面作者不手写 action 字符串。
- [ ] 状态更新支持 `setState(patch | updater)` 语义：JS 页面可主动更新局部 state，并触发页面刷新。
- [ ] `dispatch()` 可返回新 state，也可通过 `setState()` 提交动态更新；两者最终统一进入 renderer update pipeline。
- [ ] renderer update pipeline 支持 schema diff / patch；未变化的节点不参与刷新，避免整页无差别 rebuild。
- [ ] diff 第一版基于 stable key、节点类型和 props hash 判断变化；没有 key 的列表节点按保守策略刷新。
- [ ] 页面调用走 `QuickjsPluginClient` 或等价封装，复用插件 validate/init/call/dispose 生命周期。

### 开发工具与编辑提示

- [ ] 提供 `quickjs_ui` JS helper SDK，例如 `Page()`、`Column()`、`Text()`、
  `ElevatedButton()`，并由 `Page()` 根据页面方法自动生成 `page.increment()` 这类事件方法，
  让页面作者获得 IDE 自动补全和参数提示。
- [ ] 提供 TypeScript declaration：`quickjs_ui.d.ts`，描述 page object、UiNode、事件对象、props/state
  约定和默认控件属性。
- [ ] 提供 JSON Schema：`quickjs_ui.schema.json`，用于校验纯对象 UI schema、生成编辑器提示、
  以及在 CI 中检查页面描述。
- [ ] `.d.ts` 和 JSON Schema 的控件定义以 Flutter 风格属性为主，补全结果优先展示 `child`、
  `children`、`mainAxisAlignment`、`decoration`、`style` 等 Flutter 习惯字段。
- [ ] 页面仍可直接导出 plain object；`Page()` 只做类型辅助和协议适配，不成为复杂运行时框架。
- [ ] 示例页面优先使用 `import { Column, Page, Text } from 'quickjs_ui'` 和 `Page({ ... })`
  展示推荐写法，同时保留 plain object 的兼容测试。

### Dart API 草案

```dart
final view = QuickjsUiView.asset(
  path: 'assets/pages/counter.mjs',
  initialProps: {'title': 'Counter'},
);
```

```dart
final fileView = QuickjsUiView.file(
  path: 'C:/pages/counter.mjs',
);
```

```dart
final networkView = QuickjsUiView.network(
  url: Uri.parse('https://example.com/pages/counter.mjs'),
);
```

```dart
QuickjsUiView.plugin(
  plugin,
  initialProps: const <String, Object?>{},
  mounts: <QuickjsHostMount>[
    appApiMount,
  ],
);
```

- [ ] `QuickjsUiView.plugin(plugin, {initialProps, mounts})`：直接渲染一个已构建的 `QuickjsPlugin` 页面。
- [ ] `QuickjsUiView.asset(path, {initialProps, mounts})`：从 Flutter asset 加载 JS module 页面；单文件和多文件入口统一走
  `path`。
- [ ] `QuickjsUiView.file(path, {initialProps, mounts})`：从本地文件系统入口加载 JS module 页面，用于桌面调试、开发工具和
  外部页面目录。
- [ ] `QuickjsUiView.network(url, {initialProps, mounts})`：从 network 入口加载 JS module 页面；默认只做显式入口加载，
  缓存、校验和权限由后续 network loader 策略补齐。
- [ ] `QuickjsUiController`：提供 `reload()`、`dispatch(event)`、`state`、`dispose()` 和错误状态观察。
- [ ] `QuickjsUiErrorBuilder`：渲染 JS exception、schema error、runtime closed、资源加载失败等错误状态。

### 可吸收的实现参考

从外部 quickjs_ui demo 中吸收工程结构，但不照搬公开页面写法。公开协议仍保持 `Page(...)` 和
Flutter 风格控件名称。

- [ ] `QuickjsUiSession`：把 runtime、page plugin、state、current tree、dispatch、refresh、dispose
  从 controller 中拆出，controller/view 只负责绑定 Flutter 生命周期和监听状态变化。
- [ ] `QuickjsUiComponentRegistry`：内置组件 + 宿主自定义组件注册，支持注册、替换、注销和列出组件类型。
- [ ] `QuickjsUiProps`：集中解析 Flutter 风格属性，例如 color、EdgeInsets、BorderRadius、BoxFit、
  Alignment、FontWeight、opacity，替换 renderer 中分散的私有解析函数。
- [ ] `QuickjsUiRenderContext`：renderer 构建子节点、派发事件、读取 theme/resource 时统一走 context。
- [ ] `QuickjsUiNetworkLoader`：网络 `.mjs` 页面加载支持 ETag、304、错误状态和可替换 HTTP client。
- [ ] 自定义组件 JS module 模板可参考外部 demo，但生成的组件仍返回 Page/UI schema，不直接操作 Widget。

### 开发模式与调试

- [ ] 提供 `QuickjsUiDevOptions`：控制 dev reload、error overlay、schema dump、diff log、resource log。
- [ ] 支持页面热重载：JS 页面、bundle manifest、schema 或资源变化后可 reload 当前页面。
- [ ] 热重载默认保留 route params / initial props；是否保留 JS state 由 dev option 控制。
- [ ] error overlay 展示 JS stack、schema path、resource key、route name、当前 action 和 structured error。
- [ ] 提供 `QuickjsUiInspector`：查看 page name、props、state、当前 UI schema、resource graph、mounted host APIs。
- [ ] 支持导出当前 page snapshot：props、state、schema、resource manifest 和最近一次 action，方便复现问题。
- [ ] 支持 rebuild / diff 诊断日志：记录哪些节点刷新、哪些节点因 key/type/props 未变化被跳过。

### 资源与多文件页面

`quickjs_ui` 支持类似网页的多文件页面组织，但运行模型仍是 JS page object + UI schema，不引入
DOM/CSSOM/WebView。资源加载属于 `quickjs_ui` / 应用层能力，不进入 `quickjs` core。

- [x] 支持单页面多文件 bundle：本地开发优先从入口 `.mjs` 加载，递归解析静态相对 `import`；manifest 用于发布、
  远程、缓存和校验场景。
- [ ] 提供 `QuickjsUiBundle` / `QuickjsUiResourceResolver`：统一解析 asset、plugin zip、内存资源和可选远程资源。
- [ ] 支持第三方资源接入：图片、字体、JSON 数据、JS helper module、主题包等统一经过 resolver；
  allowlist、checksum、MIME/type 校验作为可配置安全策略。
- [ ] 支持类网页路径引用：页面内可用相对路径引用 `./components/card.js`、`./theme.json`、
  `./images/avatar.png`，由 bundle resolver 归一化为安全资源 key。
- [ ] 支持 `import` 多 JS module，但 module graph 仍交给 `quickjs` plugin/module 能力承载。
- [ ] network 资源默认关闭；宿主开启后可按环境配置 origin allowlist、缓存策略、超时、大小限制、
  checksum 和 MIME/type 校验。
- [ ] 类网页 network 加载必须支持刷新：重新请求入口或 manifest、按缓存策略刷新资源、重建 JS page runtime，
  并保留或重置 state 由调用方选择。
- [ ] 提供 `refresh()` / `restart()` / `reload()` 语义：`refresh` 只重 render，`restart` 用当前 plugin 重新 init，
  `reload` 重新加载 asset/file/network 源码。
- [ ] 资源加载错误进入统一 error boundary，页面可展示 loading / error / retry 状态。
- [ ] 第三方资源不能自动获得 host capability；资源来源和 JS 权限是两套独立策略。

### 页面包 Manifest 与缓存

- [ ] 定义 `quickjs_ui_manifest.json`：描述 entry、resources、routes、permissions、version、checksum。
- [ ] manifest 支持声明页面入口、资源表、相对路径映射、资源 MIME/type、资源 hash 和可选 preload。
- [ ] 支持 bundle 版本号和资源 checksum 校验，便于 zip/plugin/远程包更新和回滚。
- [ ] 支持资源缓存策略：asset/plugin 资源按 version/hash 缓存，远程资源按 ETag/max-age/version key 缓存。
- [ ] 开发模式默认禁用强缓存或提供 cache busting；生产模式按 manifest version 和 checksum 命中缓存。
- [ ] network bundle 刷新支持 force refresh、conditional refresh、stale-while-revalidate 三种策略。

### 主题与布局能力

- [ ] 支持 Flutter 风格 `Theme` / `ThemeData` 子集：颜色、字体、字号、圆角、间距、按钮样式、输入框样式。
- [ ] JS 页面可读取 theme token 并在 schema 中引用，但默认不能直接修改全局 Flutter theme。
- [ ] 支持暗色模式和宿主 theme 注入；theme 更新后触发受影响节点刷新。
- [ ] 布局控件补充 `Stack`、`Positioned`、`Expanded`、`Flexible`、`Padding`、`Center`、`SizedBox`、
  `SingleChildScrollView`。
- [ ] 表单控件补充 `Form`、`Checkbox`、`Switch`、`Radio`、`DropdownButton`；表单状态和校验规则仍由 JS 控制。

### 异步数据与状态恢复

- [ ] 支持 `async init(props)` 和 `async dispatch(state, event, props)`，异步结果回到统一 state update pipeline。
- [ ] 异步状态提供约定字段或 helper：loading、error、data、retry action。
- [ ] 页面 dispose 后 pending async result 必须取消或忽略，不能更新已销毁页面。
- [ ] 支持页面 state snapshot：序列化当前 JS state，用于开发热重载、后台恢复或页面返回恢复。
- [ ] state snapshot 只保存 structured value；host provider 返回的临时 handle、stream、callback 不持久化。

### 生命周期同步

Flutter 侧 App、Route、Widget 和 resource lifecycle 需要同步到 JS 页面；JS 页面只接收结构化生命周期事件，
不直接持有 Flutter lifecycle object。

- [ ] JS 页面协议补充生命周期 hook：`onMount`、`onShow`、`onHide`、`onPause`、`onResume`、
  `onRouteEnter`、`onRouteLeave`、`onRouteResult`、`onDispose`。
- [ ] Flutter `State.initState` / first render 完成后同步 `onMount`，页面可在此启动数据加载或订阅。
- [ ] Flutter route push/pop/replace、native <-> JSUI 跳转时同步 route lifecycle 和 route result。
- [ ] App lifecycle 同步：前台、后台、暂停、恢复、内存压力等事件转为 structured event。
- [ ] Widget subtree 暂时不可见但未销毁时使用 `onHide` / `onShow`，真正销毁时才触发 `onDispose`。
- [ ] 生命周期 hook 可以返回 state patch、effect descriptor 或 async task；最终仍进入统一 state update pipeline。
- [ ] `onDispose` 必须触发资源清理：timer、stream、pending async、host subscription、resource handle。
- [ ] lifecycle event 顺序需要可预测、可测试，并在 inspector 中记录最近生命周期事件。

### 交互模型

交互默认仍由 JS 决定状态和控制流；Flutter 负责把原生输入事件转换为 structured event，再投递给
JS 页面。事件不传 Flutter object，也不在 schema 中传 JS function。

- [ ] 统一事件 envelope：`{ action, payload, source, timestamp }`，source 可定位控件 key/path。
- [ ] 支持常用手势：tap、longPress、doubleTap、drag、swipe；第一版优先 tap/longPress。
- [ ] 支持滚动事件和滚动控制：`onScroll`、`initialScrollOffset`、`scrollTo(key|offset)`，滚动控制通过
  controller/action bridge 显式触发。
- [ ] 支持焦点管理：`focus(key)`、`blur(key)`、`onFocus`、`onBlur`，用于表单和键盘交互。
- [ ] 支持软键盘相关行为：输入框提交、键盘类型、return key action、键盘弹出后的 viewport 调整。
- [ ] 支持受控输入组件：`TextField` 的 value、selection、composition 状态由 JS 控制或显式同步。
- [ ] 支持弹窗/浮层交互：dialog、bottom sheet、menu、snackbar/toast 通过 host API 或 overlay schema 显式打开。
- [ ] 高频事件需要节流/合并策略，例如 scroll、drag、text composing，避免每帧跨 JS/Flutter 边界。
- [ ] 支持 disabled/loading/pressed/focused/error 等基础交互状态，状态来源仍由 JS schema 描述。
- [ ] 支持语义化和无障碍字段：`semanticsLabel`、`tooltip`、`enabled`、`role`，由 Flutter renderer 映射到原生能力。

### 动画与过渡

动画由 JS 声明意图和参数，Flutter renderer 使用原生动画能力执行。默认不让 JS 每帧驱动动画，
避免跨边界高频调用和 UI 卡顿。

- [ ] 支持基础隐式动画 schema：opacity、scale、slide、size、color、padding、alignment 等属性变化。
- [ ] 支持 transition 描述：`duration`、`curve`、`delay`、`from`、`to`、`onEnd` action。
- [ ] 支持列表 item enter/exit/reorder 的基础过渡，依赖 stable key 判断节点身份。
- [ ] 支持页面转场配置：JSUI -> JSUI、原生 -> JSUI 可声明 transition intent，由 Flutter adapter 决定是否执行。
- [ ] 支持交互状态动画：pressed、focused、loading、error 状态变化可映射为 Flutter 原生动画。
- [ ] 支持动画开关和无障碍降级：宿主可关闭动画或启用 reduced motion。
- [ ] 第一版不做 JS `requestAnimationFrame`、逐帧 canvas 动画、自定义物理引擎和任意 timeline 脚本。

### 原生页面与 JSUI 导航

导航属于 `quickjs_ui` / 应用层集成能力，不进入 `quickjs` core。第一版使用显式 host API 和
Flutter adapter 连接原生页面与 JSUI 页面。

- [ ] `QuickjsUiNavigator`：封装 JSUI 页面 push/pop/replace，并接入 Flutter `Navigator`。
- [ ] 原生 Flutter 页面 -> JSUI 页面：支持传入 `initialProps` / route params，例如
  `QuickjsUiNavigator.pushAsset(context, 'assets/pages/detail.js', props: {'id': 1})`。
- [ ] JSUI 页面 -> 原生 Flutter 页面：通过显式 action descriptor 或 host API 发起导航，例如
  `{ action: 'native.push', route: 'settings', params: {...} }`。
- [ ] JSUI 页面 -> JSUI 页面：支持按 asset/plugin route 跳转，并传递 JSON-compatible params。
- [ ] 页面返回值：支持 `pop(result)`，result 走 structured value codec，可被原生页面或上一个 JSUI 页面接收。
- [ ] route params 与 result 必须是 JSON-compatible / structured value，不传 Dart object、Widget、JS function handle。
- [ ] 导航权限由应用层 route registry 控制；JSUI 不能任意打开未注册原生页面。
- [ ] 支持生命周期事件：页面进入/返回时向 JSUI 派发 `onRouteEnter`、`onRouteResult`、`onRouteLeave`
  或等价事件。

### UI Schema 第一版

最小组件集合采用 Flutter Widget 名称风格，默认控件尽量兼容 Flutter 属性命名和语义，降低
Flutter 开发者学习成本：

- [ ] `Text`
- [ ] `ElevatedButton` / `TextButton` / `OutlinedButton`
- [ ] `Row`
- [ ] `Column`
- [ ] `Container`
- [ ] `Image`
- [ ] `ListView`
- [ ] `TextField`

基础原生控件实现清单：

布局与定位：
- [x] `Row`
- [x] `Column`
- [x] `Container`
- [ ] `Stack`
- [ ] `Positioned`
- [ ] `Padding`
- [ ] `Center`
- [ ] `Align`
- [ ] `SizedBox`
- [ ] `Expanded`
- [ ] `Flexible`
- [ ] `Spacer`
- [ ] `Wrap`
- [ ] `AspectRatio`
- [ ] `ConstrainedBox`
- [ ] `SafeArea`

展示与内容：
- [x] `Text`
- [ ] `RichText` / `TextSpan`
- [ ] `Icon`
- [ ] `Image`
- [ ] `Divider`
- [ ] `VerticalDivider`
- [ ] `Placeholder`
- [ ] `Card`
- [ ] `ClipRRect`
- [ ] `DecoratedBox`

按钮与可点击区域：
- [x] `ElevatedButton`
- [ ] `TextButton`
- [ ] `OutlinedButton`
- [ ] `IconButton`
- [ ] `FloatingActionButton`
- [ ] `GestureDetector`
- [ ] `InkWell`

滚动与列表：
- [ ] `SingleChildScrollView`
- [ ] `ListView`
- [ ] `GridView`
- [ ] `PageView`
- [ ] `RefreshIndicator`

表单与输入：
- [ ] `TextField`
- [ ] `TextFormField`
- [ ] `Checkbox`
- [ ] `Switch`
- [ ] `Radio`
- [ ] `Slider`
- [ ] `DropdownButton`
- [ ] `Form`

导航与页面结构：
- [ ] `Scaffold`
- [ ] `AppBar`
- [ ] `BottomNavigationBar`
- [ ] `TabBar` / `TabBarView`
- [ ] `Drawer`

反馈与状态：
- [ ] `CircularProgressIndicator`
- [ ] `LinearProgressIndicator`
- [ ] `SnackBar`
- [ ] `AlertDialog`
- [ ] `BottomSheet`
- [ ] `Tooltip`

动画与过渡：
- [ ] `AnimatedContainer`
- [ ] `AnimatedOpacity`
- [ ] `AnimatedAlign`
- [ ] `AnimatedPadding`
- [ ] `AnimatedSwitcher`
- [ ] `Hero`

Flutter 风格对象写法：

- [ ] 页面基础控件书写风格尽量贴近 Flutter Widget tree，只是把 Dart 构造函数改成 JSON-compatible
  object，例如 `{ type: 'Column', children: [...] }` 对应 `Column(children: [...])`。
- [ ] 控件名默认使用 Flutter Widget 名称：`Text`、`Container`、`Row`、`Column`、`Stack`、
  `Padding`、`Center`、`SizedBox`、`Image`、`ListView`、`TextField` 等。
- [ ] 属性名优先沿用 Flutter 原名：`child`、`children`、`padding`、`margin`、`alignment`、
  `width`、`height`、`mainAxisAlignment`、`crossAxisAlignment`、`decoration`、`style`、
  `onPressed`、`onChanged`。
- [ ] 样式和装饰也尽量贴近 Flutter 对象结构，例如 `TextStyle`、`BoxDecoration`、`BorderRadius`、
  `EdgeInsets`、`Alignment` 使用可序列化对象表达。
- [ ] 仅在 JS/JSON 表达明显更自然时提供简短 alias；alias 必须文档化，并最终归一化为 Flutter 风格属性。
- [ ] 不引入 HTML/CSS 风格命名作为主写法，例如不把 `className`、`onclick`、`background-color`
  作为推荐字段。

默认属性集合优先跟 Flutter 对齐：

- [ ] `padding`、`margin`、`width`、`height`
- [ ] `color`、`backgroundColor`
- [ ] `fontSize`、`fontWeight`
- [ ] `alignment`
- [ ] `gap`
- [ ] `mainAxisAlignment`、`crossAxisAlignment`
- [ ] `enabled`、`loading`、`tooltip`、`semanticsLabel`

设计约束：

- [ ] schema 必须可序列化、可打印、可测试、可重放。
- [ ] renderer 对未知 `type`、未知 style 字段、错误字段类型返回结构化错误，不静默失败。
- [ ] 默认控件属性名尽量沿用 Flutter，例如 `mainAxisAlignment`、`crossAxisAlignment`、`child`、
  `children`、`onPressed`、`decoration`、`style`；确实需要简化时提供文档化 alias。
- [ ] Flutter enum 用字符串表示，例如 `"center"`、`"stretch"`、`"spaceBetween"`；renderer 做严格校验。
- [ ] schema 不做 CSS selector；style 只作用于当前节点。
- [ ] schema 不做浏览器布局模型，直接映射到 Flutter 约束和 Widget 组合。

### 0.1：最小可用原型

- [x] 新建 `packages/quickjs_ui`：独立 Flutter package，依赖 `quickjs`，先提供导出入口、
  `QuickjsUiNode`、`QuickjsUiController` 和 `QuickjsUiView` 骨架。
- [x] 实现 `QuickjsUiView.plugin()`。
- [x] 实现 JS 页面协议：公开写法为 `Page({ createState, build, ...methods })`，底层适配
  `init/render/dispatch`。
- [x] 支持 `export default Page(...)` 自动包装为底层 `init/render/dispatch`，页面作者不需要手写 adapter
  exports。
- [x] 提供 `QuickjsUiPagePlugin.singleFile/asset`，手动构造 plugin 时也能复用 default Page adapter。
- [x] 实现基础 `UiNode` parser 和 Flutter renderer。
- [x] 支持 `Text/ElevatedButton/Row/Column/Container`。
- [x] 支持 button `onPressed` 事件到 JS `dispatch()`。
- [x] 支持 `setState()` 触发页面刷新，先保证状态变更后 UI 正确更新。
- [x] 提供 `Page()` 和首版 `.d.ts`，让开发工具能提示页面对象、控件和事件字段。
- [x] example：counter 页面。
- [~] 测试：schema parser、renderer smoke、event dispatch、JS-owned state、`setState` refresh、
  JS error boundary、dispose。已补测试；当前环境 Flutter CLI 运行测试超时，待可用环境复验。

### 0.1.x：渲染与 Session 打磨

- [x] 引入 `QuickjsUiSession`，沉淀 runtime/plugin/state/tree/dispatch/refresh/dispose 逻辑。
- [x] 引入 `QuickjsUiProps`，集中解析 color、EdgeInsets、BorderRadius、Alignment、FontWeight、BoxFit、
  opacity 等 Flutter 风格属性。
- [x] 引入 `QuickjsUiComponentRegistry` 和 `QuickjsUiRenderContext`，先用于内置组件注册和 renderer 拆分。
- [ ] 保持公开 JS 写法为 `export default Page(...)`，不回退到全局导出函数协议。
- [x] 测试：session lifecycle、props parser、unknown component、custom registry smoke、renderer error boundary。

### 0.2：资源加载、多文件页面与表单

- [x] `QuickjsUiView.asset(path)`：从入口 `.mjs` asset 加载单文件或多文件页面，递归解析静态相对 `import`。
- [x] `QuickjsUiView.file(path)`：从本地文件系统入口 `.mjs` 加载单文件或多文件页面，递归解析静态相对 `import`。
- [x] `QuickjsUiBundle.asset(path)`：从入口 `.mjs` asset 构建多文件 bundle。
- [x] `QuickjsUiBundle.file(path)`：从本地文件系统入口 `.mjs` 构建多文件 bundle。
- [x] `QuickjsUiBundle.network(url)`：从 network 入口 `.mjs` 构建多文件 bundle，递归解析静态相对 `import`。
- [x] `QuickjsUiView.network(url)`：从 network 入口 `.mjs` 加载单文件或多文件页面。
- [x] `QuickjsUiBundle.manifestAsset()`：加载 manifest 描述的发布/远程包格式。
- [x] `QuickjsUiResourceResolver`：统一处理相对路径、asset key、plugin zip 资源和资源错误。
- [x] `QuickjsUiController.reload()`。
- [ ] network bundle 开启后支持基础 `refresh()`：重新拉取入口/manifest/resources 并刷新页面。
- [x] `QuickjsUiNetworkLoader`：支持 network `.mjs` 加载、相对 import 解析、可替换 fetch client 和结构化状态码错误。
- [x] tool：`quickjs_ui_dev_server.dart`，本地 HTTP 服务 `example/assets/quickjs_ui`，用于 network 页面开发调试。
- [x] example：network counter 页面，通过 `QuickjsUiView.network(url)` 加载本地 dev server 页面。
- [x] `QuickjsUiNetworkLoader`：补充 ETag、304 not modified 和内存缓存复用。
- [x] `QuickjsUiNetworkLoader`：提供 request/response/cacheStore/cacheHit 日志回调，demo 可观察缓存命中。
- [x] `QuickjsUiController.refresh()`：只用当前 state 重新 render，不重新加载资源。
- [x] `QuickjsUiController.restart()`：使用当前 plugin 重新初始化页面，不重新加载资源。
- [x] `QuickjsUiController.reload()`：重新加载 asset/file/network 源码并重建页面。
- [ ] `QuickjsUiNetworkLoader`：补充持久缓存策略和 checksum 校验。
- [ ] 支持 `Image/ListView/TextField`。
- [ ] 支持 input `onChanged` 事件。
- [ ] 支持 `TextField` 受控输入、focus/blur、submit 和基础软键盘配置。
- [ ] 补充 JSON Schema，用于编辑器提示和页面对象校验。
- [ ] 支持动态局部刷新：通过 key/type/props diff 跳过未变化节点。
- [ ] 支持 loading / error / empty 状态 builder。
- [ ] 支持首版 error overlay 和 schema/resource 错误定位。
- [ ] 支持基础 `ThemeData` token 注入和 `Stack/Padding/Center/SizedBox`。
- [x] example：多文件 bundle counter 页面。
- [ ] example：todo list、profile form、多文件 profile page、第三方图片/主题资源。
- [ ] 测试：asset page、bundle page、remote refresh、relative resource resolve、list render、input event、
  runtime rebuild、unchanged node skip、resource error boundary、theme token、controlled input。

### 0.3：宿主能力与页面能力边界

- [ ] 支持 `mounts` 显式传入。
- [ ] 提供 `QuickjsUiHostApi` 示例：toast、confirm、navigation intent 等应用层能力。
- [ ] Flutter 暴露给 JS 的方法必须显式注册，并声明输入/输出 structured value 形状。
- [ ] JS 调用 Flutter 方法只作为宿主能力访问，不改变“JS 持有页面状态和控制流”的默认模型。
- [ ] 支持 `async init()` / `async dispatch()`，并在 dispose 后取消或忽略 pending result。
- [ ] 支持基础生命周期同步：`onMount`、`onPause`、`onResume`、`onDispose`。
- [ ] 支持页面声明 `permissions`，宿主按 route/bundle/plugin 维度授权。
- [ ] 支持 dialog、bottom sheet、snackbar/toast 等交互能力的 host API 示例。
- [ ] 页面权限只作为应用层策略，不由 `quickjs_ui` 自动授予能力。
- [ ] example：调用 Dart host API 的设置页。
- [ ] 测试：未启用能力时报错、启用能力后可调用、async state update、dispose/stop 取消 pending provider。

### 0.3.1：原生 / JSUI 页面互通

- [ ] 实现 `QuickjsUiNavigator` 和 route registry。
- [ ] 原生 Flutter 页面 push JSUI 页面并传参。
- [ ] JSUI 页面请求打开原生 Flutter 页面并传参。
- [ ] JSUI 页面 push 另一个 JSUI 页面并传参。
- [ ] 支持 `pop(result)` 和 route result 回传。
- [ ] 支持页面转场 transition intent，由 Flutter route adapter 映射为原生转场。
- [ ] 同步 route lifecycle：`onRouteEnter`、`onRouteLeave`、`onRouteResult`。
- [ ] 支持页面 state snapshot，用于 route 返回、后台恢复和开发 reload 场景。
- [ ] example：原生列表页 -> JSUI 详情页 -> 原生设置页 -> 返回结果。
- [ ] 测试：params 传递、result 回传、未注册 route 拒绝、dispose 后 pending navigation 取消。

### 0.4：组件化

- [ ] Dart 侧自定义 renderer registry：允许宿主注册自定义 `type` 到 Flutter Widget builder。
- [ ] JS 侧轻量组件约定：组件仍返回 UI schema，不直接返回 Widget。
- [ ] 支持 props 下发和事件上抛的受限协议。
- [ ] 支持完整页面可见性生命周期：`onShow`、`onHide`、`onMount`、`onDispose`。
- [ ] 支持滚动控制和常用手势：`onScroll`、`scrollTo`、longPress、drag/swipe 的受限事件模型。
- [ ] 支持事件节流/合并策略，避免 scroll/drag/text composing 高频跨边界调用。
- [ ] 支持基础隐式动画和列表 item enter/exit/reorder 过渡。
- [ ] 补齐表单控件：`Form/Checkbox/Switch/Radio/DropdownButton`，状态和校验仍由 JS 控制。
- [ ] 支持自定义组件 JS module 模板，组件函数返回 UI schema，并由 registry 映射到宿主 renderer。
- [ ] example：自定义 `card` / `appBar` 组件。

### 0.4.1：开发体验与调试工具

- [ ] `QuickjsUiDevOptions`：dev reload、error overlay、schema dump、diff/resource log。
- [ ] `QuickjsUiInspector`：查看 page、props、state、schema、resource graph、host APIs。
- [ ] 支持导出 page snapshot，包含 props、state、schema、manifest 和最近一次 action。
- [ ] inspector 记录 lifecycle timeline，包含 route/app/widget 生命周期事件顺序。
- [ ] example：开发调试面板。
- [ ] 测试：snapshot 序列化、diff log、lifecycle timeline、error overlay 信息完整性。

### 0.5：页面包发布格式

- [ ] 定义 `quickjs_ui_manifest.json`。
- [ ] 支持 entry/resources/routes/permissions/version/checksum。
- [ ] 支持 asset/plugin zip/远程 bundle 的统一加载和缓存策略。
- [ ] 支持开发模式 cache busting 和生产模式 version/checksum 缓存。
- [ ] 支持远程 bundle force refresh、conditional refresh、stale-while-revalidate。
- [ ] example：zip UI bundle 页面。
- [ ] 测试：manifest parse、checksum mismatch、cache hit/miss、remote refresh strategy、permission declaration。

### 0.6+：可选 DSL

等 `init/render/dispatch + UiNode schema` 稳定后，再考虑 `.ux` 或 template 语法。DSL 必须编译成
第一版协议，不成为底层运行模型。

- [ ] `.ux` / template compiler 作为可选工具包或构建步骤。
- [ ] template 只生成 JS module 的 `render()` 或 UI schema factory。
- [ ] 不追求兼容 Vue、QuickApp、Vela 完整语法。

### 明确不做

- [-] 不把 `quickjs_ui` 合入 `quickjs` core。
- [-] 不实现 DOM、CSSOM、WebView。
- [-] 不把多文件页面解释为浏览器网页；资源、模块、样式和页面生命周期都走 `quickjs_ui` 自己的受限协议。
- [-] 不把小写 DSL 或全局导出函数协议作为主公开写法；主写法保持 `Page(...)` 和 Flutter 风格控件。
- [-] 不允许 JS 直接创建或持有 Flutter Widget。
- [-] 不在第一版实现复杂 diff、逐帧 JS 动画、slot、scoped style、完整 CSS selector。
- [-] 不默认开放 fetch、storage、file system、navigation 等敏感能力。
- [-] 不默认允许远程 bundle 执行；远程页面包由宿主显式开启，allowlist/checksum/权限作为可配置安全校验。
- [-] 不持久化 stream、callback、host object 等不可序列化运行时资源。
