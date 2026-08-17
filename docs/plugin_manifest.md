# QuickJS 插件清单

`JsPluginManifest` 描述 JavaScript 插件的可调用契约。它刻意保持精简：
运行时只用它校验和调用导出函数；安装、更新、签名及远程目录均由应用层负责。

## 字段

| 字段 | 必填 | 类型 | 含义 |
| --- | --- | --- | --- |
| `id` | 是 | string | 插件命名空间，不得包含 `/`；插件模块必须以 `${id}/` 开头。 |
| `version` | 是 | string | 应用定义的插件版本；运行时不比较版本。 |
| `entry` | 是 | string | ES 模块入口标识，例如 `demo/main`。 |
| `exports` | 是 | string array | 暴露给 Dart 调用的导出函数。 |
| `init` | 否 | string | 可选生命周期导出，由 `initPlugin()` / `JsPluginClient.init()` 调用。 |
| `dispose` | 否 | string | 可选生命周期导出，由 `disposePlugin()` / `JsPluginClient.dispose()` 调用。 |
| `permissions` | 否 | string array | 应用定义的权限标签；运行时不会依据该字段自动授权能力。 |
| `metadata` | 否 | object | 应用定义的展示或目录元数据。 |
| `files` | 仅 zip | object | `JsZipPlugin` 使用的可选路径映射；键为模块标识，值为 zip 内相对路径。 |

## 最小示例

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

## Zip 发布包

`JsZipPlugin.asset()` 和 `JsZipPlugin.bytes()` 会查找
`manifest.json` 或 `manifest.json`。假设目录结构如下：

```text
manifest.json
main.js
modules/helper.js
```

清单入口如下：

```json
{
  "id": "demo",
  "version": "1.0.0",
  "entry": "demo/main",
  "exports": ["hello"]
}
```

`main.js` 映射为 `demo/main`，`modules/helper.js` 映射为
`demo/modules/helper.js`，因此 `./modules/helper.js` 等相对导入可以正常工作。

zip 路径不符合默认映射时，使用 `files` 显式声明：

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

## 运行时边界

- 清单中的 `permissions` 只是标签；宿主能力仍须显式配置
  `JsFeatures` / method。
- 清单中的 `version` 不代表更新策略；由应用决定挂载哪个插件版本。
- 文件系统扫描、安装状态、哈希/签名校验和更新源均不属于运行时职责。
