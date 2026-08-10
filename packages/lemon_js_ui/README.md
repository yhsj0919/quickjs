# lemon_js_ui

`lemon_js_ui` 是由 JavaScript 驱动的 Flutter 动态 UI 运行时。JS 页面生成受控的
UI Schema，宿主将其渲染为 Flutter 原生 Widget。

## 开始前：配置代码提示

首次使用时，请先在 Flutter 项目根目录创建 `jsconfig.json`，把 `quickjs_ui` 映射到本包的
类型声明文件。否则页面中的 `Page()`、控件属性、事件回调和 Canvas API 不会显示完整提示。

workspace `path:` 依赖的最小配置：

```json
{
  "compilerOptions": {
    "checkJs": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",
    "baseUrl": ".",
    "paths": {
      "quickjs_ui": ["../packages/lemon_js_ui/js/quickjs_ui.d.ts"],
      "quickjs_ui/*": ["../packages/lemon_js_ui/js/*"]
    }
  },
  "include": ["assets/**/*.mjs"]
}
```

发布版只需将路径改为 pub 缓存中的
`lemon_js_ui-<version>/js/quickjs_ui.d.ts`。插件的附加模块应提供自己的 `.d.ts` 并增加对应
`paths` 映射；也可以交给生成器处理：

```bash
dart run lemon_js_ui:codegen \
  --root assets/quickjs_ui \
  --types path/to/plugin/js/your_plugin.d.ts
```

生成器会扫描 `.d.ts` 中的 `declare module 'quickjs_ui/...'`，自动更新模块映射。修改后在
VS Code 执行 **Developer: Reload Window**。

完整配置和插件类型声明方式见[使用指南中的代码提示章节](docs/usage.md#0-先配置代码提示)。

本包与核心 `lemon_js` 分层维护：`lemon_js` 负责运行时执行、模块、插件、宿主
Mount 和结构化值转换；`lemon_js_ui` 负责页面协议、Schema 解析、渲染、事件、
生命周期和 UI 开发工具。

基本原则：

- JS 页面导出 `Page({ createState, build, ...methods })` 对象；
- `build()` 返回可序列化的 `UiNode` 数据；
- Flutter 将 Schema 渲染为原生 Widget；
- JS 不直接创建 Flutter Widget，也不提供 DOM/CSSOM。

## 定位与市面方案对比

Flutter 动态化方案并不是同一种技术：有的在 Flutter 内实现 Web 运行时，有的把
Flutter 风格代码转换为动态 DSL，也有的只根据服务端 JSON 构建 Widget。
`lemon_js_ui` 选择的是 **QuickJS 逻辑 + 受控 UI Schema + Flutter 原生 Widget**：
首次加载可以提交完整 Schema，频繁更新和大数据组件则逐步采用局部更新及专用数据通道。

`lemon_js_ui` **不是使用 JavaScript 重新实现 Flutter，也不以 JavaScript 承载整个应用**。
Flutter 始终是应用、导航、全局状态和原生能力的主体；JSUI 是一种可嵌入的动态页面能力，
既可以作为独立页面进入 Flutter 导航栈，也可以嵌入现有 Flutter 页面的一块区域，并与宿主
注册的原生组件混合。它提供类似 Web 页面加载、更新和 Bridge 的使用体验，但最终渲染为
Flutter 原生 Widget，不实现 HTML、CSS、DOM 或浏览器环境。

| 方案 | 技术路线 | 应用主体与集成粒度 | 优点 | 缺点或代价 | 更适合的场景 |
| --- | --- | --- | --- | --- | --- |
| [WebF](https://openwebf.com/en/docs/learn-webf/how-it-works) | 在 Flutter 中实现 DOM、CSSOM、布局和 JavaScript 运行环境 | Flutter 提供宿主；Web 技术栈可以承载整页、较完整的 Web 应用，也能与 Flutter 自定义元素混合 | 可使用 HTML/CSS 及 React、Vue、Svelte 等 Web 生态；前端迁移成本低；支持 Flutter 自定义元素 | Web 标准兼容面和运行时复杂度较大；DOM、CSS、布局、Bridge 都需要持续维护；长列表仍需专用组件 | 在 Flutter 应用中承载已有 Web 应用或 Web 技术栈 |
| [Fair](https://github.com/wuba/Fair) | 将接近 Flutter 的代码转换为 DSL/JavaScript，再动态构建 Widget Tree | Flutter 应用仍是载体；动态化对象主要是由 Dart 源码转换得到的完整页面、Widget 或局部替换区域 | Flutter 开发者写法熟悉；直接面向 Flutter Widget；动态化能力较完整 | 编译转换链和 Flutter API 映射复杂；Flutter 升级时兼容成本较高；采用前需验证当前 Flutter 版本支持情况 | 希望保持 Flutter/Dart 风格的整页或局部动态化 |
| [MXFlutter](https://github.com/tencent/mxflutter) | 以 TypeScript/JavaScript 实现 Flutter 的 Widget Tree、State、build 和 setState，目标覆盖完整应用开发模型 | JavaScript/TypeScript 是应用和 Widget Tree 的主体；Flutter 更接近渲染后端 | Flutter 风格直观；JS/TS 可以开发完整应用；前端人员容易理解 | 已基本停止公开演进，公开版本对应 Flutter 1.22；全量模拟 Flutter Widget/API 和双端生命周期的维护成本高 | 完整 JS Flutter 路线的历史架构参考 |
| [dynamic_widget](https://github.com/dengyin2000/dynamic_widget) | 将服务端 JSON 解析成 Flutter Widget | Flutter 是应用主体；JSON 通常只描述一个页面或局部配置区域 | 简单、受控、容易审核；适合配置化页面和 A/B 测试 | 复杂状态、异步流程和业务逻辑需要另建体系；高频更新能力有限 | 表单、活动页、内容页和 Backend-Driven UI |
| [flutter_d4rt](https://pub.dev/packages/flutter_d4rt) | 在应用内解释 Dart，并调用 Flutter API | Flutter 提供宿主；解释执行的 Dart 可以动态创建 Widget，边界取决于宿主暴露的 API | 动态代码仍使用 Dart 语义；理论上更贴近 Flutter API | 解释器、API 暴露、安全边界和版本兼容面较大；生态成熟度需要评估 | 动态 Dart/Flutter 的实验性场景 |
| [Shorebird](https://docs.shorebird.dev/) | 下发已编译 Flutter/Dart 代码补丁 | Flutter 始终是完整应用主体；更新粒度是编译代码补丁，不是嵌入式动态页面 | 可以修复现有 Flutter 代码；业务仍按正常 Flutter 工程开发 | 属于应用补丁而非服务端驱动 UI；不提供受控 Schema 和页面能力模型 | 线上代码修复和应用补丁发布 |
| **lemon_js_ui** | QuickJS 页面逻辑生成受控 Schema，再映射为原生 Widget | **Flutter 始终是应用、导航和原生能力主体；JSUI 只作为独立页面或局部区域嵌入，并可与原生页面、原生组件混合** | 故障和权限可限制在页面 Session；运行时及协议较轻；便于校验、快照和回放；体验类似 Web 页面接入 | 需要维护自己的组件协议和开发工具；不能直接复用 HTML/CSS 或完整 Flutter API；不适合用 JS 承载整个应用 | Flutter 应用中的业务动态页面、局部动态区域和插件页面 |

`lemon_js_ui` 不以复刻 WebF、MXFlutter 或完整映射 Flutter API 为目标。WebF 更像“Flutter
中的 Web Runtime”，MXFlutter 更像“用 JS 实现 Flutter 应用”，Fair 更像“Flutter 代码
动态化”，而 `lemon_js_ui` 的目标是“为 Flutter 应用补充可嵌入、受控的 JS 动态页面”。
如果需求只是静态服务端布局，JSON SDUI 会更简单；
如果需求是直接运行既有 React/Vue 页面，应优先评估 WebF；如果需求是二进制代码修复，
Shorebird 属于另一条技术路线。

因此，`lemon_js_ui` 与 MXFlutter 虽然都包含“JS 生成 Flutter UI”，产品目标并不相同：
MXFlutter 试图让 JS/TS 接管完整 Flutter 应用开发模型；`lemon_js_ui` 则类似 Flutter 应用中的
动态 Web 页面能力，按页面或区域接入，宿主可以随时选择原生实现、JSUI 实现或两者混合。

详细的架构阶段、优先级和非目标见
[`quickjs_ui_evolution.md`](https://github.com/yhsj0919/quickjs/blob/main/docs/quickjs_ui_evolution.md)。

## 0.1 页面协议

页面使用普通 JavaScript 对象编写。`QuickjsUiView.asset(path: ...)` 从 Flutter
Asset 加载页面入口，并自动把默认导出包装进当前插件调用模型：

```js
import { Column, ElevatedButton, Page, Text, setState } from 'quickjs_ui';

export default Page({
  name: 'CounterPage',

  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  build(state, props, actions) {
    return Column({
      mainAxisAlignment: 'center',
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

`build()` 的第三个参数是 `actions`。在 UI 树中使用 `actions.foo()`，并通过页面
方法 `foo(state, payload, props, event)` 实现对应行为。

页面方法与 Flutter `setState` 的约定相似：返回局部状态补丁，或返回
`undefined` 跳过刷新。运行时合并补丁、重新执行 `build()` 并通知 Flutter
监听器，对应 Dart 侧的 `QuickjsUiController.setState()`。

只有辅助函数确实需要在处理器内得到完整合并快照时，才使用
`setState(state, patch)`；普通页面方法应直接返回补丁。

`lemon_js_ui` 将控件 helper 作为 ES Module 注入页面代码。helper 展开后，运行时
输入仍然是可序列化的普通对象。

`QuickjsUiView.asset(path: ...)` 同时支持单文件页面和使用静态相对 `import` 的
多文件页面；本地文件入口可使用 `QuickjsUiView.file(path: ...)`。手动构造插件时，
可使用 `QuickjsUiPagePlugin.singleFile(...)`、
`QuickjsUiPagePlugin.asset(path: ...)` 或 `QuickjsUiBundle.asset(path: ...)`。

0.5 发布包格式采用固定包根结构：`main.mjs` 是运行入口，`manifest.json` 是发布描述。
发布包用于生产分发、远程下发、缓存、checksum 校验和权限声明；开发期多文件加载仍可直接
从任意 `.mjs` 入口递归解析静态相对 `import`。格式说明见
[`quickjs_ui_package_format.md`](https://github.com/yhsj0919/quickjs/blob/main/docs/quickjs_ui_package_format.md)。

发布包加载入口：

```dart
final assetBundle = await QuickjsUiBundle.assetPackage(
  root: 'assets/quickjs_ui/profile/',
);

final fileBundle = await QuickjsUiBundle.filePackage(
  root: 'E:/quickjs_ui/profile',
);

final networkBundle = await QuickjsUiBundle.networkPackage(
  root: Uri.parse('https://example.com/quickjs-ui/profile/'),
  refreshMode: QuickjsUiNetworkRefreshMode.conditional,
  cacheStore: QuickjsUiFileNetworkCacheStore(
    directory: Directory('quickjs_ui_cache'),
  ),
);

final zipBundle = await QuickjsUiBundle.assetZipPackage(
  assetKey: 'assets/quickjs_ui/profile.zip',
);
```

这三个入口都会读取包根 `manifest.json`，校验 `entry == "main.mjs"`、
`modules` 声明、静态相对 import 和声明的 `sha256`。
远程发布包支持三种刷新语义：`conditional` 默认使用 ETag 条件请求，
`force` 跳过条件请求并可通过 `cacheBuster` 追加开发期查询参数，
`staleWhileRevalidate` 命中内存缓存时先返回旧内容并在后台刷新。

`manifest.json` 可以用工具生成或更新，避免手写 module hash：

```bash
dart run lemon_js_ui:manifest --root assets/quickjs_ui/profile --id com.example.profile --version 1.0.0
dart run lemon_js_ui:manifest --root assets/quickjs_ui/profile --check
```

已支持的控件：

- `Text`
- `ElevatedButton`
- `Row`
- `Column`
- `Container`
- `Image`
- `ListView`
- `SingleChildScrollView`
- `TextField`
- `Stack`
- `Padding`
- `Center`
- `SizedBox`
- `Form`
- `Checkbox`
- `Switch`
- `Radio`
- `DropdownButton`
- `Canvas`

`TextField` 支持受控的 `value`，以及 `onChanged`、`onSubmitted`、`onFocus`
和 `onBlur` 事件描述。Flutter 分发事件时会携带当前字符串值。

0.4 示例：

- `../../examples/lemon_js_example/assets/quickjs_ui/custom_components_page.mjs` 展示 JS `Component()`
  模块、受控表单控件、事件描述和基础隐式动画属性。
- `../../examples/lemon_js_example/assets/quickjs_ui/scroll_transition_page.mjs` 展示 `scrollToKey`、
  拖动/滑动事件、`SingleChildScrollView` 和带 key 列表项的过渡效果。
- `../../examples/lemon_js_example/assets/quickjs_ui/dev_panel_page.mjs` 和
  `../../examples/lemon_js_example/lib/pages/quickjs_ui/platform/quickjs_ui_dev_panel_page.dart` 展示
  `QuickjsUiInspectorPanel`、页面快照导出、差异/资源日志和保留状态的重新加载。
- `../../examples/lemon_js_example/lib/pages/quickjs_ui/platform/quickjs_ui_network_inspector_page.dart` 展示发布包加载、
  缓存命中和请求耗时的网络日志页签。
- `../../examples/lemon_js_example/lib/pages/quickjs_ui/platform/quickjs_ui_custom_components_page.dart` 展示使用 Dart
  `QuickjsUiComponentRegistry` 注册自定义 `AppBar` 和 `Card` 渲染器。
- `../../examples/lemon_js_example/assets/quickjs_ui/counter_page.mjs` 是最小的单文件 `Page()` 计数器示例。
- 根示例应用在 `../../examples/lemon_js_example/lib/quickjs_ui_example_pages.dart` 中注册可运行页面。

`QuickjsUiView` 通过 `loadingBuilder`、`errorBuilder` 和 `emptyBuilder` 分别处理
页面加载、加载失败和无渲染节点状态。`placeholder` 保留为加载及空状态的兼容兜底。

`packages/lemon_js_ui/js/quickjs_ui.js` 和
`packages/lemon_js_ui/js/quickjs_ui.d.ts` 提供 `Page()` 及具名控件辅助函数，
用于编辑器提示；它们只服务于编写阶段，运行时仍消费普通对象形式的 UI 结构。

`packages/lemon_js_ui/js/quickjs_ui.schema.json` 提供 JSON Schema，
可用于编辑器提示，以及在 CI 中校验普通对象形式的 UI 结构。

`lib/src/runtime/quickjs_ui_helpers.g.dart` 由
`packages/lemon_js_ui/js/quickjs_ui.js` 生成。修改 JS 辅助文件后，
请在 `packages/lemon_js_ui` 中运行 `dart run tool/generate_quickjs_ui_helpers.dart`。

## Canvas 2D 编写方式

生命周期、限制、兼容边界和设备性能验收标准见
[`docs/canvas_and_animation.md`](docs/canvas_and_animation.md)。

API 风格与浏览器 Canvas 2D 相近。回调在 QuickJS 中执行一次并记录显示列表，
之后由 Flutter 在本地完成渲染和动画。

```js
import { animate, Canvas } from 'quickjs_ui';

Canvas({
  width: 320,
  height: 320,
  staticDraw(ctx) {
    ctx.fillStyle = '#020617';
    ctx.fillRect(0, 0, 320, 320);
    ctx.strokeStyle = '#334155';
    ctx.lineWidth = 2;
    ctx.strokeCircle(160, 160, 130);
  },
  draw(ctx) {
    ctx.save();
    ctx.translate(160, 160);
    ctx.rotate(animate(0, Math.PI * 2, {
      durationMs: 1000,
      repeat: true
    }));
    ctx.strokeStyle = '#22d3ee';
    ctx.lineWidth = 3;
    ctx.lineCap = 'round';
    ctx.drawLine(0, 15, 0, -120);
    ctx.restore();
  }
});
```

常用操作包括 `save`、`restore`、`translate`、`rotate`、`scale`、
`beginPath`, `moveTo`, `lineTo`, `quadraticCurveTo`, `bezierCurveTo`, `arc`,
`fill`, `stroke`, `fillRect`, `strokeRect`, `clearRect`, and `fillText`.
`fillCircle`、`strokeCircle` 和 `drawLine` 是便捷方法。`staticDraw` 会缓存为 Flutter
`ui.Picture`；`draw` 可以包含本地 `animate()` 值，并直接由 VSync 重绘，无需每帧
调用 QuickJS Bridge。

对于需要在输入后立即启动的大型场景，可通过 `sceneKey` 注册一次，随后复用而无需再次
发送 `draw` 或 `commands`。`playToken` 重启本地时间，`paused` 保留场景但停止计时，
`reverse` 反向播放有限时长场景。

```js
Canvas({
  key: 'retained-burst',
  sceneKey: 'burst',
  resources: {
    source: state.sourceSnapshot,
    target: state.targetSnapshot
  },
  paused: state.mode === 'idle',
  playToken: state.run,
  reverse: state.mode === 'restoring',
  ...(publishScene ? { draw: drawBurst } : {})
});
```

保留场景按页面 Controller/Session 隔离、具有容量上限。Renderer 重建时会继续复用，
页面替换或 Controller 释放时才清空。
`ctx.drawImage({ slot: 'source' }, ...)` 不会把快照 ID 写入保留显示列表，因此过渡效果
可以替换源图和目标图，无需重建或重新发送粒子指令。

对于快照消散效果，`ctx.drawSnapshotParticleGrid()` 将整个网格保留为一条原生指令，
而不是把每个碎片展开成通用变换和图像指令：

```js
ctx.drawSnapshotParticleGrid({
  sourceSlot: 'source',
  targetSlot: 'target',
  x: 38,
  y: 120,
  width: 284,
  height: 220,
  columns: 24,
  rows: 18
});
```

可选的 `direction` 可设为 `transition`（默认）、`destroy` 或 `create`。
`bucketCount`、`staggerMs`、`travelMs` 和 `fadeMs` 用于控制本地有限时长动画。

## 控件状态与结构插槽

`ElevatedButton`、`TextButton`、`OutlinedButton`、`Switch`、`Slider`、
`TextField` 和 `TextFormField` 共享一套状态模型。`normal` 是基础样式，活动状态按以下
优先级覆盖：
`disabled > pressed > selected > focused > hovered > normal`.

```js
ElevatedButton({
  leading: Icon({ icon: 'bolt' }),
  child: Text('Run'),
  trailing: Icon({ icon: 'arrow_forward' }),
  gap: 8,
  stateStyles: {
    normal: { backgroundColor: '#172554', foregroundColor: '#dbeafe' },
    hovered: { backgroundColor: '#1e3a8a' },
    focused: { borderColor: '#22d3ee', borderWidth: 2 },
    pressed: { backgroundColor: '#0891b2' },
    disabled: { backgroundColor: '#1e293b' }
  },
  onPressed: actions.run()
});
```

Button 暴露 `leading / content / child / trailing`，文字输入框暴露
`leading / prefix / suffix / trailing`。Switch 和 Slider 通过
`thumbStyle / trackStyle / overlayStyle` 暴露原生视觉结构，各部分使用相同状态名。
Button 和输入插槽接受普通 JSUI 节点，因此新增组合无需发布新版宿主。

状态变化可在 Flutter VSync 上本地插值，无需通过 QuickJS 发送逐帧更新：

```js
ElevatedButton({
  stateTransition: { durationMs: 160, curve: 'easeOutCubic' },
  stateStyles: {
    normal: { backgroundColor: '#155e75', scale: 1, opacity: 1 },
    hovered: { backgroundColor: '#0e7490', scale: 1.02 },
    pressed: { backgroundColor: '#0891b2', scale: 0.96 },
    disabled: { opacity: 0.6 }
  },
  onPressed: actions.run()
});
```

同一个 `stateTransition` 声明可用于 Button、Switch、Slider、TextField 和
TextFormField。颜色、数值、内边距、文字样式、圆角、`scale` 和 `opacity`
共用一套插值流程。默认过渡为 140 ms、曲线为 `easeOutCubic`；将
`durationMs` 设为 `0` 或使用 `stateTransition: false` 可立即切换状态。

Flutter 会遵循系统的“减少动态效果”无障碍设置。在 Web 平台，如果浏览器的
`prefers-reduced-motion: reduce` 生效，`MediaQuery.disableAnimations` 会变为
`true`，JSUI 将停止 Canvas Ticker 和其他本地动画。若页面能够绘制但动画停在
一帧，可在浏览器控制台执行：

```js
matchMedia('(prefers-reduced-motion: reduce)').matches
```

返回 `true` 时，请检查操作系统的动画效果设置，或浏览器开发者工具是否模拟了
`prefers-reduced-motion`。Windows 可在“设置 → 辅助功能 → 视觉效果 → 动画效果”
中调整。

## 浮层系统

`Overlay` 在当前页面上方渲染任意 JSUI 节点，通过 `visible` 控制，并支持模态遮罩、
九点对齐、安全区内边距、关闭事件和 Flutter 本地过渡：

```js
Overlay({
  visible: state.open,
  alignment: 'bottomCenter',
  padding: 20,
  barrierDismissible: true,
  barrierColor: '#99000000',
  transition: 'slideUp',
  durationMs: 180,
  curve: 'easeOutCubic',
  onDismissed: actions.close(),
  child: Container({
    padding: 20,
    child: Text('Any JSUI content')
  })
});
```

可用过渡包括 `fade`、`scale`、`fadeScale`、`slideDown`、`slideUp` 和 `none`。
`SnackBar`、`AlertDialog` 与 `BottomSheet` 使用同一声明式浮层协调层，因此 Schema
驱动关闭和用户关闭共享同一生命周期。

## 通用控件效果

所有渲染节点，包括原生或自定义注册 Widget，都接受相同的 Flutter 风格效果属性。
数值属性使用与 Canvas 相同的 `animate()` 描述，并由 Flutter VSync 在本地运行。

```js
Container({
  key: 'effect-card',
  playToken: state.run,
  opacity: animate(0, 1, { durationMs: 500, curve: 'easeOut' }),
  transform: {
    translate: {
      x: animate(-48, 0, { durationMs: 500, curve: 'easeOut' })
    },
    scale: animate(0.8, 1, { durationMs: 500 })
  },
  clipRadius: animate(48, 20, { durationMs: 500 }),
  blur: animate(10, 0, { durationMs: 400 }),
  onAnimationEnd: actions.finished(),
  child: Text('Flutter widget')
});
```

同时支持静态 `colorFilter` 和可动画的 `backdropBlur`。`paused`、`playToken`
和 `reverse` 与保留 Canvas 场景中的播放含义一致。

这些 API 在 `0.1.x` 版本中仍属于实验特性。业务正确性不应依赖动画是否播放或完成，
请始终提供语义一致的静态最终状态。

## 为 Canvas 捕获 Flutter 控件

`SnapshotBoundary` 可以捕获任意已渲染子树，包括已注册的原生插件 Widget，且无需通过
QuickJS 复制 RGBA 字节。捕获事件返回页面级不透明句柄，`ctx.drawImage()` 可使用类似
浏览器的签名绘制或裁剪该句柄。

```js
import { Canvas, SnapshotBoundary } from 'quickjs_ui';

SnapshotBoundary({
  key: 'profile-card',
  captureToken: state.captureToken,
  onCaptured: actions.captured(),
  child: ProfileCard()
});

Canvas({
  width: 320,
  height: 200,
  draw(ctx) {
    if (state.snapshotId) {
      ctx.drawImage(state.snapshotId, 0, 0, 320, 200);
    }
  }
});
```

需要零延迟播放时，应在交互前预先捕获。每次捕获都会得到带版本的不可变句柄，
因此过渡期间新旧控件图像可以共存。句柄按渲染器隔离，并受数量与像素上限约束；
系统会淘汰最早且未使用的条目，渲染器释放时也会一并清理句柄。

中文使用指南（控件、第三方模块注入、宿主互操作）见
[`docs/usage.md`](docs/usage.md)。编辑器代码提示配置见
[`docs/usage.md` 第 0 节](docs/usage.md#0-先配置代码提示)。

运行栈、路由、事件入口、生命周期，以及本次栈溢出问题的复盘见
[`docs/architecture.md`](docs/architecture.md)。
