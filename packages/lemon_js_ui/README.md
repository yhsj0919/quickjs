# lemon_js_ui

`lemon_js_ui` 是基于 `lemon_js` 的声明式动态 UI 框架。页面状态和交互逻辑运行在
JavaScript 中，Flutter 将 JS 返回的 Schema 渲染成原生 Widget。它适合动态业务页、
插件登录页、小程序入口和可下发 UI，不是 HTML/DOM 渲染器。

支持 Android、iOS、macOS、Linux、Windows 和 Web。

## 安装

```yaml
dependencies:
  lemon_js_ui: ^0.2.0
```

```dart
import 'package:lemon_js_ui/lemon_js_ui.dart';
```

## 先生成代码提示

在开始写 JS 页面前运行：

```bash
dart run lemon_js_ui:codegen --root assets/quickjs_ui
```

工具会在页面目录生成或更新 `jsconfig.json`、类型声明入口和模块映射，使 VS Code 能提示
`Page()`、组件属性、事件和 Canvas API。第三方 UI 插件的声明文件可通过 `--types` 加入：

```bash
dart run lemon_js_ui:codegen \
  --root assets/quickjs_ui \
  --types path/to/plugin_types.d.ts
```

完整配置见[代码提示说明](doc/usage.md#0-先配置代码提示)。

## 最小页面

创建 `assets/quickjs_ui/counter_page.mjs`：

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
        Text(`${props.title ?? 'Counter'}: ${state.count}`),
        ElevatedButton({
          child: Text('Add'),
          onPressed: page.increment()
        })
      ]
    });
  },

  increment(state) {
    return { count: state.count + 1 };
  }
});
```

在 `pubspec.yaml` 中声明资源：

```yaml
flutter:
  assets:
    - assets/quickjs_ui/
```

Flutter 页面中加载：

```dart
JsUiView.asset(
  path: 'assets/quickjs_ui/counter_page.mjs',
  initialProps: const <String, Object?>{
    'title': 'QuickJS UI',
    'initialCount': 0,
  },
  loadingBuilder: (_) => const Center(
    child: CircularProgressIndicator(),
  ),
  errorBuilder: (_, error) => Text('$error'),
)
```

JS 持有 state 并处理事件；Flutter 负责渲染和把事件送回 JS。

## 加载方式

`JsUiView` 支持多种来源：

- `JsUiView.asset()`：Flutter asset；
- `JsUiView.file()`：原生平台文件；
- `JsUiView.network()`：网络页面；
- `JsUiView.plugin()`：已经构建的 QuickJS 插件；
- `JsUiBundle`：多模块或 ZIP UI 包。

网络加载仍受来源策略、CORS 和宿主权限限制。页面加载失败可通过 `errorBuilder` 显示系统
回退 UI。

## 内置能力

主要组件包括布局、文本、按钮、表单、列表、图片、SVG、浮层、主题、动画和 Canvas。
此外还提供：

- `JsUiController`：刷新、暂停、恢复和宿主控制；
- `JsUiPlugin`：第三方 JS 模块、宿主 features 和 Flutter 组件注册；
- `JsUiNavigator`：受控页面导航；
- `JsUiComponentRegistry`：注册自定义原生组件；
- Inspector、加载指标、网络记录和性能报告。

直接驱动页面协议、编写基准或自定义宿主时，才使用低层 Session 入口：

```dart
import 'package:lemon_js_ui/lemon_js_ui_session.dart';

final session = JsUiSession(engine: engine);
```

普通应用不需要创建 Session，使用 `JsUiView` 或 `JsUiController` 即可。

Canvas 与控件动画由 Flutter VSync 驱动。系统启用“减少动态效果”时，Flutter Web 的
`MediaQuery.disableAnimations` 可能停止动画；排查方法见
[Canvas 与动画文档](doc/canvas_and_animation.md)。

## 第三方 UI 插件

插件通常同时提供 JS module、`.d.ts` 类型声明和 Flutter renderer：

```dart
JsUiView.asset(
  path: 'assets/quickjs_ui/page.mjs',
  uiPlugins: <JsUiPlugin>[
    thirdPartyPlugin,
  ],
)
```

页面只能导入已经由宿主注入的模块。缺少插件时会明确报模块或组件未注册错误。

视频组件示例见
[lemon_js_ui_video_player](https://pub.dev/packages/lemon_js_ui_video_player)。

## 示例与文档

- [使用指南](doc/usage.md)
- [架构与生命周期](doc/architecture.md)
- [Canvas 与动画](doc/canvas_and_animation.md)
- [完整 Flutter 示例](https://github.com/yhsj0919/quickjs/tree/master/examples/lemon_js_example)
- [JS 页面目录](https://github.com/yhsj0919/quickjs/tree/master/examples/lemon_js_example/assets/quickjs_ui)
- [组件参考](https://github.com/yhsj0919/quickjs/blob/master/docs/quickjs_ui_components.md)
- [跨组件能力](https://github.com/yhsj0919/quickjs/blob/master/docs/quickjs_ui_cross_cutting.md)

完整组件、Canvas 和性能示例保留在 GitHub 仓库；README 只提供最小接入路径。
