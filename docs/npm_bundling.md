# npm dependency bundling

QuickJS runtimes do not resolve `node_modules`, `package.json` exports, or the
full Node module algorithm. Bundle npm dependencies before packaging the
Flutter application. The runtime then receives ordinary JavaScript source with
no unresolved npm specifiers.

## Recommended boundary

- Use esbuild, Rollup, or another application build tool outside the runtime.
- Prefer one self-contained ESM file per public plugin or capability entry.
- Use `platform=browser` as the default compatibility check. Packages that
  require Node built-ins fail at build time unless the application supplies an
  explicit polyfill or marks the dependency external.
- Do not mark npm dependencies external unless the same specifiers are
  registered explicitly through `QuickjsRuntimeOptions.modules`.
- Keep filesystem, network, database, and platform APIs outside the bundle and
  expose them through opt-in host providers or mounts.

## Included esbuild example

The runnable example is in `example/npm_bundle`. It bundles the CommonJS npm
package `fast-deep-equal` behind a small ESM API.

```powershell
cd example/npm_bundle
npm ci
npm run build
```

The build command is equivalent to:

```powershell
esbuild src/index.js `
  --bundle `
  --format=esm `
  --platform=browser `
  --target=es2020 `
  --outfile=../assets/js/npm_bundle.mjs
```

`--bundle` follows npm imports at build time. `--format=esm` preserves the
entry exports for `QuickjsHostModule.esModule`. `--platform=browser` prevents
accidental reliance on Node runtime globals and built-in modules.

## Registering the generated asset

Declare the generated file in the Flutter application's `pubspec.yaml`:

```yaml
flutter:
  assets:
    - assets/js/npm_bundle.mjs
```

Load the source before creating the runtime and register it under an
application-owned specifier:

```dart
final source = await rootBundle.loadString('assets/js/npm_bundle.mjs');
final engine = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    modules: <QuickjsHostModule>[
      QuickjsHostModule.esModule(
        specifier: 'example/npm-bundle',
        source: source,
      ),
    ],
  ),
);

await engine.evalModule('''
import { compareValues } from 'example/npm-bundle';
globalThis.bundleResult = compareValues(
  { answer: 42 },
  { answer: 42 },
);
''', name: 'app/use-npm-bundle.mjs');
```

The specifier belongs to the application. It does not need to match the npm
package name and should be namespaced to avoid collisions.

## IIFE alternative

For a script that intentionally installs one global, build with
`--format=iife --global-name=YourNamespace` and execute the result with
`Quickjs.eval()`. Prefer ESM for reusable libraries because exports remain
explicit and do not pollute `globalThis`.

## Unsupported or risky packages

A successful npm install does not imply QuickJS compatibility. Review bundles
that depend on:

- Node built-ins such as `fs`, `net`, `tls`, `child_process`, or native addons;
- dynamic `require()` calls that the bundler cannot resolve statically;
- browser DOM APIs that are not supplied by the selected host mounts;
- `eval`, generated code, WebAssembly, or large startup payloads;
- environment variables or package files expected to exist at runtime.

Treat third-party bundles as untrusted application code. Apply runtime memory
and timeout limits, expose only required host capabilities, and rebuild the
runtime when replacing an already loaded module.

## References

- [esbuild bundling](https://esbuild.github.io/api/#bundle)
- [esbuild output formats](https://esbuild.github.io/api/#format)
- [esbuild platform behavior](https://esbuild.github.io/api/#platform)
