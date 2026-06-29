# QuickJS Plugin Manifest

`QuickjsPluginManifest` describes the callable contract for a JavaScript plugin.
It is intentionally small: the runtime uses it to validate and call exported
functions, while installation, updates, signatures, and remote catalogs stay in
the application layer.

## Fields

| Field | Required | Type | Meaning |
| --- | --- | --- | --- |
| `id` | yes | string | Plugin namespace. It must not contain `/`. Plugin modules must start with `${id}/`. |
| `version` | yes | string | Application-defined plugin version. The runtime does not compare versions. |
| `entry` | yes | string | Entry ES module specifier, for example `demo/main`. |
| `exports` | yes | string array | Callable function exports exposed to Dart. |
| `init` | no | string | Optional lifecycle export called by `initPlugin()` / `QuickjsPluginClient.init()`. |
| `dispose` | no | string | Optional lifecycle export called by `disposePlugin()` / `QuickjsPluginClient.dispose()`. |
| `permissions` | no | string array | Application-defined permission labels. The runtime does not grant capabilities from this field. |
| `metadata` | no | object | Application-defined metadata, for display or catalog usage. |
| `files` | zip only | object | Optional zip path map used by `QuickjsZipPlugin`. Keys are module specifiers, values are zip-relative file paths. |

## Minimal Example

```json
{
  "id": "demo",
  "version": "1.0.0",
  "entry": "demo/main",
  "exports": ["hello"],
  "init": "init",
  "dispose": "dispose",
  "permissions": ["storage"],
  "metadata": {
    "displayName": "Demo Plugin"
  }
}
```

## Zip Packages

`QuickjsZipPlugin.asset()` and `QuickjsZipPlugin.bytes()` look for
`quickjs-plugin.json` or `manifest.json`. With this layout:

```text
manifest.json
main.js
modules/helper.js
```

and this entry:

```json
{
  "id": "demo",
  "version": "1.0.0",
  "entry": "demo/main",
  "exports": ["hello"]
}
```

`main.js` maps to `demo/main`, and `modules/helper.js` maps to
`demo/modules/helper.js`, so relative imports like `./modules/helper.js` work.

Use `files` when zip paths do not match the default mapping:

```json
{
  "id": "demo",
  "version": "1.0.0",
  "entry": "demo/main",
  "exports": ["hello"],
  "files": {
    "demo/main": "src/main.mjs",
    "demo/lib/helper.mjs": "src/helper.mjs"
  }
}
```

## Runtime Boundaries

- Manifest `permissions` are labels only. Host capabilities still require
  explicit `QuickjsHostMount` / provider configuration.
- Manifest `version` is not an update policy. The application decides which
  plugin version to mount.
- File system scanning, installation state, hash/signature verification, and
  update sources are not runtime responsibilities.
