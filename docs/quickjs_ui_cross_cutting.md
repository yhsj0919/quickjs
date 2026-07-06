# quickjs_ui cross-cutting modules

This document tracks large quickjs_ui concerns that cut across schema, renderer,
custom components, navigation, resource loading, and tooling. These are not
single-widget features.

## Design Rule

For each cross-cutting module, start from Flutter's native model and expose only
the serializable subset that fits quickjs_ui. Do not copy Web/DOM concepts when
Flutter already has a stronger primitive.

### Fix and Refactor Policy

> **功能修复允许重构，不要一直在错误的路径上打补丁。**

When a bug reveals a lifecycle or ownership mismatch, fix the architecture first.
Do not stack frame-timing workarounds across `QuickjsUiView`, `QuickjsUiController`,
custom renderers, and page code unless the workaround is itself the documented
contract.

Use this decision checklist:

1. Name the real invariant being violated. Example: renderer callbacks must not
   synchronously rebuild the page while Flutter is still building widgets.
2. If the failure spans more than one layer, move the fix to the layer that owns
   the boundary instead of adding local `addPostFrameCallback` / deferred
   `setState` / extra `notifyListeners` calls.
3. Delete superseded patches after the structural fix lands. A correct design
   should make per-widget frame hacks unnecessary.
4. Document the new contract in this file and in `docs/quickjs_ui_components.md`
   so future custom renderers follow the same path.

Anti-patterns that were removed in favor of the renderer event ingress:

- `QuickjsUiView` deferring every controller notification with chained post-frame
  rebuild flags.
- `QuickjsUiController.dispatch()` notifying listeners before the page session
  finishes, then notifying again after completion.
- Custom renderers such as `VideoPlayer` deferring `onReady` / progress listeners
  with their own post-frame callbacks.

Preferred outcome: one documented pipeline, predictable tests, and example pages
that only express product behavior rather than Flutter frame timing.

Reference points in Flutter:

- Accessibility: `Semantics`, `SemanticsProperties`, `Tooltip`.
- Theme: `ThemeData`, `ColorScheme`, `TextTheme`.
- Focus and keyboard: `FocusNode`, `FocusTraversalPolicy`,
  `FocusTraversalGroup`, `Actions`, `Shortcuts`.
- Forms: `Form`, `FormField`, controlled input widgets.
- Scrolling: `ScrollController`, `ScrollNotification`.
- Animation: `ImplicitlyAnimatedWidget`, `AnimatedContainer`,
  `AnimatedPadding`, `AnimatedList`.

quickjs_ui should translate JS schema into these Flutter concepts, not create a
parallel UI runtime.

## Accessibility / Semantics

Goal: UI schema should carry enough semantic information for Flutter to expose a
usable accessibility tree.

Flutter reference: map schema props to `Semantics` / `SemanticsProperties` and
`Tooltip` where appropriate.

Planned scope:

- `semanticLabel`, `tooltip`, `role`, `enabled`, `selected`, and related
  semantic props.
- Screen reader labels for images, buttons, form fields, custom renderers, and
  list items.
- Focus order and traversal hints where Flutter defaults are not enough.
- Tests that verify semantic labels and roles for representative widgets.

Boundary: JS still returns serializable schema only. It does not receive Flutter
`SemanticsNode` or platform accessibility handles.

## Theme / Design Tokens

Goal: pages should reference host-provided design tokens instead of hard-coding
Flutter theme internals.

Flutter reference: resolve tokens through `ThemeData`, `ColorScheme`, and
`TextTheme`, while keeping token names stable across host apps.

Planned scope:

- Color, text style, spacing, radius, elevation, and motion tokens.
- Dark mode and high-contrast variants.
- Host brand theme injection.
- Token validation and fallback rules.
- Documentation for token names that are stable across host apps.

Boundary: JS schema may reference tokens such as `$colors.primary` or
`$text.titleMedium`; it should not depend on Flutter `ThemeData` object shape.

## Renderer → Page Event Pipeline

Goal: all renderer-originated UI events must cross the JS boundary without
violating Flutter build/layout invariants.

### Problem

Built-in widgets and custom renderers call `QuickjsUiRenderContext.dispatch()` or
`dispatchEvent()` from gesture handlers, scroll notifications, media callbacks,
and sometimes while a renderer rebuild is still in progress. A direct
`QuickjsUiController.dispatch()` from those call sites can:

1. Run JS `dispatch()` during Flutter `build`.
2. Call `notifyListeners()` and synchronously rebuild `QuickjsUiView`.
3. Trigger `setState() called during build` or silently drop the final refresh
   when notifications are merged.

Patching each call site or each custom renderer with post-frame deferral does not
scale and hides the real boundary violation.

### Architecture

`QuickjsUiView` owns a `QuickjsUiEventIngress`. The renderer and every custom
component still call `onEvent` through `QuickjsUiRenderContext`; the view wires
that to `ingress.submit()` instead of `controller.dispatch()`:

```text
Widget build / gesture / media callback
  -> QuickjsUiRenderContext.dispatch / dispatchEvent
  -> QuickjsUiEventDispatcher (optional coalesce / throttle / debounce)
  -> QuickjsUiEventIngress.submit (queue)
  -> post-frame flush
  -> QuickjsUiController.dispatch
  -> QuickjsUiSession.dispatch
  -> notifyListeners
  -> QuickjsUiView setState
```

Responsibilities:

| Layer | Responsibility |
| --- | --- |
| `QuickjsUiEventDispatcher` | Renderer-side backpressure for high-frequency events before they reach the page session. |
| `QuickjsUiEventIngress` | Frame-safe delivery into the controller; preserves event order per flush. |
| `QuickjsUiController` | Session serialization, error surface, and a single `notifyListeners()` after dispatch completes. |
| `QuickjsUiView` | Plain `setState` on controller changes; no frame-timing rebuild chain. |
| Custom renderers | Emit serializable events only; no post-frame dispatch workarounds. |

Implementation reference:

- `packages/quickjs_ui/lib/src/renderer/quickjs_ui_event_ingress.dart`
- `packages/quickjs_ui/lib/src/view/quickjs_ui_view.dart`

### Imperative control from JS state

When JS page state must command native side effects such as `seek`, `restart`, or
`replace source`, use explicit serializable props plus a monotonic token instead
of hidden renderer state.

Example from the native video player demo:

- `seekPositionMs` carries the target position.
- `seekToken` increments when the page wants the host renderer to apply that seek.
- `restartToken` uses the same pattern for "play from start".

This keeps media control declarative in schema, testable in page state, and
separate from the event ingress that handles renderer → page callbacks.

Boundary: ingress is owned by `QuickjsUiView` / navigator-hosted views. Code that
constructs `QuickjsUiRenderer` directly for isolated widget tests bypasses ingress
by design.

## Focus / Keyboard / IME

Goal: form and text input behavior should be predictable without leaking
platform-specific IME details into page code.

Flutter reference: use `FocusNode`, focus traversal policies, `Actions`, and
`Shortcuts` for native keyboard behavior. JS should receive events, not focus
handles.

Planned scope:

- Unified `onFocus` / `onBlur` events across text fields and custom inputs.
- `autofocus`, `enabled`, `readOnly`, and next/previous focus traversal.
- Keyboard action handling and form submit.
- Text composing / IME high-frequency update strategy.
- Event policies for `onChanged` and composing-like events.

Boundary: focus handles stay in Flutter. JS receives serializable events and
updates controlled state.

## Schema Versioning / Compatibility

Goal: bundles and host apps should be able to negotiate quickjs_ui protocol
compatibility.

Flutter reference: follow the same compatibility posture Flutter widgets use:
new props should have safe defaults, deprecated props should keep working until
a documented removal point, and unknown inputs should fail or ignore according
to an explicit policy.

Planned scope:

- Schema version and helper/runtime protocol version.
- Minimum required `quickjs_ui` version in bundle manifests.
- Deprecated prop tracking and migration notes.
- Unknown type / unknown prop policy.
- Compatibility tests using fixture bundles from older schema versions.

Boundary: versioning belongs to quickjs_ui package and bundle metadata. It
should not require changes to quickjs core except where core loading APIs need
to expose metadata.

## Custom Renderer Lifecycle

Goal: custom renderers should have a clear ownership model for native resources
such as video players, maps, camera previews, or platform views.

Flutter reference: model renderer-owned resources like `StatefulWidget` state:
create in init, update when schema changes, react to show/hide, and dispose
deterministically.

Planned scope:

- Controller creation and disposal.
- Visibility lifecycle: show/hide, pause/resume, dispose.
- Host resource ownership and cancellation.
- Integration with `QuickjsUiRenderContext.dispatchEvent()` for high-frequency
  callbacks.
- Recommended policies for progress, buffering, position, and sensor-like
  events.
- Custom renderers must not defer `context.dispatch()` with local post-frame
  callbacks; frame safety is handled by `QuickjsUiEventIngress` in
  `QuickjsUiView`.
- Imperative native actions from page state should use explicit props plus token
  counters (`seekToken`, `restartToken`, etc.) rather than hidden controller
  handles.

Boundary: custom renderers may own Flutter/Dart resources, but JS only observes
serializable state and events. Streams are used only for real data streams, not
as the default UI event channel.

## Resource / Media Model

Goal: resources should be resolved consistently across asset, file, network,
zip bundle, and custom media components.

Flutter reference: align resource categories with `AssetImage`, network image
loading, platform media controllers, and cache invalidation patterns. Use core
streams for large data streams, not for ordinary widget events.

Planned scope:

- Resource resolver API for asset/file/network references.
- Image cache and cache invalidation policy.
- Video/audio/custom media references.
- Permission, allowlist, checksum, and manifest integration.
- Clear rule for when core stream transport is appropriate, such as response
  bodies, subtitles, timed metadata, or long-running host data sources.

Boundary: media resources are declared in schema or manifest. JS does not get
direct file handles unless the host explicitly exposes a capability.

### 0.4.1 contract

Resource props may be either a legacy string or a serializable resource object:

```js
Image({
  src: {
    uri: 'https://example.com/avatar.png',
    kind: 'network',
    mimeType: 'image/png',
    sha256: '...',
    cacheKey: 'avatar-v1',
    headers: { Authorization: 'Bearer ...' }
  }
});
```

The normalized Dart model is `QuickjsUiResourceReference`. It classifies
resources as `asset`, `file`, `network`, `data`, or `custom`, validates allowed
schemes, and carries cache/checksum metadata for host policy and diagnostics.
Built-in `Image` resolves asset/file/network/data resources through this model.
Custom media renderers, such as `VideoPlayer`, should parse their `source` with
the same model and reject unsupported resource kinds with a structured `onError`
event where available.

Bundle manifests may include a `resources` table. This records resource metadata
alongside modules but does not grant JS new host capabilities. File system,
network, stream, or DRM access still requires explicit host policy/capability.

Core stream transport is reserved for large or long-lived data streams such as
response bodies, subtitles, timed metadata, or live host data sources. Ordinary
widget events and media progress remain renderer events via
`QuickjsUiEventIngress`.

## Conformance Tests

Goal: quickjs_ui should have stable compatibility coverage beyond feature-level
unit tests.

Flutter reference: keep renderer tests close to Flutter widget tests and
semantics tests; use golden tests only where visual regressions matter and can
remain deterministic.

Planned scope:

- Schema fixture tests.
- Renderer smoke and targeted golden tests.
- Lifecycle sequence tests for mount/show/hide/dispose and route events.
- Navigation sequence tests for push/replace/pop/result.
- Event backpressure tests for drop/throttle/debounce/pending limits.
- Bundle compatibility tests for manifests and older schema versions.

Boundary: conformance tests should stay deterministic and avoid depending on a
full example application unless the behavior truly needs Flutter app wiring.
