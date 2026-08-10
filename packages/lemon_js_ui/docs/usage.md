# quickjs_ui 使用指南

本文档说明如何在 Flutter 应用中使用 `quickjs_ui`：编写 JS 页面、使用内置控件、注入第三方模块，以及宿主与 JS 之间的互操作。

更底层的运行栈与事件流说明见 [architecture.md](./architecture.md)。

## 0. 先配置代码提示

开始编写页面前，先让编辑器认识 `quickjs_ui` 模块；否则 `Page()`、控件 props、事件回调和
Canvas 命令都不会有完整提示。

在 Flutter 项目根目录创建 `jsconfig.json`。如果项目通过 workspace 的 `path:` 依赖引用本仓库，配置如下：

```json
{
  "compilerOptions": {
    "checkJs": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",
    "baseUrl": ".",
    "paths": {
      "quickjs_ui": [
        "../packages/lemon_js_ui/js/quickjs_ui.d.ts"
      ],
      "quickjs_ui/*": [
        "../packages/lemon_js_ui/js/*"
      ]
    }
  },
  "include": [
    "assets/**/*.mjs"
  ]
}
```

如果使用已发布的 `lemon_js_ui`，把 `paths.quickjs_ui` 指向 pub 缓存中的
`lemon_js_ui-<version>/js/quickjs_ui.d.ts` 即可。插件提供的额外模块还需要在自己的包中提供
`.d.ts`，生成时通过 `--types` 传入，工具会自动增加对应模块映射。修改配置后，在 VS Code 中执行
**Developer: Reload Window**。

第三方 UI 模块的声明文件需要包含模块名，例如：

```ts
import type { QuickjsUiNode } from 'quickjs_ui';

declare module 'quickjs_ui/video_player' {
  export type VideoPlayerProps = {
    source: string;
    playing?: boolean;
  };

  export function VideoPlayer(props: VideoPlayerProps): QuickjsUiNode;
}
```

生成配置时追加该声明文件：

```bash
dart run lemon_js_ui:codegen \
  --root assets/quickjs_ui \
  --types ../packages/lemon_js_ui_video_player/js/quickjs_ui_video_player.d.ts
```

如果声明文件已经放在 JS 页面目录下，工具会自动递归发现，不需要重复传入 `--types`。

类型声明文件的位置：

- 核心 UI：`packages/lemon_js_ui/js/quickjs_ui.d.ts`
- Canvas、控件、页面协议和宿主 API 都包含在核心声明文件中；
- 第三方 UI 插件应提供独立的 `js/*.d.ts`，不要直接修改核心声明文件。

## 1. 概述

`lemon_js_ui` 是一套**用 JavaScript 描述 UI、由 Flutter 原生渲染**的实验性 UI 框架。它与 `package:lemon_js` 分工明确：

| 包 | 职责 |
|---|---|
| `lemon_js` | QuickJS 运行时、模块加载、插件协议、宿主挂载（Host Mount）、结构化值转换 |
| `lemon_js_ui` | 页面协议、UI Schema 解析、控件渲染、事件分发、生命周期、导航 |

### 1.1 核心设计原则：JS 管逻辑，Flutter 管渲染

quickjs_ui 最重要的边界约定是：

> **所有页面状态、业务逻辑和事件处理都在 JS 中完成；Flutter 只负责把 JS 输出的 UI 描述渲染成原生控件，并把用户操作转发回 JS。**

换句话说，Flutter 侧**不写**页面业务代码，只做「渲染器 + 事件管道 + 宿主能力桥接」。

| 层次 | 归属 | 做什么 | 不做什么 |
|---|---|---|---|
| **JS 页面** | JavaScript | 持有 state、实现 handler、`build()` 产出 UI 树、调用宿主 API | 不直接创建 Flutter Widget |
| **Flutter 渲染层** | Dart | 将 `UiNode` 转成 `Widget`、响应手势/输入、按帧转发事件 | 不实现按钮点击后的业务逻辑 |
| **Flutter 宿主** | Dart | 提供 toast、导航壳、存储等原生能力（可选） | 不替代 JS 管理页面 state |

用计数器举例，职责划分如下：

```
用户点击「+1」
    │
    ▼
Flutter ElevatedButton.onPressed          ← 只捕获手势，不修改 count
    │
    ▼
dispatchEvent({ method: 'increment' })      ← 事件入队，跨帧 flush
    │
    ▼
JS handleEvent → increment(state)         ← 业务逻辑在 JS
    │              return { count: +1 }
    ▼
JS commit() → build(state) → UiNode 树    ← 重新描述 UI（count 已变）
    │
    ▼
Flutter QuickjsUiRenderer 渲染新树         ← 只根据 schema 更新 Widget
```

**JS 侧负责：**

- 页面 state 的创建、更新与权威持有
- 所有控件事件对应的 handler（点击、输入、滑动等）
- `build()` 根据 state 生成完整的 UI 描述
- 生命周期 hook、路由跳转意图、调用 `quickjsUiHost` / `quickjsUiApp`

**Flutter 侧负责：**

- 加载 JS 页面、运行 QuickJS 运行时
- 将 `QuickjsUiNode` 渲染为 Material/Cupertino 控件
- 把 Widget 回调包装成事件描述符，发给 JS 的 `handleEvent`
- 在 JS `commit()` 后刷新 Widget 树
- （可选）注册宿主能力、自定义控件 renderer、路由解析

因此，如果你在 Flutter 里写 `onPressed: () => setState(() => count++)`，那是传统 Flutter 写法，**不符合** quickjs_ui 模型。正确做法是：Flutter 只挂载 `QuickjsUiView`，计数逻辑完全在 JS 的 `increment(state)` 中实现。

Dart 侧的 `controller.setState` / `controller.dispatch` 是给宿主主动干预的**补充入口**（如原生按钮触发 JS 逻辑、调试面板改状态），并不改变「state 权威在 JS」这一原则。

### 1.2 数据流

```
JS Page.build() → 可序列化 UiNode 树 → Flutter Widget 渲染
       ↑                                    ↓
   state patch                         用户交互事件（转发给 JS）
```

JS 侧**不直接**创建 Flutter Widget，也不访问 DOM/CSSOM；只输出 JSON 兼容的节点对象。Flutter 侧**不持有**页面业务 state，只在需要诊断时同步 JS 的 state 快照。

---

## 2. 快速开始

### 2.1 添加依赖

```yaml
dependencies:
  flutter:
    sdk: flutter
  lemon_js:
    path: ../lemon_js
  lemon_js_ui:
    path: ../packages/lemon_js_ui
```

将 JS 页面放入 `assets`，并在 `pubspec.yaml` 中声明：

```yaml
flutter:
  assets:
    - assets/quickjs_ui/counter_page.mjs
```

### 2.2 Flutter 侧挂载页面

```dart
import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class CounterPage extends StatelessWidget {
  const CounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: QuickjsUiView.asset(
        path: 'assets/quickjs_ui/counter_page.mjs',
        initialProps: const {
          'title': 'Counter',
          'initialCount': 0,
        },
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Text('加载失败: $error'),
      ),
    );
  }
}
```

### 2.3 JS 侧编写页面

```js
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'CounterPage',

  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  build(state, props, actions) {
    return Column({
      mainAxisAlignment: 'center',
      children: [
        Text(`${props.title ?? 'Counter'}: ${state.count}`),
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

**要点：**

- `build(state, props, actions)` 的第三个参数 `actions` 由运行时根据页面方法名自动生成。
- 在 UI 树里写 `actions.increment()`，对应实现 `increment(state, payload, props, event)`。
- 页面方法应返回 **state patch**（部分字段），不要返回 `{ ...state, ...patch }`。
- 无状态变化时返回 `null` 或 `undefined`，不要返回当前 `state`。

---

## 3. Page() 页面编写

`Page({ ... })` 是 quickjs_ui 的核心入口。传入页面对象后，运行时将其包装为 `quickjs_ui.runtime.v1` 协议对象，由 Dart 侧 `QuickjsUiSession` 驱动。

### 3.1 声明属性一览

| 属性 | 类型 | 必填 | 说明 |
|---|---|---|---|
| `name` | `string` | 否 | 页面名称，用于诊断、快照、日志 |
| `props` | `Record<string, string>` | 否 | Props 类型声明（文档/校验提示，不影响运行时） |
| `metadata` | `object` | 否 | 附加元数据，出现在诊断快照中 |
| `schemaVersion` | `number` | 否 | 页面 schema 版本，默认 `1` |
| `minimumQuickjsUiVersion` / `minQuickjsUiVersion` | `number` | 否 | 要求的最低 quickjs_ui 运行时版本 |
| `unknownProps` | `'ignore' \| 'warn' \| 'error'` | 否 | 未知节点属性的处理策略，默认 `ignore` |
| `deprecatedProps` | `Record<string, string>` | 否 | 已废弃属性及迁移提示 |
| `createState` | `(props) => state` | 否* | 根据 props 初始化 state |
| `state` | `(props) => state` | 否* | `createState` 的别名 |
| `build` | `(state, props, actions) => node` | **是** | 构建 UI 树 |
| `onMount` 等 | 生命周期函数 | 否 | 见 [3.6 生命周期 Hook](#36-生命周期-hook) |
| 其他函数 | `(state, payload, props, event) => patch` | 否 | 页面事件方法，通过 `actions` 绑定到控件 |

\* `createState` 与 `state` 二选一；都不写时初始 state 为 `{}`。

#### 完整声明示例

```js
import { Column, Page, Text } from 'quickjs_ui';

export default Page({
  // 页面标识
  name: 'ProfilePage',

  // Props 类型声明（供编辑器/文档参考）
  props: {
    userId: 'string',
    title: 'string',
    initialCount: 'number'
  },

  // 诊断用元数据
  metadata: {
    team: 'platform',
    feature: 'profile'
  },

  // 兼容性声明
  schemaVersion: 1,
  minimumQuickjsUiVersion: 1,
  unknownProps: 'warn',
  deprecatedProps: {
    oldText: '请改用 Text 的 data 属性'
  },

  createState(props) {
    return {
      label: props.title ?? '默认标题',
      count: props.initialCount ?? 0
    };
  },

  build(state, props, actions) {
    return Column({
      children: [
        Text(`${state.label}: ${state.count}`),
        Text(`userId = ${props.userId ?? '未传入'}`)
      ]
    });
  }
});
```

Flutter 侧传入 props：

```dart
QuickjsUiView.asset(
  path: 'assets/quickjs_ui/profile_page.mjs',
  initialProps: const {
    'userId': 'u-001',
    'title': '我的资料',
    'initialCount': 3,
  },
)
```

### 3.2 状态初始化

**方式一：`createState(props)`（推荐）**

```js
createState(props) {
  return {
    count: props.initialCount ?? 0,
    items: props.seedItems ?? []
  };
}
```

**方式二：`state(props)`（与 `createState` 等价）**

```js
state(props) {
  return { ready: props.autoload === true };
}
```

**方式三：不写初始化函数**

```js
export default Page({
  name: 'EmptyStatePage',
  build(state) {
    // state 为 {}
    return Text(`version: ${state.version ?? 0}`);
  }
});
```

`createState` 可以是 `async`，支持在初始化时 `await` 宿主 API：

```js
async createState(props) {
  const cached = await quickjsUiHost.storage.getItem('draft');
  return { draft: cached ?? props.defaultDraft ?? '' };
}
```

### 3.3 build 与 actions

`build` 接收三个参数：

```js
build(state, props, actions) {
  return Column({
    children: [
      Text(`计数: ${state.count}`),
      ElevatedButton({
        child: Text('+1'),
        onPressed: actions.increment()   // 绑定到 increment 方法
      })
    ]
  });
}
```

`actions` 由运行时根据页面对象上的**非保留函数**自动生成。保留名（不能作为事件方法）包括：`name`、`build`、`createState`、`onMount` 等，完整列表见 `quickjs_ui.d.ts` 中的 `QuickjsUiReservedPageKeys`。

第三个参数在类型定义里可能写作 `actions`，示例代码里也常见 `page` 作为参数名，二者等价：

```js
build(state, props, page) {
  return ElevatedButton({
    child: Text('提交'),
    onPressed: page.submit()
  });
}
```

### 3.4 页面方法（事件 Handler）

#### 基本用法

```js
increment(state) {
  return { count: state.count + 1 };
}
```

#### 读取事件值

控件会把当前值附在 `event` 上，通过第四个参数读取：

```js
setExpanded(state, _payload, _props, event) {
  return { expanded: event.value === true };
}

changeName(state, _payload, _props, event) {
  return { name: event.value ?? '' };
}
```

#### 带 payload 的方法

`actions.methodName(payload)` 会把 `payload` 作为 handler 的第二个参数传入，适合列表项、表单字段等场景：

```js
// UI 绑定
TextField({
  value: state.name,
  onChanged: actions.updateField({ field: 'name' })
})

// Handler 实现
updateField(state, payload, _props, event) {
  return {
    [payload.field]: event.value ?? '',
    status: `正在编辑 ${payload.field}`
  };
}
```

列表示例（`todo_page.mjs`）：

```js
// 列表项按钮
ElevatedButton({
  onPressed: actions.toggleTodo({ id: todo.id }),
  child: Text(todo.done ? 'Reopen' : 'Done')
})

toggleTodo(state, payload) {
  const todos = state.todos.map((todo) =>
    todo.id === payload.id ? { ...todo, done: !todo.done } : todo
  );
  return { todos };
}
```

#### 异步 Handler

Handler 可返回 `Promise<patch>`，适合调用宿主 API：

```js
async callToast(state) {
  const result = await quickjsUiHost.toast('保存成功');
  return { status: `toast => ${JSON.stringify(result)}` };
}

async openSettings(state, _payload, props) {
  const result = await quickjsUiNavigation.push({
    route: 'app.settings',
    params: { source: props.itemId }
  });
  return { lastResult: JSON.stringify(result) };
}
```

#### 无状态变化

导航等副作用操作不需要刷新 UI 时，返回 `null`：

```js
popToList(state, _payload, props) {
  quickjsUiNavigation.pop({ itemId: props.itemId });
  return null;
}
```

#### 通过 methods 集中声明（可选）

除直接写在页面对象上，也可通过 `methods` 字段挂载：

```js
export default Page({
  name: 'MethodsObjectPage',
  createState() { return { count: 0 }; },
  build(state, props, actions) {
    return ElevatedButton({
      child: Text(`Count: ${state.count}`),
      onPressed: actions.increment()
    });
  },
  methods: {
    increment(state) {
      return { count: state.count + 1 };
    }
  }
});
```

### 3.5 工具函数

#### setState(state, patch)

在 handler 内部需要合并出完整快照时使用（例如校验逻辑）；**handler 返回值仍应只含 patch**：

```js
import { Page, setState } from 'quickjs_ui';

saveProfile(state) {
  const next = setState(state, { saved: true });
  const errors = validate(next);   // 用合并后的快照做校验
  if (Object.keys(errors).length > 0) {
    return { errors, status: '校验失败' };
  }
  return { errors: {}, status: `已保存 ${next.name}` };
}
```

#### eventField(event, name, fallback)

从事件对象安全读取字段，适合 Slider、视频进度等复杂 payload：

```js
import { Page, Slider, eventField } from 'quickjs_ui';

onProgress(state, _payload, _props, event) {
  return {
    positionMs: eventField(event, 'positionMs', state.positionMs),
    durationMs: eventField(event, 'durationMs', state.durationMs)
  };
}

scrub(state, payload, _props, event) {
  return {
    scrubbing: true,
    scrubPositionMs: eventField(event, 'value', state.positionMs)
  };
}
```

### 3.6 生命周期 Hook

在页面对象上声明 hook 函数后，运行时会在 `capabilities().lifecycle` 中列出，Dart 侧调用 `controller.lifecycle(type)` 时才会进入 JS。

```js
export default Page({
  name: 'LifecycleDemoPage',

  createState() {
    return { events: [] };
  },

  build(state) {
    return Column({
      children: [
        Text('生命周期事件'),
        Text(state.events.join(' → ') || '等待 mount')
      ]
    });
  },

  onMount(state, payload, props, event) {
    console.log('[lifecycle] mount', { props, event });
    return { events: [...state.events, 'mount'] };
  },

  onShow(state) {
    return { events: [...state.events, 'show'] };
  },

  onHide(state) {
    return { events: [...state.events, 'hide'] };
  },

  onPause(state) {
    return { events: [...state.events, 'pause'] };
  },

  onResume(state) {
    return { events: [...state.events, 'resume'] };
  },

  onDispose(state) {
    console.log('[lifecycle] dispose');
    return { events: [...state.events, 'dispose'] };
  }
});
```

Dart 侧触发：

```dart
final controller = QuickjsUiController();

// 页面显示时
await controller.lifecycle('show');

// 应用进入后台
await controller.lifecycle('pause');

// 页面销毁前
await controller.lifecycle('dispose', render: false);
```

| Hook | `lifecycle()` 参数 | 典型触发场景 |
|---|---|---|
| `onMount` | `'mount'` | 页面首次挂载完成 |
| `onShow` / `onHide` | `'show'` / `'hide'` | Tab 切换、路由可见性变化 |
| `onPause` / `onResume` | `'pause'` / `'resume'` | 应用前后台切换 |
| `onDispose` | `'dispose'` | 页面销毁 |

### 3.7 路由生命周期

路由相关 hook 由 `controller.routeLifecycle(...)` 触发，与页面事件队列分离：

```js
export default Page({
  name: 'NavigationDetailPage',

  createState() {
    return { count: 0, routeResult: '等待返回' };
  },

  build(state, props, actions) {
    return Column({
      children: [
        Text(`itemId: ${props.itemId}`),
        Text(`route result: ${state.routeResult}`),
        ElevatedButton({
          child: Text('打开子页'),
          onPressed: actions.openChild()
        })
      ]
    });
  },

  async openChild(state, _payload, props) {
    const result = await quickjsUiNavigation.push({
      route: 'app.child',
      path: './child_page.mjs',
      params: { itemId: props.itemId, count: state.count }
    });
    return { routeResult: JSON.stringify(result) };
  },

  onRouteEnter(state, payload) {
    console.log('进入路由', payload);
  },

  onRouteLeave(state, payload) {
    console.log('离开路由', payload);
  },

  onRouteResult(state, payload) {
    // 子页面 pop 带回结果时触发
    return { routeResult: JSON.stringify(payload) };
  }
});
```

| Hook | `routeLifecycle()` 参数 | 说明 |
|---|---|---|
| `onRouteEnter` | `'routeEnter'` | 进入当前路由 |
| `onRouteLeave` | `'routeLeave'` | 离开当前路由 |
| `onRouteResult` | `'routeResult'` | 子路由 `pop` 带回结果 |

### 3.8 兼容性声明

页面可通过声明属性约束运行时版本，加载时由 Dart 校验：

```js
export default Page({
  schemaVersion: 1,              // 当前仅支持 1
  minimumQuickjsUiVersion: 1,    // 要求 quickjs_ui >= 1
  unknownProps: 'warn',          // 未知 UI 属性：ignore | warn | error
  deprecatedProps: {
    oldText: '请改用 Text 的 data 属性'
  },
  build() {
    return Text('兼容当前运行时');
  }
});
```

版本不匹配时，`QuickjsUiSession.loadPlugin` 会抛出 `StateError`（如 `unsupported schema version`）。

### 3.9 runtime v1 协议（Dart 调用边界）

`Page()` 包装后的运行时对象暴露以下方法，一般无需在页面代码中手动调用，但了解有助于排查问题：

| 方法 | 说明 |
|---|---|
| `capabilities()` | 协议版本、schema 版本、已声明的生命周期 hook |
| `mount(props)` | 初始化 props/state，返回 `{ version, state }` |
| `handleEvent(event)` | 处理控件事件，更新 JS 内部 state，返回 `{ changed, version }` |
| `commit()` | dirty 时调用 `build()`，返回新 UI 节点 |
| `setState(patch)` | 宿主侧显式 patch 入口（对应 `controller.setState`） |
| `lifecycle(event)` | 调用已声明的生命周期 hook |
| `snapshot()` | 返回当前 state 快照（供 Dart 诊断） |
| `dispose()` | 释放页面运行时 |

Dart 侧主动改 state 示例：

```dart
await controller.setState({'count': 7});
```

等效于 JS 内部执行 `page.setState({ count: 7 })` 后触发 re-render。

### 3.10 Handler 返回值规则（重要）

1. **只返回 patch**，不要 `return { ...state, count: state.count + 1 }`。
2. **无变化返回 `null` 或 `undefined`**，不要 `return state`。
3. Handler 内可用 `...state.xxx` 构造局部变量，但不能把完整 `state` 作为返回值。
4. 违反上述规则时，运行时会抛出 `must return a state patch` 类型错误。

---

## 4. 内置控件参考

所有控件均从 `quickjs_ui` 模块导入。每个 helper 最终展开为 `{ type: '控件名', ...props }` 的可序列化节点。

以下属性中，带 **事件** 标记的字段值为事件描述符，写法为 `actions.methodName()` 或 `{ method: 'methodName', ... }`。

### 4.1 通用属性（多数控件支持）

| 属性 | 类型 | 说明 |
|---|---|---|
| `key` | `string` | 节点 key，用于列表动画、滚动定位 |
| `semanticLabel` / `semanticsLabel` | `string` | 无障碍标签 |
| `semanticHint` | `string` | 无障碍提示 |
| `tooltip` | `string` | 工具提示 |
| `role` | `'button' \| 'image' \| 'textField' \| 'header'` | 语义角色 |
| `enabled` | `boolean` | 是否可用 |
| `focusOrder` | `number` | 焦点顺序 |
| `onTap` / `onLongPress` / `onDoubleTap` | 事件 | 点击手势 |
| `onDragStart` / `onDragUpdate` / `onDragEnd` | 事件 | 拖拽 |
| `onSwipe` | 事件 | 滑动手势，payload 含 `direction` |

### 4.2 Text

显示文本。

```js
Text('Hello')
Text('标题', { style: '$text.titleMedium', textAlign: 'center' })
Text({ data: '内容', style: { color: '$primary', fontSize: 16, fontWeight: 'w700' } })
```

| 属性 | 说明 |
|---|---|
| `data` / `text` | 文本内容 |
| `textAlign` | `left` `right` `center` `justify` `start` `end` |
| `style` | 文本样式对象或主题 token（如 `$text.bodyLarge`） |

`style` 支持：`color`、`fontSize`、`fontWeight`（100–900 或 `bold`/`w600` 等）、`letterSpacing`、`height`。

### 4.3 ElevatedButton

Material 凸起按钮。

```js
ElevatedButton({
  child: Text('提交'),
  onPressed: actions.submit()
})
```

| 属性 | 说明 |
|---|---|
| `child` | **必填**，子节点 |
| `onPressed` | 事件，通常为 command 型（点击类离散操作） |

### 4.4 Row / Column

水平/垂直 Flex 布局。

```js
Column({
  mainAxisAlignment: 'center',      // start | end | center | spaceBetween | spaceAround | spaceEvenly
  crossAxisAlignment: 'stretch',    // start | end | center | stretch | baseline
  gap: '$space.md',                 // 子项间距
  children: [Text('A'), Text('B')]
})
```

### 4.5 Container

带装饰的容器。

```js
Container({
  width: 200,
  height: 100,
  padding: { all: 12 },
  margin: { bottom: 8 },
  alignment: 'center',
  color: '$primaryContainer',
  borderRadius: 8,
  decoration: {
    color: '$surface',
    borderRadius: 12,
    border: { color: '$outline', width: 1 }
  },
  child: Text('内容')
})
```

支持隐式动画属性：`animationDurationMs`、`animationCurve`（如 `easeOut`）。

### 4.6 Image

图片，支持 asset / network / file 等资源。

```js
// 网络图
Image({ src: 'https://example.com/a.png', height: 120, fit: 'cover' })

// Asset 图
Image({ src: 'assets/icons/logo.png', width: 48, height: 48, fit: 'contain' })

// 结构化资源
Image({
  source: { uri: 'https://...', kind: 'network', sha256: '...' },
  fit: 'cover'
})
```

| 属性 | 说明 |
|---|---|
| `src` / `source` | **必填**，字符串或资源对象 |
| `width` / `height` | 尺寸 |
| `fit` | `fill` `contain` `cover` `fitWidth` `fitHeight` `none` `scaleDown` |

### 4.7 ListView

可滚动列表，支持列表项过渡动画与滚动控制。

```js
ListView({
  padding: 16,
  gap: 12,
  scrollDirection: 'vertical',       // vertical | horizontal
  shrinkWrap: true,
  scrollToKey: state.scrollToKey,    // 滚动到指定 key 的子项
  scrollToken: state.scrollToken,    // 递增以触发滚动
  scrollDurationMs: 180,
  scrollCurve: 'easeOut',
  onScroll: actions.onScroll(),
  animateItems: true,
  itemTransitionDurationMs: 180,
  children: items.map(item => Container({ key: item.id, child: Text(item.name) }))
})
```

数组驱动的列表也可以统一使用 `ListView.builder`，数据量较小时同样适用。宿主按
`prefetchItemCount` 分批请求节点，不会把完整超长列表一次性传过 QuickJS 桥：

```js
ListView.builder({
  key: 'message-list',                // 必填，必须稳定
  itemCount: messages.length,
  prefetchItemCount: 20,              // 可选，默认 20
  cacheExtent: 320,
  itemKey: index => messages[index].id,
  itemBuilder: index => MessageRow({ message: messages[index] })
})
```

`itemExtent` 不是必填项：

- 不设置时按真实内容高度布局，并按条数预加载，适合聊天消息和不等高卡片。
- `estimatedItemExtent` 只是加载占位的参考值，不会固定业务条目高度。
- `itemExtent` 会固定每项高度，适合等高列表，布局成本最低。

不提供固定或预估高度时，连续滚动不受影响，但宿主无法在尚未构建条目前准确知道
完整滚动长度，也不能立即精确跳转到很远的索引。需要精确远距离定位的业务应提供
`itemExtent`；第一版 builder 模式以连续向后滚动和分批预取为主。

`ListView.builder` 不支持 `animateItems`。动态插入、删除动画继续使用
`ListView({ children, animateItems: true })`。

接口分页时，`itemCount` 应填写当前已经加载的数据量，而不是服务器总量：

```js
ListView.builder({
  key: 'article-list',
  itemCount: state.items.length,
  hasMore: state.hasMore,
  loading: state.loading,
  loadMoreThreshold: 5,
  loadingText: '正在加载下一页…',
  onLoadMore: actions.loadMore(),
  resetToken: state.queryVersion,
  itemKey: index => state.items[index].id,
  itemBuilder: index => ArticleRow({ article: state.items[index] })
})
```

| 分页属性 | 说明 |
|---|---|
| `hasMore` | 是否还有下一页；为 `false` 时不再触发加载 |
| `loading` | 当前是否正在请求；为 `true` 时阻止重复触发 |
| `loadMoreThreshold` | 距离已加载末尾多少项时预取，默认 5 |
| `onLoadMore` | 请求下一页的事件 |
| `loadingText` | 底部加载提示；省略时只显示系统进度指示器 |
| `resetToken` | 筛选、搜索或刷新后递增，用于清空旧列表缓存 |

分页加载默认关闭，只有提供 `onLoadMore` 才会启用；未提供回调时不会预取下一页，
也不会显示底部加载提示。下拉刷新同样默认关闭，只有使用 `RefreshIndicator` 并提供
`onRefresh` 时才启用，不需要额外的布尔开关。

下一页数据应追加到原数组，并保持 `key` 和 `resetToken` 不变，此时列表保留滚动位置。
下拉刷新可以继续使用系统 `RefreshIndicator` 包裹 builder；刷新时替换数据并递增
`resetToken`：

```js
RefreshIndicator({
  onRefresh: actions.refresh(),
  child: ListView.builder({ /* 分页列表属性 */ })
})
```

### 4.8 SingleChildScrollView

单子滚动视图，属性与 `ListView` 的滚动相关字段类似，适合内容较少的可滚动区域。

### 4.9 TextField

受控文本输入框。

```js
TextField({
  value: state.name,
  labelText: '姓名',
  hintText: '请输入',
  keyboardType: 'text',              // text | number | emailAddress | url | multiline 等
  textInputAction: 'done',
  obscureText: false,
  maxLines: 1,
  onChanged: actions.changeName(),   // payload: { value: string }
  onSubmitted: actions.submitName(),
  onFocus: actions.focusName(),
  onBlur: actions.blurName()
})
```

| 属性 | 说明 |
|---|---|
| `value` | 受控值 |
| `focusId` | 焦点标识 |
| `requestFocus` / `clearFocus` / `focusOnMount` | 焦点控制 |
| `submitFocusAction` | 提交后焦点：`none` `next` `previous` `unfocus` |

事件 handler 中通过 `event.value` 读取当前字符串。

### 4.10 Stack

层叠布局。

```js
Stack({
  alignment: 'center',
  fit: 'loose',                      // loose | expand | passthrough
  children: [background, foreground]
})
```

### 4.11 Padding / Center / SizedBox

```js
Padding({ padding: { horizontal: 16, vertical: 8 }, child: Text('x') })
Center({ child: Text('居中') })
SizedBox({ width: 100, height: 40, child: Text('固定尺寸') })
```

### 4.12 Form

表单容器，包裹子控件。

```js
Form({ child: Column({ children: [/* 表单控件 */] }) })
```

### 4.13 Checkbox

```js
Checkbox({
  value: state.checked,
  tristate: false,
  onChanged: actions.setChecked()    // payload: { value: boolean | null }
})
```

### 4.14 Switch

```js
Switch({
  value: state.expanded,
  onChanged: actions.setExpanded()  // payload: { value: boolean }
})
```

### 4.15 Slider

```js
Slider({
  min: 0,
  max: 100,
  value: state.progress,
  divisions: 10,
  label: '50%',
  onChanged: actions.scrub(),       // 拖动中，sample 事件
  onChangeEnd: actions.seek()       // 拖动结束，command 事件
})
```

### 4.16 Radio

```js
Radio({
  value: 'a',
  groupValue: state.selected,
  onChanged: actions.select()       // payload: { value: any }
})
```

### 4.17 DropdownButton

```js
DropdownButton({
  value: state.size,
  items: [
    { value: 'small', label: 'Small' },
    { value: 'medium', label: 'Medium' },
    { value: 'large', label: 'Large' }
  ],
  hint: '请选择',
  onChanged: actions.setSize()
})
```

### 4.18 补充基础控件

以下控件保持 Flutter 命名和属性语义：

- `VerticalDivider(props)`：支持 `width`、`thickness`、`indent`、`endIndent` 和 `color`。
- `Placeholder(props)`：支持 `color`、`strokeWidth`、`fallbackWidth` 和 `fallbackHeight`。
- `GestureDetector({ child, ...events })`：支持通用点击、长按、双击、拖动和 swipe 事件。
- `TextFormField(props)`：沿用 `TextField` 的受控值、焦点和事件字段，并支持 `helperText`、`errorText`。
- `Tooltip({ message, child, waitDurationMs, showDurationMs })`。
- `AnimatedContainer`、`AnimatedOpacity`、`AnimatedPadding`：使用 `durationMs` / `animationDurationMs`
  和 `animationCurve` 描述隐式动画。
- `Hero({ tag, child, transitionOnUserGestures })`：`tag` 仅接受 string、number 或 boolean，
  保证页面 schema 可序列化且跨运行时稳定。

这些 helper 只生成 UI schema；动画、手势和 Hero flight 均由 Flutter 执行。

### 4.19 Web 动画与“减少动态效果”

JSUI 动画由 Flutter 在本地执行，并遵循系统和浏览器的无障碍设置。Web 平台会把
CSS 媒体特性 `prefers-reduced-motion: reduce` 映射为
`MediaQuery.disableAnimations = true`。当前 JSUI 在该状态下会将效果质量设为
`off`，停止 Canvas Ticker；循环动画会停在初始帧，有限动画则显示最终状态。

当 Canvas 已经显示内容但动画不播放时，可在浏览器控制台检查：

```js
matchMedia('(prefers-reduced-motion: reduce)').matches
```

- 返回 `false`：不是无障碍降级，应继续检查动画描述、`paused`、Ticker 和 VSync。
- 返回 `true`：浏览器正在请求减少动画。Windows 可在“设置 → 辅助功能 → 视觉效果
  → 动画效果”中调整；同时检查浏览器开发者工具是否模拟了
  `prefers-reduced-motion`。

性能面板中的 `reducedMotion=true`、`quality=off` 和
`stoppedCanvasTickerCount > 0` 也表示动画因该设置而停止。业务正确性不应依赖动画
一定播放，静态状态也应保持完整语义。

---

## 5. 主题与设计令牌

控件样式可直接使用 Flutter `ThemeData` 对应的设计令牌：

**颜色：** `$primary` `$onPrimary` `$surface` `$onSurface` `$outline` `$error` 等

**文字：** `$text.titleMedium` `$text.bodyLarge` `$text.labelSmall` 等

**间距：** `$space.xs` `$space.md` `$space.lg` 等

**圆角：** `$radius.sm` `$radius.md` `$radius.full` 等

**阴影：** `$elevation.sm` `$elevation.md` 等

也支持十六进制颜色（`#RRGGBB` / `#AARRGGBB`）和数值。

---

## 6. 事件模型

事件是 JS 与 Flutter 之间的核心边界：Flutter 控件只负责**产生**事件，JS 页面方法负责**处理**事件并决定 state 如何变化。Flutter 不会在本地修改业务 state。

### 6.1 事件描述符

控件事件属性值为对象，至少包含 `method`（或 `action`）：

```js
// 推荐：通过 actions 生成
onPressed: actions.increment()

// 等价手写
onPressed: { method: 'increment' }
onPressed: { method: 'increment', payload: { id: 1 } }
```

### 6.2 事件类型

| 类型 | 行为 | 适用场景 |
|---|---|---|
| **command**（默认） | 保序、不合并 | 按钮点击、提交、导航 |
| **sample** | 同 key 可合并 | Switch、Checkbox、Slider 拖动、视频进度 |

可在事件描述符上附加：

- `throttleMs` — 节流
- `debounceMs` — 防抖
- `coalesceKey` — 合并 key
- `dropMs` — 丢弃窗口

### 6.3 Handler 签名

```js
methodName(state, payload, props, event) {
  // event.value — 控件当前值（Switch、TextField 等）
  // event.method — 方法名
  return { field: newValue };  // 只返回变化的字段
}
```

Handler 可以是 `async`，支持 `await quickjsUiHost.toast(...)` 等异步宿主调用。

---

## 7. 第三方模块注入

扩展 `quickjs_ui` 分两层：**JS 模块注入**（让页面能 `import`）和 **Dart 渲染器注册**（让 Flutter 能渲染新 `type`）。

### 7.1 注入 JS 模块（QuickjsHostMount）

通过 `QuickjsHostMount` 向 QuickJS 运行时注册 ES 模块。`quickjs_ui` 自身会自动注入 `quickjs_ui` helper 模块；第三方插件需额外传入 `mounts`。

**示例：`lemon_js_ui_video_player`**

Dart 侧定义模块：

```dart
const QuickjsHostMount mount = QuickjsHostMount(
  name: 'quickjs_ui:plugin:video_player',
  modules: [
    QuickjsHostModule.esModule(
      specifier: 'quickjs_ui/video_player',
      source: '''
export function VideoPlayer(props = {}) {
  return {
    type: 'VideoPlayer',
    key: props.key ?? 'video-player',
    source: props.source,
    playing: props.playing === true,
    onProgress: props.onProgress,
    // ...
  };
}
''',
    ),
  ],
);
```

Flutter 页面挂载：

```dart
QuickjsUiView.asset(
  path: 'assets/quickjs_ui/video_player_plugin_page.mjs',
  mounts: const [QuickjsUiVideoPlayerPlugin.mount],
  registry: _videoPlayerRegistry,
)
```

JS 页面使用：

```js
import { VideoPlayer } from 'quickjs_ui/video_player';

VideoPlayer({
  source: 'https://example.com/video.mp4',
  playing: state.playing,
  onProgress: actions.onProgress()
})
```

### 7.2 注册 Dart 渲染器（QuickjsUiComponentRegistry）

仅有 JS helper 不够，还需在 Flutter 侧注册对应 `type` 的 builder：

```dart
final registry = QuickjsUiComponentRegistry.defaults()
  ..register('VideoPlayer', QuickjsUiVideoPlayerPlugin.build);
```

或使用插件提供的工厂：

```dart
final registry = QuickjsUiVideoPlayerPlugin.registry();
```

**重要：** `registry` 应是**稳定实例**，不要在 `build()` 里每次 `new`，否则窗口 resize 时会重建 renderer 引发事件队列问题。

### 7.3 带生命周期的自定义控件

复杂原生控件可注册 lifecycle controller：

```dart
registry.registerLifecycle<MyController>(
  'MyWidget',
  createController: (node) => MyController(node),
  build: (context, node, controller) => MyNativeWidget(controller: controller),
);
```

### 7.4 JS 侧 Component 辅助函数

用 `Component()` 封装可复用的 schema 组件（不要求 Dart 注册，只要 `type` 已被 registry 识别）：

```js
import { Component, Padding, Text } from 'quickjs_ui';

export const Card = Component((props) => ({
  type: 'Card',
  tone: props.tone,
  child: Padding({ padding: 16, child: props.child })
}));
```

Dart 侧为 `Card` 注册 renderer 后即可在任意页面使用。

---

## 8. 宿主与 JS 互操作

### 8.1 整体架构

```
┌─────────────────────────────────────────────────────┐
│  Flutter 宿主                                        │
│  QuickjsUiView / QuickjsUiController                │
│  QuickjsUiHostCapabilities → QuickjsHostMount       │
│  QuickjsUiComponentRegistry                         │
└──────────────┬──────────────────────┬───────────────┘
               │ mount / provider      │ 渲染 UiNode
               ▼                       ▼
┌─────────────────────────────────────────────────────┐
│  QuickJS 运行时                                      │
│  globalThis.quickjsUiHost   — 系统宿主 API           │
│  globalThis.quickjsUiApp    — 应用自定义 API         │
│  globalThis.quickjsUiNavigation — JS 路由 API        │
│  Page({ build, ...methods }) — 页面逻辑与 state      │
└─────────────────────────────────────────────────────┘
```

### 8.2 系统宿主 API（quickjsUiHost）

通过 `QuickjsUiHostCapabilities` 挂载，JS 侧使用 `globalThis.quickjsUiHost`：

| API | 说明 |
|---|---|
| `toast(message, options?)` | 轻提示 |
| `confirm(message, options?)` | 确认框，返回 `boolean` |
| `dialog({ title, content, ... })` | 对话框，`content` 可为 UiNode |
| `snackbar({ message, ... })` | SnackBar |
| `bottomSheet({ title, content, ... })` | 底部弹层 |
| `navigationIntent(intent)` | 导航意图，由宿主 route registry 解析 |
| `clipboard.readText()` / `writeText(text)` | 剪贴板 |
| `storage.getItem(key)` / `setItem(key, value)` / `removeItem(key)` | 键值存储 |
| `network(request)` | 网络请求（需启用 handler） |
| `fileSystem(operation)` | 文件操作（需启用 handler） |
| `nativeCall(method, payload?)` | 通用原生调用 |

#### Dart 侧配置示例

```dart
final capabilities = QuickjsUiHostCapabilities(
  groups: [
    QuickjsUiCapabilityGroup.system(
      options: const QuickjsUiHostCapabilityOptions(
        enabled: {
          QuickjsUiHostCapability.toast,
          QuickjsUiHostCapability.confirm,
          QuickjsUiHostCapability.navigation,
          QuickjsUiHostCapability.storage,
          QuickjsUiHostCapability.nativeCall,
        },
      ),
      handlers: QuickjsUiHostApiHandlers(
        onToast: (message, options) async {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(message)));
          return {'shown': true, 'message': message};
        },
        onConfirm: (message, _) async => true,
        onNavigationIntent: (intent) async {
          final route = intent['route'] as String;
          // 查 route registry，Navigator.push(...)
          return {'route': route};
        },
        onNativeCall: (method, payload) async {
          return {'method': method, 'payload': payload, 'ok': true};
        },
      ),
      storage: {'boot': 'ready'},
    ),
  ],
);

QuickjsUiView.asset(
  path: 'assets/quickjs_ui/host_capabilities_page.mjs',
  mounts: capabilities.mounts,
  grantedPermissions: capabilities.permissions,
);
```

#### JS 侧调用示例

```js
async callToast(state) {
  const result = await quickjsUiHost.toast('Hello from JS', { source: 'mjs' });
  return { lastResult: result };
}

async callNative(state) {
  const result = await quickjsUiHost.nativeCall('example.echo', { value: 42 });
  return { lastResult: result };
}
```

### 8.3 应用自定义 API（quickjsUiApp）

通过 `QuickjsUiCapabilityGroup.functions` 或 `.methods` 注入业务方法：

```dart
QuickjsUiCapabilityGroup.functions(
  name: 'app-custom',
  globalName: 'quickjsUiApp',
  functions: {
    'customEcho': (Object? value) => 'echo:$value',
    'add': (num a, num b) => a + b,
  },
)
```

JS 侧：

```js
const text = await quickjsUiApp.customEcho('hello');
const sum = await quickjsUiApp.add(20, 22);
```

### 8.4 导航互操作

**JS → 宿主：** `quickjsUiHost.navigationIntent({ route, params })`，宿主在 route registry 中查找并 `Navigator.push`。

**JS → JS 页面：** `quickjsUiNavigation.push({ route, path, params })`，由 `QuickjsUiNavigator` 管理 JS 路由栈。

**路由生命周期：** 使用 `onRouteEnter` / `onRouteLeave` / `onRouteResult` hook；Dart 侧对应 `controller.routeLifecycle(...)`。

### 8.5 Dart → JS

| 方式 | API | 说明 |
|---|---|---|
| 初始参数 | `QuickjsUiView.initialProps` | 页面 `mount` 时传入 |
| 显式改状态 | `controller.setState({'key': value})` | 合并 patch 并 re-render |
| 模拟事件 | `controller.dispatch({'method': 'foo', 'value': true})` | 触发页面方法 |
| 生命周期 | `controller.lifecycle('show')` | 触发 hook |
| 读取状态 | `controller.state` | Dart 侧 state 快照（权威在 JS） |
| 读取 UI 树 | `controller.node` | 当前 `QuickjsUiNode` |
| 刷新 | `controller.refresh()` | 强制 `commit()` |
| 控制台 | `controller` 构造时 `onConsole` | 接收 JS `console.log` |

```dart
final controller = QuickjsUiController();

// 宿主按钮触发 JS 逻辑
FilledButton(
  onPressed: () => controller.dispatch({'method': 'increment'}),
  child: const Text('Dart 触发 +1'),
)

QuickjsUiView.asset(
  path: 'assets/quickjs_ui/counter_page.mjs',
  controller: controller,
)
```

### 8.6 权限

- `QuickjsUiHostCapabilities` 的 `permissions` 集合描述已声明能力。
- `QuickjsUiView.grantedPermissions` 传入实际授权。
- `QuickjsUiPermissionPolicy.restricted(allowed: {...})` 可在应用层限制页面 manifest 请求的权限。

未授权的 provider 调用会被 QuickJS 宿主层拒绝。

---

## 9. 页面加载方式

| 方式 | API | 场景 |
|---|---|---|
| Asset 单文件 | `QuickjsUiView.asset(path: '...')` | 开发期最常见 |
| 本地文件 | `QuickjsUiView.file(path: '...')` | 桌面端调试 |
| 网络 URL | `QuickjsUiView.network(url: '...')` | 远程页面 |
| 已有 Plugin | `QuickjsUiView.plugin(plugin)` | 手动构造 |
| 发布包 | `QuickjsUiBundle.assetPackage(...)` | 生产分发、checksum 校验 |

发布包格式（`main.mjs` + `manifest.json`）见 [quickjs_ui_package_format.md](../../../docs/quickjs_ui_package_format.md)。

生成 manifest：

```bash
dart run lemon_js_ui:manifest --root assets/quickjs_ui/my_package --id com.example.app --version 1.0.0
```

---

## 10. 开发辅助

| 资源 | 路径 | 用途 |
|---|---|---|
| JS helper 源码 | `packages/lemon_js_ui/js/quickjs_ui.js` | `Page`、`Component`、控件 helper |
| TypeScript 类型 | `packages/lemon_js_ui/js/quickjs_ui.d.ts` | 编辑器代码提示与 `checkJs` 校验 |
| JSON Schema | `packages/lemon_js_ui/js/quickjs_ui.schema.json` | Schema 校验 |
| 示例页面 | `../../examples/lemon_js_example/assets/quickjs_ui/` | 各特性演示 |
| 示例 Flutter 页 | `../../examples/lemon_js_example/lib/pages/` | 宿主集成参考 |
| 示例 jsconfig | `../../examples/lemon_js_example/assets/quickjs_ui/jsconfig.json` | 编辑器提示配置参考 |

修改 `quickjs_ui.js` 后需重新生成 Dart helper：

```bash
cd packages/lemon_js_ui
dart run tool/generate_quickjs_ui_helpers.dart
```

### 10.1 配置编辑器代码提示

quickjs_ui 的 JS 页面本质是 **ES Module（`.mjs`）**，运行时由 QuickJS 加载；编辑器侧通过 **`jsconfig.json` + `quickjs_ui.d.ts`** 提供补全、跳转和类型检查。不需要把页面改成 TypeScript，也不依赖 Node 打包。

#### 10.1.1 前置条件

- 使用 **VS Code** 或 **Cursor**（内置 JavaScript/TypeScript 语言服务即可）。
- JS 页面目录下放置 `jsconfig.json`。
- 页面里保持标准导入：

```js
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';
```

配置成功后，编辑器可提示：

- `Page()`、`Component()` 及页面方法保留名
- 内置控件名与常用属性（`child`、`children`、`onPressed` 等）
- 主题 token（`$primary`、`$surface`、`$text.bodyLarge` 等）
- `quickjsUiHost`、`quickjsUiNavigation` 等全局宿主 API（见 `.d.ts` 的 `declare global`）

#### 10.1.2 最小配置（monorepo / path 依赖）

在存放 JS 页面的目录创建 `jsconfig.json`。本仓库示例见
`../../examples/lemon_js_example/assets/quickjs_ui/jsconfig.json`：

```json
{
  "compilerOptions": {
    "checkJs": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",
    "baseUrl": ".",
    "paths": {
      "quickjs_ui": [
        "../../../../packages/lemon_js_ui/js/quickjs_ui.d.ts"
      ]
    }
  },
  "include": [
    "**/*.mjs",
    "**/*.js"
  ]
}
```

说明：

| 字段 | 作用 |
|---|---|
| `checkJs: true` | 在 `.mjs` 中启用类型检查（未标注类型的参数会较宽松） |
| `paths.quickjs_ui` | 把 `import ... from 'quickjs_ui'` 映射到类型声明文件 |
| `include` | 让子目录（如 `bundle_counter/`、`package_demo/`）也纳入提示范围 |

`paths` 中的相对路径：**从 `jsconfig.json` 所在目录** 指向 `quickjs_ui.d.ts`。若你的页面放在其他 asset 目录，按实际层级调整 `../` 数量。

#### 10.1.3 pub.dev 依赖时的路径

若通过 pub 引用 `lemon_js_ui`，`dart pub get` 后包位于 Pub cache。`jsconfig.json` 仍放在你的 JS 页面根目录，将 `paths` 指到该包内的声明文件，例如：

```json
{
  "compilerOptions": {
    "checkJs": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",
    "baseUrl": ".",
    "paths": {
      "quickjs_ui": [
        "../../../../.pub-cache/hosted/pub.dev/lemon_js_ui-<version>/js/quickjs_ui.d.ts"
      ]
    }
  },
  "include": ["**/*.mjs"]
}
```

更稳妥的做法：

- 使用 **`path:` 依赖**（团队内 monorepo）时直接相对路径指向 `packages/lemon_js_ui/js/quickjs_ui.d.ts`；
- 或在应用仓库中 **复制一份** `jsconfig.json`，把路径写成你机器上 `flutter pub cache path` 下的实际位置。

类型文件路径也可在本地用下面命令查看：

```bash
dart pub cache path
# 进入该目录下的 hosted/pub.dev/lemon_js_ui-<version>/js/quickjs_ui.d.ts
```

#### 10.1.4 第三方 lemon_js_ui 插件类型

使用插件子路径 import 时，在 `paths` 中追加映射。例如 `lemon_js_ui_video_player`：

```json
{
  "compilerOptions": {
    "checkJs": true,
    "module": "ESNext",
    "moduleResolution": "Bundler",
    "target": "ES2022",
    "baseUrl": ".",
    "paths": {
      "quickjs_ui": [
        "../../../packages/lemon_js_ui/js/quickjs_ui.d.ts"
      ],
      "quickjs_ui/video_player": [
        "../../../../packages/lemon_js_ui_video_player/js/quickjs_ui_video_player.d.ts"
      ]
    }
  },
  "include": ["**/*.mjs"]
}
```

页面中即可同时获得主包与插件的提示：

```js
import { Page, Text } from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';
```

插件作者应为自己的包提供类似的 `js/*.d.ts`，并通过 `declare module 'quickjs_ui/xxx'` 扩展模块名。

#### 10.1.5 为页面 state / props 增强提示（可选）

`.d.ts` 已覆盖控件与 `Page()` 形状。若需要 **业务 state 字段** 的补全，可在页面文件顶部用 JSDoc 标注：

```js
/**
 * @typedef {Object} CounterProps
 * @property {string} [title]
 * @property {number} [initialCount]
 */

/**
 * @typedef {Object} CounterState
 * @property {number} count
 */

/** @type {import('quickjs_ui').QuickjsUiPageDefinition<CounterState, CounterProps>} */
export default Page({
  name: 'CounterPage',

  /** @param {CounterProps} props */
  createState(props) {
    return { count: props.initialCount ?? 0 };
  },

  /**
   * @param {CounterState} state
   * @param {CounterProps} props
   */
  build(state, props, actions) {
    return Text(`${props.title ?? 'Counter'}: ${state.count}`);
  },

  /** @param {CounterState} state */
  increment(state) {
    return { count: state.count + 1 };
  }
});
```

这样在 `state.`、`props.` 上会列出你声明的字段；`actions.increment()` 等方法名仍由 `Page()` 对象上的函数自动推导。

#### 10.1.6 JSON Schema（非 JS 页面）

若直接编写 JSON UI schema（不经过 JS），可在 VS Code/Cursor 中为文件关联 schema：

```json
{
  "$schema": "../../../packages/lemon_js_ui/js/quickjs_ui.schema.json"
}
```

或在项目 `.vscode/settings.json` 中配置 `json.schemas`，用于校验 `type`、`children` 等字段。

#### 10.1.7 常见问题

| 现象 | 处理 |
|---|---|
| `import 'quickjs_ui'` 报「找不到模块」 | 检查 `paths` 是否指向存在的 `quickjs_ui.d.ts`；修改后执行 **Developer: Reload Window** |
| 只有语法高亮、没有补全 | 确认当前文件扩展名在 `include` 内（如 `*.mjs`）；确认已保存 `jsconfig.json` |
| 子目录页面无提示 | 将 `include` 改为 `**/*.mjs`，或在上级目录再放一份 `jsconfig` |
| `$surface` 等 token 无提示 | 主题 token 在 `.d.ts` 的 `QuickjsUiThemeColorToken` 中；自定义 token 需宿主注册 `QuickjsUiDesignTokens` |
| 颜色运行时报 `must be an int or hex string` | 说明 token 未在运行时主题中解析；优先使用 `.d.ts` 列出的 `$error`、`$surface` 等，或直接用 `#RRGGBB` |

代码提示仅作用于 **开发期编辑体验**，不影响 Flutter 运行时加载；运行时仍加载 asset 中的 `.mjs` 与 QuickJS helper。

---

## 11. 最佳实践

1. **Handler 只返回 patch**，不要 `return { ...state, ... }`，无变化返回 `null`。
2. **registry / capabilities 用稳定实例**，避免在 `build()` 中创建。
3. **连续值变化控件**（Switch、Slider、进度）走 sample；**离散操作**（按钮、提交）走 command。
4. **自定义控件**同时提供 JS helper（生成 schema）和 Dart registry（渲染）。
5. **第三方模块**通过 `QuickjsHostMount.modules` 注入，`specifier` 与 JS `import` 路径一致。
6. **异步宿主调用**在 handler 里 `await`，返回 patch 即可，不必手动 `setState`。
7. 排查错误时关注日志前缀 `quickjs_ui runtime call failed call=...`，常见值：`dispatch`、`render`、`lifecycle`、`state`。

---

## 12. 示例索引

| 示例 | 路径 | 演示内容 |
|---|---|---|
| 计数器 | `counter_page.mjs` | 最小 Page + 事件 |
| 控件集 | `controls_page.mjs` | TextField、Image、主题 token |
| 自定义组件 | `custom_components_page.mjs` | `Component()` + Dart registry |
| 滚动与动画 | `scroll_transition_page.mjs` | `scrollToKey`、手势、列表过渡 |
| 宿主能力 | `host_capabilities_page.mjs` | `quickjsUiHost` / `quickjsUiApp` |
| 视频插件 | `video_player_plugin_page.mjs` | 第三方模块 + lifecycle 控件 |
| 导航 | `navigation_*.mjs` | JS 路由与 route lifecycle |
| 表单 | `profile_form_page.mjs` | 多控件表单 |
| 发布包 | `package_demo/` | manifest 与 zip 包 |
