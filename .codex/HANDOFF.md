# Agent Handoff

## Current State

- The working tree contains uncommitted work spanning 0.6.0 through 0.9.0. Preserve it and do not assume a clean checkout.
- Public imports still enter through `package:quickjs/quickjs.dart`, while implementation files are now grouped under:
  - `lib/src/backend/`
  - `lib/src/bridge/`
  - `lib/src/diagnostics/`
  - `lib/src/module/`
  - `lib/src/runtime/`
  - `lib/src/native/` and `lib/src/web/`
- 0.6.0 module support is complete: ES modules, static imports, relative resolution, runtime module cache, asset loading, and minimal CommonJS.
- 0.7.0 is complete except for JS-GC-driven Dart instance finalization:
  - function handles with call, callAsync, cancel, timeout, and explicit disposal
  - Dart object proxies with properties, accessors, methods, and explicit disposal
  - Dart class/instance bindings with runtime-owned instance tables
- 0.8.0 debug support is implemented:
  - console log/warn/error forwarding
  - source names and structured JS exceptions
  - source-map registration and stack remapping
  - `debugInspect()` and `debugEvaluateValue()` prototypes
- 0.9.0 host capabilities are in active development:
  - `QuickjsHostScript`, `QuickjsHostModule`, and async `QuickjsHostProvider`
  - `QuickjsHostProviderContext` signals per-call cancellation during stop, dispose, and runtime rebuild
  - `QuickjsHostProviderImplementation` declares Dart/platform/Web implementation metadata, exposed by `debugInspect().providerDetails`
  - initialization mounts through `QuickjsRuntimeOptions.mounts`
  - direct runtime configuration uses `environmentPatches`, `modules`, and `providers`; the old `hostScripts` / `hostModules` / `hostProviders` names are removed
  - runtime mounts through `Quickjs.mount()`; the first implementation rebuilds the runtime atomically
  - `QuickjsHostMountConflictPolicy.replace` atomically replaces a same-name runtime mount and restores the old mount/runtime if installation fails
  - `QuickjsHostScript.globals` declares installed globals so duplicate globals are rejected before a mount rebuild
  - `QuickjsHostMount.web()`, `.essential()`, and `.node()` presets
  - `QuickjsWebCryptoMount()` provides randomUUID, getRandomValues, and provider-backed subtle.digest
  - the old `QuickjsHostEnvironment` / `hostEnvironments` API has been removed
- Example coverage includes host modules, Web host globals, Web Crypto, bulk host mounts,
  and Fetch (`QuickjsFetchMount` with POST, FormData, XHR, redirects, and origin policy).
- `docs/npm_bundling.md` and `example/npm_bundle` document and test the supported npm boundary: esbuild produces a self-contained ESM Flutter asset that is registered through `QuickjsRuntimeOptions.modules`; the dedicated `NPM Bundle` page shows only asset loading, module registration, and one exported method call.
- `QuickjsFetchMount` is an opt-in mount with an exact origin allowlist, timeout/body limits,
  and configurable redirect following with per-hop allowlist checks; native uses HttpClient
  and Web uses browser fetch; the JS wrapper exposes Fetch APIs plus an XHR compatibility
  layer (`onload` / `onerror` properties; no `addEventListener`).

## Important Files

- `ROADMAP.md`
- `lib/quickjs.dart`
- `lib/src/runtime/quickjs.dart`
- `lib/src/runtime/quickjs_runtime_options.dart`
- `lib/src/runtime/quickjs_runtime_base.dart`
- `lib/src/module/quickjs_asset_module_loader.dart`
- `lib/src/module/quickjs_web_crypto_mount.dart`
- `lib/src/native/quickjs_native_worker.dart`
- `lib/src/web/quickjs_web_backend.dart`
- `test/quickjs_consistency_test.dart`
- `example/lib/example_pages.dart`
- `example/lib/pages/host_modules_page.dart`
- `example/lib/pages/host_mounts_page.dart`
- `example/lib/pages/web_host_environment_page.dart`
- `example/lib/pages/crypto_random_uuid_page.dart`
- `example/lib/pages/fetch_page.dart`
- `example/test/widget_test.dart`
- `test/quickjs_fetch_mount_test.dart`

## Commands To Verify

Keep routine verification targeted and keep command output out of the agent context. The
wrapper stores full output under `build/verification-logs` and prints only pass/fail timing
or the tail of a failed log:

```powershell
.\tool\verify.cmd -TestPath test\quickjs_consistency_test.dart -PlainName "test name"
.\tool\verify.cmd -TestPath test\quickjs_consistency_test.dart -PlainName "test name" -Web
```

Run the complete gate once after the implementation is stable:

```powershell
.\tool\verify.cmd -Mode full
```

Only run `flutter build windows --debug` when native or Windows integration code changed.
The Windows build may still emit existing C4819 encoding warnings for native files. Avoid
re-running a passing full gate unless relevant files changed.

## Next Recommended Step

Fetch (`QuickjsFetchMount`) is wrapped up for 0.9.0. Continue with the remaining 0.9.0
lifecycle and conflict semantics before starting the 0.10.0 plugin API:

1. Close foundational gaps from 0.3.0 / test strategy: handle ownership rules, OOM/stack
   overflow tests, example smoke automation.
2. Decide whether JS/worker-local providers belong in 0.9.0 or should remain deferred.
3. Decide whether Node crypto belongs in 0.9.0 or should remain deferred.
4. Run the full native/Web and example test suites before declaring the 0.9.0 slice complete.

## Constraints To Preserve

- Keep `Quickjs` as the single public system entry point.
- Do not expose raw native `JSValue`, `JSRuntime`, or `JSContext` values.
- Runtime-owned handles, callbacks, providers, module caches, and class instances must not cross runtimes.
- Keep native and Web request/response/stop/dispose semantics aligned and covered by consistency tests.
- Host/platform capabilities remain opt-in. Core defaults must not expose network, filesystem, browser, or Node APIs.
- Cross-isolate Dart/Flutter providers are asynchronous; do not present them as synchronous JavaScript APIs.
- Runtime mounting currently rebuilds the runtime, so existing globals, module cache, manual callbacks, and handles are not retained.
- Example pages create and dispose their own `Quickjs` instances.

## Startup Procedure

1. Read this file and the relevant `ROADMAP.md` section.
2. Run `git status --short` before editing.
3. Inspect only the files related to the selected roadmap item; avoid broad rewrites in the dirty worktree.
4. Keep public exports in `lib/quickjs.dart` and internal imports within the new directory structure.
