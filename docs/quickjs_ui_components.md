# quickjs_ui components

0.4.0 introduces a lightweight JS component convention. A JS component is still
only a function that returns quickjs_ui UI schema. It does not create or hold a
Flutter `Widget`, and it does not own a page session.

## JS component modules

Use `Component(render)` for reusable schema-producing functions:

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

Pages pass plain props down and pass event maps up:

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

The event protocol is intentionally restricted to serializable maps such as
`{ method: 'increment', payload: { step: 1 } }`. Do not pass JS callback
functions through UI schema props.

Built-in interactive props use the same event map protocol. `onTap` and
`onLongPress` are supported on layout/media wrapper nodes such as `Container`,
`Padding`, `Center`, `SizedBox`, `Image`, and `ListView`. `ListView` also
supports `onScroll`; the dispatched event includes `pixels`, `minScrollExtent`,
`maxScrollExtent`, `viewportDimension`, and `axis`.

Form controls are controlled by JS state. `TextField`, `Checkbox`, `Switch`,
`Radio`, and `DropdownButton` render the schema value they receive and dispatch
`onChanged` with the next `value`. They do not keep authoritative state in
Flutter.

Basic implicit animation is opt-in with serializable props. `Container` animates
size, padding, margin, alignment, color/decoration, and opacity; `Padding`
animates padding.

```js
Container({
  width: state.expanded ? 240 : 120,
  opacity: state.enabled ? 1 : 0.5,
  animationDurationMs: 180,
  animationCurve: 'easeOut',
  child: Text('Animated')
})
```

`Container` and `DecoratedBox` decorations also support linear/radial
gradients and one or more box shadows:

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

`Image.alignment` controls image placement inside its bounds. `Stack` accepts
`clipBehavior` and clips with `hardEdge` by default; `Wrap` defaults to the
horizontal direction, matching Flutter.

High-frequency events can opt into renderer-side coalescing before crossing the
QuickJS boundary:

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

`throttleMs` sends the first event immediately and coalesces later events in the
window, keeping only the latest payload. `debounceMs` waits until events stop
for the configured window, also keeping only the latest payload. `dropMs` sends
the first event and discards later events in the window; it does not keep a
pending latest event. The same fields may be placed under `policy`.

## Host renderer components

JS components can return a custom `type`. The host must register that type in
`QuickjsUiComponentRegistry`; otherwise rendering fails with an unknown node type.

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

Custom renderers should use `context.dispatchEvent()` for high-frequency native
callbacks so they share the same event policy. For example, a video player can
drop overly frequent progress ticks while still sending terminal events
immediately:

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

Use `dropMs` for status samples where skipped intermediate values are fine, such
as playback progress. Use `throttleMs` when the latest value in each window
matters, such as scroll position. Use `debounceMs` for settled values, such as
text composing or resize-like input.

The renderer event dispatcher applies backpressure before events reach the page
session. Each `coalesceKey` can have at most one pending event. The dispatcher
also has a bounded pending queue; when the queue is full, the oldest pending
event is discarded. Timing policies without a `coalesceKey` are sent
immediately and are not queued, so high-frequency custom components should
always provide a stable key.

Use plain `context.dispatch()` only for low-frequency events such as `onEnded`,
`onError`, `onPlay`, or `onPause`.

## Renderer event ingress

`QuickjsUiView` does not wire renderer callbacks directly to
`QuickjsUiController.dispatch()`. All renderer and custom-component events go
through `QuickjsUiEventIngress`, which queues them and flushes after the
current frame. This keeps page state updates from synchronously rebuilding the
view during Flutter `build`.

Custom renderers should call `context.dispatch()` / `context.dispatchEvent()`
normally. Do not add `addPostFrameCallback` around those calls in host code.

See `docs/quickjs_ui_cross_cutting.md` for the full pipeline, fix/refactor
policy, and the `seekToken` / `restartToken` imperative-control pattern used by
the native video player example.

Use the same registry with `QuickjsUiView` or `QuickjsUiNavigator` so nested
JSUI routes render custom component types consistently.
All rendered nodes can also use `onMouseEnter`, `onMouseExit`, `onMouseHover`,
`onMouseScroll`, `onPointerDown`, `onPointerMove`, `onPointerUp`, and
`onPointerCancel`.
Pointer payloads include local/global coordinates, deltas, buttons, pressure,
device `kind`, and a timestamp. Scroll events also include `scrollDeltaX` and
`scrollDeltaY`. High-frequency hover and move events are
coalesced per frame. Use `mouseCursor` (or `cursor`) for common system cursors
such as `click`, `text`, `move`, `grab`, and resize cursors.

Input behavior is shared by every rendered node. `hitTestBehavior` accepts
`deferToChild`, `opaque`, or `translucent`; `ignorePointer` lets events pass
through a subtree, while `absorbPointer` consumes them. Keyboard-capable nodes
can use `autofocus`, `canRequestFocus`, `onFocus`, `onBlur`, `onKeyDown`, and
`onKeyUp`. Key and pointer payloads include Ctrl/Shift/Alt/Meta modifier state.

Layout and visual fundamentals include Container min/max constraints,
independent `translate`, `scale`, `rotate`, and `transformAlignment` shortcuts,
per-side borders, circle decorations, and background blend modes. Text supports
`maxLines`, `softWrap`, and `overflow`. Images support `repeat`, tint `color`,
and `blendMode`. Scrollable components support `physics` and an optional
`scrollbar`. Stack paint and hit-test order follows child array order; later
children are above earlier children.

Use `AnchoredOverlay` for popovers, dropdown panels, context menus, teaching
bubbles, and similar system-layer content. Its `anchor` remains in normal
layout while `overlay` renders in Flutter's Overlay and follows the anchor.
`placement` supports automatic, top/bottom start/center/end, left/right, and
center positions. `gap` sets the base anchor distance. Positive main-axis
`offset` values move the overlay farther in its placement direction (up for
top, down for bottom, left for left, and right for right); the cross-axis keeps
screen-coordinate direction. `screenPadding` reserves edge space and the
native positioner flips or shifts content when needed.
`consumeOutsideTap`, `useRootOverlay`, `animated`, `matchAnchorWidth`, and
`onDismissed` control common popover behavior.
Set `dismissOnTapOutside: false` for overlays that must remain open while the
user drags or scrolls outside the anchor; the default remains `true` for menus
and dropdown panels.
