# QuickJS Runtime / Context architecture

## Goal

The core runtime is moving from one `JSRuntime` plus one `JSContext` to one
long-lived `JSRuntime` containing multiple short-lived contexts. This allows
dynamic UI pages and plugins to load without rebuilding the native worker and
the complete QuickJS runtime.

Existing `Quickjs.create()`, `eval()`, `mount()` and `dispose()` remain the
compatibility API. Internally they use a default context.

## Ownership

```text
QuickjsRuntime
├─ native worker
├─ JSRuntime
├─ memory and stack limits
├─ interrupt handler
├─ shared Promise job queue
├─ runtime-scoped host capabilities
└─ QuickjsContext registry
   ├─ default context used by Quickjs
   ├─ dynamic page context
   └─ plugin context
```

Each `QuickjsContext` owns:

- its `JSContext` and global object;
- ES module instances and CommonJS cache;
- context-scoped callbacks and providers;
- timers, streams and pending async work;
- loaded plugin instances;
- source/module names associated with that context.

The runtime owns memory limits, cancellation infrastructure and the QuickJS
pending-job queue. A context must always be disposed before its runtime.

## Public API target

```dart
final runtime = await QuickjsRuntime.create(
  options: QuickjsRuntimeOptions(
    mounts: [applicationMount],
  ),
);

final context = await runtime.createContext(
  options: QuickjsContextOptions(
    mounts: [pageMount],
  ),
);

final plugin = await context.loadPlugin(dynamicPlugin);
final result = await plugin.call('mount', [props]);

await context.dispose();
await runtime.dispose();
```

The compatibility API remains:

```dart
final quickjs = await Quickjs.create();
final value = await quickjs.eval('1 + 2');
await quickjs.dispose();
```

## Dynamic UI loading

Page bundles are not runtime mounts. Resource loading and context creation can
run concurrently, after which the module graph is evaluated in the new context:

```text
load asset/network bundle ─┐
                           ├─ load modules into page context
create page context ───────┘
                                    ↓
                              mount state / commit
                                    ↓
                              Flutter first frame
```

This removes the current `Quickjs.mount()` runtime rebuild from page loading.

## Scope rules

Runtime-scoped mounts are immutable and shared by every context. Context mounts
are installed only for one context and disappear when it is disposed. Dynamic
page modules always belong to a context.

Mutable values must not cross context boundaries. Module source and optional
compiled bytecode may be cached by the runtime, but module instances, globals,
callbacks, handles and pending Promises remain context-local.

## Migration order

1. Add native context creation, registration and deterministic disposal.
2. Route native worker requests by `contextId`.
3. Move timer, callback, stream, async and module state onto contexts.
4. Add Dart `QuickjsRuntime` and `QuickjsContext` APIs.
5. Implement context-local plugin loading without `Quickjs.mount()`.
6. Make the existing `Quickjs` class delegate to a default context.
7. Switch `quickjs_ui` sessions to dynamic contexts.
8. Add native and web isolation, disposal and performance tests.

## Implementation status

- Native `QuickjsContext` creation, registration and deterministic disposal are
  implemented.
- Native worker commands can create, evaluate and dispose additional contexts
  by numeric `contextId`.
- Synchronous global evaluation is isolated between sibling contexts.
- ES module source tables, module instances and globals are isolated between
  sibling contexts.
- Public `QuickjsRuntime.create()` and `runtime.createContext()` lifecycle APIs
  are available for synchronous and ES-module evaluation. Native contexts share
  one worker/`JSRuntime`; other backends currently preserve semantics with an
  isolated runtime fallback.
- Host callbacks and their pending Promises are context-local. Late Dart
  responses are dropped after their owning context is disposed.
- Timers and async evaluation are context-local. The shared runtime event pump
  dispatches due timers against their owning `JSContext`, and context disposal
  releases all remaining intervals/timeouts.
- Dart async streams returned by host callbacks and JavaScript-to-Dart sinks
  are context-owned. Disposing a context cancels/closes its registered stream
  sessions without affecting siblings.
- `QuickjsContextOptions` installs mounts, providers, modules and plugins through
  the existing high-level `Quickjs` installer on a context adapter. Native
  callback ids are remapped across sibling facades, and no runtime rebuild is
  involved.
- Incremental `context.mount()` and `context.loadPlugin()` install directly in
  the existing context. Existing globals and sibling contexts remain intact;
  the compatibility `Quickjs.mount()` path still rebuilds its standalone
  runtime.
- `QuickjsUiRuntime` now owns one application-scoped core runtime and leases a
  fresh context to every `QuickjsUiSession`. Dynamic asset/file/network bundles
  remain page inputs; no page list is required during runtime initialization.

## Invariants

- Disposing one context must not stop sibling contexts.
- A disposed context cannot receive callback, stream or Promise results.
- A page cannot observe another page's globals or module state.
- Runtime disposal releases all contexts before `JS_FreeRuntime`.
- Context plugin loading never invokes runtime-rebuilding `mount()`.
