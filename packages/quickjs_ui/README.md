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

中文使用指南（控件、第三方模块注入、宿主互操作）见
[`docs/usage.md`](docs/usage.md)。编辑器代码提示配置见
[`docs/usage.md` §10.1](docs/usage.md#101-配置编辑器代码提示)。

运行栈、路由、事件入口、生命周期，以及本次栈溢出问题的复盘见
[`docs/architecture.md`](docs/architecture.md)。
