# quickjs_ui cross-cutting modules

This document tracks large quickjs_ui concerns that cut across schema, renderer,
custom components, navigation, resource loading, and tooling. These are not
single-widget features.

## Design Rule

For each cross-cutting module, start from Flutter's native model and expose only
the serializable subset that fits quickjs_ui. Do not copy Web/DOM concepts when
Flutter already has a stronger primitive.

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
