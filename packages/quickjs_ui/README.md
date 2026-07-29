# quickjs_ui

`quickjs_ui` is an experimental package for rendering Flutter widgets from a
JavaScript-driven UI schema.

This package is intentionally separate from `package:quickjs`. The core
`quickjs` package owns runtime execution, modules, plugins, host mounts, and
structured value conversion. `quickjs_ui` will own page protocol, schema
parsing, rendering, events, lifecycle, and UI examples.

Initial direction:

- JS pages export a `Page({ createState, build, ...methods })` object.
- `build()` returns JSON-compatible `UiNode` data.
- Flutter renders the schema as native widgets.
- JS does not directly create Flutter widgets or access DOM/CSSOM.

## 定位与市面方案对比

Flutter 动态化方案并不是同一种技术：有的在 Flutter 内实现 Web 运行时，有的把
Flutter 风格代码转换为动态 DSL，也有的只根据服务端 JSON 构建 Widget。
`quickjs_ui` 选择的是 **QuickJS 逻辑 + 受控 UI Schema + Flutter 原生 Widget**：
首次加载可以提交完整 Schema，频繁更新和大数据组件则逐步采用局部更新及专用数据通道。

`quickjs_ui` **不是使用 JavaScript 重新实现 Flutter，也不以 JavaScript 承载整个应用**。
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
| **quickjs_ui** | QuickJS 页面逻辑生成受控 Schema，再映射为原生 Widget | **Flutter 始终是应用、导航和原生能力主体；JSUI 只作为独立页面或局部区域嵌入，并可与原生页面、原生组件混合** | 故障和权限可限制在页面 Session；运行时及协议较轻；便于校验、快照和回放；体验类似 Web 页面接入 | 需要维护自己的组件协议和开发工具；不能直接复用 HTML/CSS 或完整 Flutter API；不适合用 JS 承载整个应用 | Flutter 应用中的业务动态页面、局部动态区域和插件页面 |

`quickjs_ui` 不以复刻 WebF、MXFlutter 或完整映射 Flutter API 为目标。WebF 更像“Flutter
中的 Web Runtime”，MXFlutter 更像“用 JS 实现 Flutter 应用”，Fair 更像“Flutter 代码
动态化”，而 `quickjs_ui` 的目标是“为 Flutter 应用补充可嵌入、受控的 JS 动态页面”。
如果需求只是静态服务端布局，JSON SDUI 会更简单；
如果需求是直接运行既有 React/Vue 页面，应优先评估 WebF；如果需求是二进制代码修复，
Shorebird 属于另一条技术路线。

因此，`quickjs_ui` 与 MXFlutter 虽然都包含“JS 生成 Flutter UI”，产品目标并不相同：
MXFlutter 试图让 JS/TS 接管完整 Flutter 应用开发模型；`quickjs_ui` 则类似 Flutter 应用中的
动态 Web 页面能力，按页面或区域接入，宿主可以随时选择原生实现、JSUI 实现或两者混合。

详细的架构阶段、优先级和非目标见
[`docs/quickjs_ui_evolution.md`](../../docs/quickjs_ui_evolution.md)。

## 0.1 protocol

Pages should be authored as plain JavaScript objects. `QuickjsUiView.asset(path: ...)`
loads a page entry from Flutter assets and wraps the default page export into the
current plugin call model automatically:

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

`build()` receives `actions` as its third argument. Use `actions.foo()` in the
UI tree and implement `foo(state, payload, props, event)` as page methods.

Page methods follow the same contract as Flutter `setState`: return a **state
patch** (partial object) or `undefined` to skip a refresh. The runtime merges the
patch, re-renders `build()`, and notifies Flutter listeners—matching
`QuickjsUiController.setState()` on the Dart side.

Use `setState(state, patch)` only when a helper needs an explicit merged snapshot
inside the handler; ordinary page methods should return patches directly.

`quickjs_ui` injects these controls as an ES module for page code. The runtime
input remains serializable object data after helper expansion.

`QuickjsUiView.asset(path: ...)` supports both single-file pages and multi-file
pages that use static relative `import`. `QuickjsUiView.file(path: ...)` does the
same for local filesystem entries. For manual plugin construction, use
`QuickjsUiPagePlugin.singleFile(...)`, `QuickjsUiPagePlugin.asset(path: ...)`, or
`QuickjsUiBundle.asset(path: ...)`.

0.5 发布包格式采用固定包根结构：`main.mjs` 是运行入口，`manifest.json` 是发布描述。
发布包用于生产分发、远程下发、缓存、checksum 校验和权限声明；开发期多文件加载仍可直接
从任意 `.mjs` 入口递归解析静态相对 `import`。格式说明见
[`docs/quickjs_ui_package_format.md`](../../docs/quickjs_ui_package_format.md)。

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
dart run quickjs_ui:manifest --root assets/quickjs_ui/profile --id com.example.profile --version 1.0.0
dart run quickjs_ui:manifest --root assets/quickjs_ui/profile --check
```

Supported widgets:

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

`TextField` supports controlled `value`, `onChanged`, `onSubmitted`, `onFocus`,
and `onBlur` event descriptors. Flutter dispatches the current string value
with each event.

0.4 examples:

- `example/assets/quickjs_ui/custom_components_page.mjs` shows JS `Component()`
  modules, controlled form controls, event descriptors, and basic implicit
  animation props.
- `example/assets/quickjs_ui/scroll_transition_page.mjs` covers `scrollToKey`,
  drag/swipe event descriptors, `SingleChildScrollView`, and keyed list item
  transitions.
- `example/assets/quickjs_ui/dev_panel_page.mjs` and
  `example/lib/pages/quickjs_ui_dev_panel_page.dart` demonstrate
  `QuickjsUiInspectorPanel`, page snapshot export, diff/resource logging, and
  state-preserving reload.
- `example/lib/pages/quickjs_ui_network_inspector_page.dart` demonstrates the
  network journal tab for bundle loading, cache hits, and request timing.
- `example/lib/pages/quickjs_ui_custom_components_page.dart` shows a Dart
  `QuickjsUiComponentRegistry` with custom `AppBar` and `Card` renderers.
- `example/assets/quickjs_ui/counter_page.mjs` is the minimal single-file
  `Page()` counter sample.
- The root example app registers both runnable pages in
  `example/lib/quickjs_ui_example_pages.dart`.

`QuickjsUiView` exposes `loadingBuilder`, `errorBuilder`, and `emptyBuilder` for
the page loading, failure, and no-rendered-node states. `placeholder` remains as
a compatibility fallback for loading and empty states.

`packages/quickjs_ui/js/quickjs_ui.js` and
`packages/quickjs_ui/js/quickjs_ui.d.ts` provide `Page()` and named control
helpers for editor hints. They are authoring helpers; the runtime still
consumes plain object UI schema.

`packages/quickjs_ui/js/quickjs_ui.schema.json` provides the first JSON Schema
for editor hints and CI checks against plain object UI schema.

`lib/src/runtime/quickjs_ui_helpers.g.dart` is generated from
`packages/quickjs_ui/js/quickjs_ui.js`. After editing the JS helper, run
`dart run tool/generate_quickjs_ui_helpers.dart` from `packages/quickjs_ui`.

## Canvas 2D authoring style

The lifecycle, limits, compatibility boundary, and device performance
acceptance criteria are specified in
[`docs/canvas_and_animation.md`](docs/canvas_and_animation.md).

Use the familiar browser Canvas 2D style. The callback runs once in QuickJS
and records a display list; Flutter then renders and animates that list locally.

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

Familiar operations include `save`, `restore`, `translate`, `rotate`, `scale`,
`beginPath`, `moveTo`, `lineTo`, `quadraticCurveTo`, `bezierCurveTo`, `arc`,
`fill`, `stroke`, `fillRect`, `strokeRect`, `clearRect`, and `fillText`.
`fillCircle`, `strokeCircle`, and `drawLine` are convenience methods.
`staticDraw` is cached as a Flutter `ui.Picture`; `draw` may contain local
`animate()` values and repaints directly from VSync without a per-frame
QuickJS bridge call.

For a large scene that must start immediately after input, register it once
with `sceneKey`, then reuse it without resending `draw` or `commands`.
`playToken` restarts local time, `paused` preserves the scene without ticking,
and `reverse` plays a finite scene backwards.

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

Retained scenes are page-scoped, bounded, and released with the renderer.
`ctx.drawImage({ slot: 'source' }, ...)` keeps snapshot ids out of the retained
display list, so a transition can replace source and target images without
rebuilding or resending its particle commands.

For snapshot dissolution effects, `ctx.drawSnapshotParticleGrid()` keeps the
entire grid as one native command instead of expanding every fragment into
generic transform and image commands:

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

The optional `direction` selects `transition` (the default), `destroy`, or
`create`. `bucketCount`, `staggerMs`, `travelMs`, and `fadeMs` control the
locally rendered finite animation.

## Control states and structural slots

`ElevatedButton`, `TextButton`, `OutlinedButton`, `Switch`, `Slider`,
`TextField`, and `TextFormField` share one state model. `normal` is the base
style; active states override it with this priority:
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

Buttons expose `leading / content / child / trailing`. Text inputs expose
`leading / prefix / suffix / trailing`. Switch and Slider expose their native
visual structure through `thumbStyle / trackStyle / overlayStyle`; each part
uses the same state names. The Button and input slots accept ordinary JSUI
nodes, so adding a new composition does not require a host release.

State changes can be interpolated locally on Flutter's VSync without sending
per-frame updates through QuickJS:

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

The same `stateTransition` declaration works on Button, Switch, Slider,
TextField, and TextFormField. Colors, numbers, padding, text style, border
radius, `scale`, and `opacity` share one interpolation pipeline. The default
transition is 140 ms with `easeOutCubic`; set `durationMs: 0` or
`stateTransition: false` for an immediate change. Flutter's reduced-motion
setting also disables these transitions automatically.

## Overlay system

`Overlay` renders any JSUI node above the current page. It is controlled with
`visible` and supports modal barriers, nine-point alignment, safe-area
padding, dismissal events, and local Flutter transitions:

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

Available transitions are `fade`, `scale`, `fadeScale`, `slideDown`,
`slideUp`, and `none`. `SnackBar`, `AlertDialog`, and `BottomSheet` use the same declarative
overlay reconciliation layer, so schema-driven close and user dismissal have
one lifecycle.

## Universal widget effects

Every rendered node, including native or custom registered widgets, accepts
the same Flutter-style effect properties. Numeric properties use the same
`animate()` descriptor as Canvas and run locally from Flutter VSync.

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

Static `colorFilter` and animated `backdropBlur` are also supported.
`paused`, `playToken`, and `reverse` have the same playback meaning as a
retained Canvas scene.

These APIs are currently experimental under the package's `0.1.x` version.
Do not make application correctness depend on animation completion or motion;
always provide the same meaningful static end state.

## Capturing Flutter widgets for Canvas

`SnapshotBoundary` captures any rendered child subtree—including registered
native plugin widgets—without copying RGBA bytes through QuickJS. The capture
event returns an opaque page-scoped handle that `ctx.drawImage()` can draw or
crop with the familiar browser signatures.

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

Capture ahead of an interaction when zero-delay playback matters. Every
capture receives a versioned immutable handle, allowing old and new widget
images to coexist during a transition. Handles are isolated to one renderer,
bounded by count and pixel limits, evict oldest unused entries, and are
disposed with the renderer.

中文使用指南（控件、第三方模块注入、宿主互操作）见
[`docs/usage.md`](docs/usage.md)。编辑器代码提示配置见
[`docs/usage.md` §10.1](docs/usage.md#101-配置编辑器代码提示)。

运行栈、路由、事件入口、生命周期，以及本次栈溢出问题的复盘见
[`docs/architecture.md`](docs/architecture.md)。
