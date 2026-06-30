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
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'CounterPage',

  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  build(state, props, page) {
    return Column({
      mainAxisAlignment: 'center',
      children: [
        Text(`Count: ${state.count}`),
        ElevatedButton({
          child: Text('Add'),
          onPressed: page.increment()
        })
      ]
    });
  },

  increment(state) {
    return { ...state, count: state.count + 1 };
  }
});
```

`quickjs_ui` injects these controls as an ES module for page code. The runtime
input remains serializable object data after helper expansion.

`QuickjsUiView.asset(path: ...)` supports both single-file pages and multi-file
pages that use static relative `import`. `QuickjsUiView.file(path: ...)` does the
same for local filesystem entries. For manual plugin construction, use
`QuickjsUiPagePlugin.singleFile(...)`, `QuickjsUiPagePlugin.asset(path: ...)`, or
`QuickjsUiBundle.asset(path: ...)`.

Supported widgets in 0.1:

- `Text`
- `ElevatedButton`
- `Row`
- `Column`
- `Container`

`packages/quickjs_ui/js/quickjs_ui.js` and
`packages/quickjs_ui/js/quickjs_ui.d.ts` provide `Page()` and named control
helpers for editor hints. They are authoring helpers; the runtime still
consumes plain object UI schema.
