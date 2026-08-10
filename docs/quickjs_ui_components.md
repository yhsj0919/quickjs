# quickjs_ui 组件

0.4.0 引入轻量级 JS 组件约定。JS 组件仍只是返回 quickjs_ui UI Schema 的函数，
不会创建或持有 Flutter `Widget`，也不拥有页面 Session。

## JS 组件模块

使用 `Component(render)` 定义可复用的 Schema 生成函数：

```js
import { Column, Component, ElevatedButton, Text } from 'quickjs_ui';

export const CounterCard = Component((props) => {
  return Column({
    children: [
      Text(props.title),
      ElevatedButton({
        onPressed: props.onIncrement,
        child: Text(`Count: ${props.count}`)
      })
    ]
  });
});
```

页面向下传递普通 props，向上传递事件映射：

```js
import { Page } from 'quickjs_ui';
import { CounterCard } from '../components/counter_card.mjs';

export default Page({
  createState() {
    return { count: 0 };
  },
  build(state, props, actions) {
    return CounterCard({
      title: props.title,
      count: state.count,
      onIncrement: actions.increment({ step: 1 })
    });
  },
  increment(state, payload) {
    return { ...state, count: state.count + payload.step };
  }
});
```

事件协议刻意限制为 `{ method: 'increment', payload: { step: 1 } }` 等可序列化映射。
不要通过 UI Schema props 传递 JS 回调函数。

内置交互属性使用相同的事件映射协议。`Container`、`Padding`、`Center`、
`SizedBox`、`Image` 和 `ListView` 等布局/媒体包装节点支持 `onTap` 与
`onLongPress`。`ListView` 还支持 `onScroll`，事件包含 `pixels`、
`minScrollExtent`、`maxScrollExtent`、`viewportDimension` 和 `axis`。

表单控件由 JS state 控制。`TextField`、`Checkbox`、`Switch`、`Radio` 和
`DropdownButton` 渲染收到的 Schema 值，并通过 `onChanged` 分发新的 `value`；
Flutter 不保存权威业务状态。

基础隐式动画通过可序列化 props 显式启用。`Container` 可对尺寸、内外边距、对齐、
颜色/装饰及透明度执行动画；`Padding` 可对内边距执行动画。

```js
Container({
  width: state.expanded ? 240 : 120,
  opacity: state.enabled ? 1 : 0.5,
  animationDurationMs: 180,
  animationCurve: 'easeOut',
  child: Text('Animated')
})
```

`Container` 和 `DecoratedBox` 的装饰也支持线性/径向渐变及一个或多个阴影：

```js
Container({
  decoration: {
    gradient: {
      colors: ['#177fd1', '#55b8ec', '#bdebfb'],
      stops: [0, 0.58, 1],
      begin: 'topCenter',
      end: 'bottomCenter'
    },
    boxShadow: {
      color: '#55000000',
      offset: { x: 0, y: 8 },
      blurRadius: 18,
      spreadRadius: 1
    }
  }
})
```

`Image.alignment` 控制图像在边界内的位置。`Stack` 接受 `clipBehavior`，默认使用
`hardEdge` 裁剪；`Wrap` 与 Flutter 一致，默认采用水平方向。

高频事件可在跨越 QuickJS 边界前启用渲染器侧合并：

```js
{
  type: 'ListView',
  onScroll: {
    method: 'scrollList',
    throttleMs: 100,
    coalesceKey: 'feed:list:onScroll'
  }
}
```

`throttleMs` 立即发送首个事件，并在时间窗口内合并后续事件，只保留最新 payload。
`debounceMs` 等待事件停止指定时间，同样只保留最新 payload。`dropMs` 发送首个事件并
丢弃窗口内后续事件，不保留待发送的最新事件。这些字段也可以放在 `policy` 下。

## 宿主渲染组件

JS 组件可以返回自定义 `type`。宿主必须在 `QuickjsUiComponentRegistry` 中注册该类型，
否则渲染会因未知节点类型失败。

```js
import { Component, Text } from 'quickjs_ui';

export const Badge = Component((props) => {
  return {
    type: 'Badge',
    tone: props.tone,
    child: Text(props.label)
  };
});
```

```dart
final registry = QuickjsUiComponentRegistry.defaults()
  ..register('Badge', (context, node) {
    return DecoratedBox(
      decoration: const BoxDecoration(color: Color(0xffeeeeee)),
      child: context.child(node) ?? const SizedBox.shrink(),
    );
  });
```

自定义渲染器的高频原生回调应使用 `context.dispatchEvent()`，以共享同一事件策略。
例如，视频播放器可丢弃过于频繁的进度采样，同时立即发送结束事件：

```dart
context.dispatchEvent(
  QuickjsUiProps.event(node.props['onProgress'])!,
  defaultCoalesceKey: 'VideoPlayer:${node.props['key']}:onProgress',
  payload: <String, Object?>{
    'positionMs': position.inMilliseconds,
    'durationMs': duration.inMilliseconds,
  },
);
```

允许跳过中间值的状态采样（如播放进度）使用 `dropMs`；需要每个窗口最新值的场景
（如滚动位置）使用 `throttleMs`；等待稳定值的场景（如文字组合或缩放输入）使用
`debounceMs`。

渲染器事件分发器会在事件抵达页面 Session 前施加背压。每个 `coalesceKey` 最多有一个
待处理事件；待处理队列也有容量上限，满载时丢弃最早事件。未提供 `coalesceKey` 的
定时策略会立即发送且不进入队列，因此高频自定义组件必须提供稳定 key。

普通 `context.dispatch()` 仅用于 `onEnded`、`onError`、`onPlay` 或 `onPause`
等低频事件。

## 渲染器事件入口

`QuickjsUiView` 不会把渲染器回调直接连接到 `QuickjsUiController.dispatch()`。
所有渲染器及自定义组件事件均经过 `QuickjsUiEventIngress`，由其入队并在当前帧后刷新，
避免页面状态更新在 Flutter `build` 期间同步重建 View。

自定义渲染器正常调用 `context.dispatch()` / `context.dispatchEvent()` 即可，
宿主代码不要再在调用外包裹 `addPostFrameCallback`。

完整管线、修复/重构策略，以及原生视频播放器示例采用的 `seekToken` / `restartToken`
命令式控制模式见 `docs/quickjs_ui_cross_cutting.md`。

`QuickjsUiView` 与 `QuickjsUiNavigator` 应使用同一注册表，保证嵌套 JSUI 路由一致渲染
自定义组件类型。所有渲染节点还可使用 `onMouseEnter`、`onMouseExit`、`onMouseHover`、
`onMouseScroll`、`onPointerDown`、`onPointerMove`、`onPointerUp` 和
`onPointerCancel`。
指针 payload 包含局部/全局坐标、增量、按键、压力、设备 `kind` 和时间戳。滚轮事件还
包含 `scrollDeltaX` 与 `scrollDeltaY`。高频悬停和移动事件按帧合并。常用系统光标可通过
`mouseCursor`（或 `cursor`）设置，例如 `click`、`text`、`move`、`grab` 和缩放光标。

每个渲染节点共享相同输入行为。`hitTestBehavior` 接受 `deferToChild`、`opaque` 或
`translucent`；`ignorePointer` 允许事件穿透子树，`absorbPointer` 则消费事件。
支持键盘的节点可使用 `autofocus`、`canRequestFocus`、`onFocus`、`onBlur`、
`onKeyDown` 和 `onKeyUp`。键盘与指针 payload 均包含 Ctrl/Shift/Alt/Meta 修饰键状态。

布局与视觉基础能力包括 Container 最小/最大约束，独立的 `translate`、`scale`、
`rotate` 和 `transformAlignment` 快捷属性，分边框线、圆形装饰及背景混合模式。
Text 支持 `maxLines`、`softWrap` 和 `overflow`；Image 支持 `repeat`、着色 `color`
和 `blendMode`；可滚动组件支持 `physics` 及可选 `scrollbar`。Stack 的绘制和命中顺序
遵循 children 数组顺序，越靠后的子节点越靠上。

弹出框、下拉面板、上下文菜单、引导气泡等系统层内容使用 `AnchoredOverlay`。
`anchor` 保持在普通布局中，`overlay` 在 Flutter Overlay 中渲染并跟随锚点。
`placement` 支持自动定位、上下方向的 start/center/end、左右及居中位置；`gap` 设置
基础锚点距离。主轴正 `offset` 会让浮层沿放置方向远离锚点，交叉轴仍采用屏幕坐标方向。
`screenPadding` 预留屏幕边缘空间，原生定位器会在需要时翻转或平移内容。
`consumeOutsideTap`、`useRootOverlay`、`animated`、`matchAnchorWidth` 和
`onDismissed` 控制常见弹出层行为。需要在用户于锚点外拖动或滚动时保持打开，可设置
`dismissOnTapOutside: false`；菜单和下拉面板默认仍为 `true`。
