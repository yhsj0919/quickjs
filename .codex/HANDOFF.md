# Agent Handoff

## Current State

- `ROADMAP.md` 0.6.0 `module 与 asset` is complete.
- ES module support now covers:
  - `evalModule(source, name: ...)`
  - static import dependency loading
  - relative path resolution
  - runtime-scoped imported module cache
  - `QuickjsRuntimeOptions.moduleLoader`
  - Flutter `AssetBundle` helper via `quickjsAssetModuleLoader()`
  - package asset and web asset paths
- Minimal CommonJS support is complete:
  - `Quickjs.evalCommonJs()` / `evaluateCommonJs()`
  - `require()`
  - `module.exports`
  - `exports`
  - relative path resolution
  - runtime-scoped CommonJS module cache
- The working tree may contain the uncommitted 0.6.0 changes. Do not assume a clean tree.

## Important Files

- `ROADMAP.md`
- `lib/src/quickjs.dart`
- `lib/src/quickjs_runtime_options.dart`
- `lib/src/quickjs_asset_module_loader.dart`
- `lib/src/quickjs_runtime_base.dart`
- `lib/src/native/quickjs_native_worker.dart`
- `lib/src/web/quickjs_web_backend.dart`
- `lib/src/web/quickjs_web_loader.dart`
- `assets/web/quickjs_bridge.mjs`
- `assets/web/quickjs_web.js`
- `assets/web/quickjs_web_worker.js`
- `native/quickjs_bridge.c`
- `native/quickjs_bridge.h`
- `test/quickjs_consistency_test.dart`
- `example/lib/pages/module_eval_page.dart`
- `example/lib/example_pages.dart`
- `example/test/widget_test.dart`

## Verified Commands

Run from `E:\quickjs` unless noted.

```powershell
flutter analyze
flutter test
flutter test test\quickjs_consistency_test.dart
flutter test test\quickjs_consistency_test.dart -d chrome
cd example
flutter test
flutter build windows --debug
```

Notes:

- The Windows build succeeded after native bridge changes.
- Windows build may still show existing C4819 encoding warnings for native files.

## Next Recommended Step

Start 0.7.0 with the smallest JS function handle slice:

1. Add public `evaluateHandle()` or equivalent on `Quickjs`.
2. Return a `QuickjsHandle` / function-handle object bound to its owning `Quickjs` runtime.
3. Implement `handle.call(args, {timeout})`.
4. Reuse the existing worker request / response queue model.
5. Support timeout and closed-runtime errors.
6. Add ownership rules: handle calls after runtime dispose return `JsRuntimeClosedException`; cross-runtime use should be impossible or explicitly rejected.
7. Add native/web consistency tests before expanding to object proxy or class binding.

Do not start with Dart object proxy or class binding. Those expand the API surface and should wait until function handles are stable.

## Constraints To Preserve

- Public API should continue to enter through `Quickjs`.
- Do not expose raw native `JSValue`, `JSRuntime`, or `JSContext`.
- Handles must be runtime-owned.
- Worker backends should keep request / response / stop / dispose semantics.
- Native and web behavior should stay covered by `test/quickjs_consistency_test.dart`.
- Example pages should create and dispose their own `Quickjs` instances.

## Suggested Startup Procedure For Next Session

1. Read this file.
2. Read only `ROADMAP.md`.
3. Check `git status --short`.
4. For 0.7.0 function handles, read:
   - `lib/src/quickjs.dart`
   - `lib/src/quickjs_runtime_base.dart`
   - `lib/src/native/quickjs_native_worker.dart`
   - `lib/src/web/quickjs_web_backend.dart`
   - `assets/web/quickjs_bridge.mjs`
   - `native/quickjs_bridge.c`
   - `test/quickjs_consistency_test.dart`
5. Avoid `rg --files` or broad scans unless the targeted files contradict this handoff.
