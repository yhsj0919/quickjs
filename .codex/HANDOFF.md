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
- 0.7.0 function handle slice is implemented:
  - `Quickjs.evaluateHandle()` / `evalHandle()`
  - `QuickjsFunctionHandle.call(args, timeout: ...)`
  - `QuickjsFunctionHandle.callAsync(args, timeout: ...)`
  - `QuickjsFunctionHandle.dispose()`
  - `QuickjsFunctionHandle.cancel()`
  - runtime-owned hidden JS function registry
  - `callAsync` timeout docs: timeout covers Promise pending; synchronous work before returning a Promise should use `call`
  - native/web consistency tests cover call, callAsync Promise resolve/reject, structured args, non-function rejection, isolation, timeout, cancel, handle dispose, and runtime dispose errors
- 0.7.0 object proxy minimal slice is implemented:
  - `QuickjsObjectProxy`
  - `Quickjs.bindObject(name, proxy)`
  - `QuickjsObjectHandle.dispose()`
  - readonly data properties
  - methods routed through the existing Promise callback bridge
  - object handle dispose deletes the JS global proxy, hidden method callback globals, and runtime-level callback registry entries
  - native/web consistency tests cover readonly properties, method calls, method errors, invalid descriptors, object handle dispose, leaked method references after dispose, dispose-after-runtime-dispose, and bind-after-dispose errors
  - example page registered as `对象代理`
- The working tree may contain uncommitted 0.6.0 and 0.7.0 changes. Do not assume a clean tree.

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
- `example/lib/pages/function_handle_page.dart`
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

Continue 0.7.0 with the next Dart object proxy slice:

1. Add dynamic getter / setter descriptors if the public API shape is clear.
2. Consider proxy access after handle dispose error semantics if a stronger error than missing global is desired.
3. Keep using explicit descriptors rather than arbitrary Dart reflection.
4. Add native/web consistency tests before expanding to constructors or class binding.

Do not start with Dart class binding. That expands the API surface and should wait until object proxy semantics are stable.

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
