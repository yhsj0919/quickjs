# Canvas and animation contract

This document defines the first experimental contract for Canvas, retained
scenes, widget effects, and control-state transitions. The APIs remain under
the `quickjs_ui` package's `0.1.x` experimental versioning policy: compatible
additions may land in a patch release, while incompatible schema changes must
be called out in the changelog and guarded by schema/runtime compatibility
metadata.

## Execution model

JavaScript records serializable values once. Flutter owns painting, VSync,
interpolation, hit testing, and resource disposal. An animation must not call
QuickJS once per frame. `onFrame` is an optional, throttled observation event;
it is not the animation driver.

`staticDraw`/`staticCommands` are cached as a Flutter `ui.Picture` and cannot
contain animated values. `draw`/`commands` are evaluated by the painter on each
local frame. A Canvas is isolated by a `RepaintBoundary`.

## Canvas lifecycle

- Give a stateful or retained Canvas a stable node `key`.
- Without `sceneKey`, the current command lists belong to that Canvas node.
- The first use of a `sceneKey` must provide commands. Later uses may omit them
  and resolve the retained page-scoped scene.
- Registering the same `sceneKey` with commands replaces the retained scene.
- Retained scenes are bounded to 32 entries per renderer; the oldest entry is
  evicted first. All scenes are cleared when the renderer is disposed.
- `playToken` changing, command content changing, or `reverse` changing starts
  a new local playback generation.
- `paused: true` stops ticking and preserves elapsed time. Resuming continues
  from that time.
- `reverse` is supported only for finite timelines. Reversing a repeating or
  epoch-based animation is rejected.
- `onAnimationEnd` is emitted once for each completed finite playback
  generation, after its final frame has been painted. Repeating and
  epoch-based animations do not complete.

Canvas dimensions use logical Flutter pixels. Flutter applies the device pixel
ratio while rasterizing; schema authors should not multiply coordinates by the
device pixel ratio.

## Commands and limits

The first contract includes rectangles, rounded rectangles, circles, arcs,
lines, paths, text, snapshot images, particle grids, save/restore, translate,
rotate, scale, rectangular clipping, paint opacity, stroke/fill, and supported
blend modes. It intentionally does not promise complete browser Canvas 2D
compatibility.

Safety limits are part of the protocol:

- at most 10,000 commands in each submitted command list;
- at most 20,000 path segments in one submitted command list;
- at most 128 nested `save()` calls, with balanced `save()`/`restore()`;
- `frameIntervalMs` must be between 16 and 60,000 ms;
- unknown commands, invalid colors, non-finite numbers, and missing retained
  scenes are rejected as schema/render errors.

Prefer one specialized command, such as `drawSnapshotParticleGrid`, over
thousands of generic commands. Put unchanging content in `staticDraw`. Use a
retained `sceneKey` when a large display list must be replayed immediately.

## Snapshots and images

`SnapshotBoundary` captures a child subtree into an opaque, immutable,
page-scoped handle. Pixel bytes never cross the JavaScript bridge. Handles are
valid only in the renderer that created them and must be passed through Canvas
`resources` slots for retained scenes. Snapshot storage is bounded by entry and
pixel limits, evicts old unreferenced entries, and is disposed with the
renderer.

Capture before an interaction when playback must begin without capture delay.
Do not persist snapshot handles in a server payload, application database, or
another page session.

## Widget and control animations

Universal effects (`opacity`, `transform`, `clipRadius`, `blur`,
`backdropBlur`, and `colorFilter`) use the same `animate()` number descriptor
and playback controls as Canvas. A stable node `key` is required when playback
state must survive schema rebuilds. Finite effects emit `onAnimationEnd` once
per playback generation.

Control-state transitions are separate: `stateTransition` interpolates between
resolved `normal`, `hovered`, `focused`, `selected`, `pressed`, and `disabled`
styles. `durationMs: 0` or `stateTransition: false` applies the new state
immediately. Flutter's reduced-motion accessibility setting also disables
control-state transitions. Product code should provide an equivalent static
end state and must not make meaning depend on motion alone.

## Retained particle flow

`ParticleFlow` is the preferred carrier for a large set of widget-backed
particles that share the same vertical looping motion. JavaScript provides
serializable trajectories and retained child widgets once; Flutter advances
all particles from one clock and repaints one `Flow` layer without rebuilding
each child on every frame.

- `width` and `height` are required logical-pixel bounds.
- `particles.length` must equal `children.length`.
- Each particle defines `fromX`, `toX`, `fromY`, `toY`, and `durationMs`.
  Optional start/end pairs interpolate opacity, scale, and rotation; `phaseMs`
  offsets its loop without creating another clock.
- `frameIntervalMs` limits paint frequency. Omitting it follows display VSync.
- `paused` preserves elapsed time; changing `playToken` restarts all particles
  as one generation.

Use this component when the visual must remain a normal Flutter widget (for
example decoded image sprites). Prefer Canvas for primitive-only particles.
Do not create one independently ticking effect per particle: that multiplies
listeners, rebuilds, and layer work even when all particles share one timeline.

## Performance acceptance

### Adaptive effect quality

The host can keep the existing full-quality behavior or opt into local,
frame-timing-driven degradation without rebuilding the JavaScript page:

```dart
final performance = QuickjsUiPerformanceController(
  mode: QuickjsUiPerformanceMode.auto,
);
final renderer = QuickjsUiRenderer(
  onEvent: handleEvent,
  performanceController: performance,
);

// Dispose both when the owning page/session ends.
renderer.dispose();
performance.dispose();
```

`QuickjsUiView` creates an auto controller by default, reads
`View.of(context).display.refreshRate`, and derives the budget as one refresh
interval (8.33 ms at 120 Hz, 11.11 ms at 90 Hz, or 16.67 ms at 60 Hz). Passing
`targetFrameBudget` explicitly overrides this derivation. Direct
`QuickjsUiRenderer` usage keeps the compatibility default of `high`; inject a
controller to opt into automatic sampling.

The default mode is `high`, which preserves compatibility and performs no
global frame sampling. `auto` starts at `high`, degrades after 24 consecutive
slow frames, and upgrades only after 240 stable frames. The asymmetric windows
avoid quality oscillation. Hosts may instead force `high`, `balanced`, `low`,
or `off`.

Quality changes stay inside Flutter:

- `high`: complete effects and up to 4,096 snapshot particle fragments;
- `balanced`: blur is capped at 12 and particle grids at about 1,024 fragments;
- `low`: backdrop blur and color filters are removed, blur is capped at 4,
  and particle grids are aggregated to about 256 fragments;
- `off`: effect animations resolve to their finite end state, filters are
  removed, Canvas tickers stop, and snapshot particle transitions draw the
  target image directly.

The controller compares the larger of Flutter's build and raster durations
with the configured budget. Device-name heuristics are intentionally not the
primary signal: thermal throttling and page complexity can change during a
session. The host owns an injected controller and must dispose it after all
renderers using it have been disposed.

`MediaQuery.disableAnimations` temporarily forces the effective quality to
`off` for Canvas and universal effects, without discarding the prior adaptive
quality. When the system setting is removed, playback returns to that quality.
The Inspector performance tab and exported page snapshot expose refresh rate,
budget, current mode/quality, reduced-motion state, build/raster P50/P90/P99,
consecutive slow/stable frame counts, and the latest transition reason.
They also expose current Canvas/animated-Canvas counts, command and Path
segment counts, retained scenes, snapshot count/pixels, requested versus
effective particle fragments, repaint count, Dart painter CPU P50/P90/P99,
rejected command count/reason, and the number of clamped or disabled blur,
backdrop-blur, color-filter, and ticker effects. Painter CPU duration measures
display-list processing on the Dart/UI side; use Flutter's raster timing for
GPU cost.

The repository widget benchmarks are regression indicators, not GPU or device
benchmarks. Before declaring a release production-ready, run the example in
Flutter profile mode on a representative low-end 60 Hz Android device and a
120 Hz target device. Record UI/raster frame times and memory for:

1. 1,000, 5,000, and 10,000 animated primitives;
2. multiple visible Canvas nodes;
3. large snapshot capture and particle playback;
4. repeated page enter/exit and background/foreground cycles;
5. 40 mixed animated controls.

Acceptance requires no sustained frame budget misses (16.67 ms at 60 Hz or
8.33 ms at 120 Hz), no ticker after page disposal, and no monotonic retained
scene/snapshot memory growth after repeated navigation. Use DevTools' Frame
Analysis and Memory views; widget-test stopwatch results must not be reported
as device raster performance.

The example app's final Particle FX entry, **Performance Lab · 自适应效果质量**,
combines 1,000/5,000/10,000 locally animated Canvas primitives, universal
filters, widget animation, and a Snapshot particle transition. Its Flutter
host owns the performance controller, offers manual `auto/high/balanced/low/off`
selection, and displays the live serialized performance snapshot without
sending frame statistics through JavaScript.

Use **开始采样** to exclude a two-second warm-up, then stop and copy a versioned
JSON report. Reports include frame counts, slow/severe frames, build/raster
P50/P90/P99/max, quality transitions and time at each quality, display/build
metadata, and the current Canvas/effect scene metrics. Programmatic hosts can
call `startSession(...)` and `stopSession()`; fixed quality modes are sampled as
well, enabling repeatable `high` versus `low` Profile-mode A/B comparisons.
`toJson()` is platform-neutral so the host can save, upload, or copy the result.

Useful local regression commands:

```bash
.\tool\verify.cmd -Mode ui
.\tool\verify.cmd -Mode ui -Benchmark
```

Run these commands from the repository root. The script uses
`QUICKJS_DLL_PATH` when configured, otherwise it locates an existing Windows
example build and builds the debug example when necessary. Pass
`-SkipNativeBuild` to fail instead of triggering that build.
