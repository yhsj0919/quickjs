# quickjs_ui 发布包格式

本文定义 0.5 阶段的 quickjs_ui 页面发布包格式。发布包用于生产分发、远程下发、缓存、校验和权限声明；开发期仍然可以直接从任意 `.mjs` 入口递归加载多文件页面。

## 基本原则

- 发布包的运行入口永远是包根目录下的 `main.mjs`。
- 发布包的描述文件永远是包根目录下的 `manifest.json`。
- `main.mjs` 是代码入口，`manifest.json` 只做包描述和校验，不作为运行入口。
- manifest 中所有相对路径都相对包根目录。
- 发布包模式必须校验 manifest；开发期多文件加载可以不使用 manifest。

## 目录结构

目录式发布包：

```text
profile/
├─ main.mjs
├─ manifest.json
├─ components/
│  └─ card.mjs
├─ assets/
│  └─ logo.png
└─ data/
   └─ options.json
```

zip 发布包：

```text
profile.quickjsui.zip
├─ main.mjs
├─ manifest.json
├─ components/card.mjs
├─ assets/logo.png
└─ data/options.json
```

网络发布包：

```text
https://example.com/quickjs-ui/profile/
├─ main.mjs
├─ manifest.json
├─ components/card.mjs
└─ assets/logo.png
```

## manifest.json

第一版 manifest 示例：

```json
{
  "schemaVersion": 1,
  "id": "com.example.profile",
  "name": "Profile",
  "version": "1.0.0",
  "entry": "main.mjs",
  "modules": {
    "main.mjs": {
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    },
    "components/card.mjs": {
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  },
  "resources": {
    "assets/logo.png": {
      "kind": "asset",
      "mimeType": "image/png",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef",
      "cacheKey": "logo-v1"
    },
    "data/options.json": {
      "kind": "data",
      "mimeType": "application/json",
      "sha256": "0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef"
    }
  },
  "permissions": [
    "quickjs_ui.host.navigation"
  ],
  "routes": {
    "main": {
      "entry": "main.mjs"
    }
  },
  "cache": {
    "mode": "versioned"
  },
  "metadata": {
    "description": "Profile demo page"
  }
}
```

## 字段说明

`schemaVersion`
: manifest 格式版本。它和 UI schema version 不是同一个概念。manifest 负责包格式，UI schema 负责 renderer 协议。

`id`
: 发布包稳定 ID。用于缓存、日志、权限策略和版本判断。

`version`
: 发布包版本。生产缓存可以使用 `id + version` 作为主键的一部分。

`entry`
: 第一版必须是 `"main.mjs"`。即使后续支持多 route，包根入口仍然固定为 `main.mjs`。

`modules`
: JS module 清单。所有会进入 QuickJS runtime 的本地 module 都应声明在这里。发布包模式下，实际 import 到未声明的本地 module 应拒绝加载。

`resources`
: 图片、JSON、主题、媒体等非 JS module 资源清单。资源可以按需懒加载，但 metadata 和 checksum 先登记。

`permissions`
: 页面希望使用的 host capability。manifest 只是声明，不自动授权；宿主仍然通过 permission policy 和 granted permissions 决定是否开放。

`routes`
: 包内页面路由。第一版可以只声明 `main`，多页面 bundle 后续再扩展。

`cache`
: 缓存策略。第一版建议先支持 `versioned`，后续再扩展 force refresh、conditional refresh、stale-while-revalidate。

`metadata`
: 人类可读的描述信息，不参与运行时安全判断。

## 加载模式

开发期多文件加载：

```text
入口可以是任意 .mjs
递归解析静态相对 import
不要求 manifest
适合 example、调试、快速验证
```

发布包加载：

```text
入口固定为包根 main.mjs
必须加载并校验包根 manifest.json
manifest.entry 必须是 main.mjs
modules/resources/permissions/cache 都来自 manifest
适合生产、远程下发、缓存和权限校验
```

建议 API 语义：

```dart
JsUiBundle.asset(path: 'assets/demo/pages/dev.mjs'); // 开发期多文件加载
JsUiBundle.file(path: 'E:/demo/pages/dev.mjs');      // 开发期多文件加载
JsUiBundle.network(url: devEntry);                   // 开发期多文件加载

JsUiBundle.packageAsset(root: 'assets/profile/');
JsUiBundle.packageFile(root: 'E:/packages/profile/');
JsUiBundle.packageNetwork(root: Uri.parse('https://example.com/profile/'));
JsUiBundle.archiveAsset(path: 'assets/profile.quickjsui.zip');
JsUiBundle.archiveFile(path: 'E:/packages/profile.quickjsui.zip');
```

如果需要保留可配置校验模式，可以在开发期入口加载上增加：

```dart
enum JsUiManifestMode {
  disabled,
  optional,
  required,
}
```

但发布包 API 本身应该始终等价于 `required`。

## manifest 生成

`manifest.json` 不建议手写，尤其是 `modules.*.sha256`。
开发期使用内置工具扫描包根目录并生成或更新 manifest：

```powershell
dart run lemon_js_ui:manifest --root assets/quickjs_ui/profile --id com.example.profile --version 1.0.0
```

在 CI 或发布前可以只检查不写入：

```powershell
dart run lemon_js_ui:manifest --root assets/quickjs_ui/profile --check
```

工具规则：

- 包根必须包含 `main.mjs`。
- 递归扫描包根下所有 `.mjs` 文件，写入 `modules`。
- 自动计算每个 module 的 `sha256`。
- 校验静态相对 `import/export from` 指向的模块存在于包根内。
- 保留已有 manifest 里的 `resources`、`permissions`、`routes`、`cache`、`metadata`。
- 不自动生成权限和资源声明，这些字段仍由开发者显式维护。

## 网络刷新策略

远程发布包加载支持三种运行时刷新语义：

- `conditional`：默认策略。命中内存缓存时发送 `If-None-Match`，服务端返回 `304` 时复用缓存内容。
- `force`：跳过 `If-None-Match`，强制重新请求；如果配置了 `cacheBuster`，会追加 `_quickjs_ui_cache_bust` 查询参数，适合开发期绕过代理或浏览器缓存。
- `staleWhileRevalidate`：命中内存缓存时立即返回旧内容，同时后台发起一次条件刷新。后台失败不会中断当前页面加载，只通过 network log 暴露。

当前阶段的缓存是 loader 内存级缓存，已经用于 ETag、checksum 校验和刷新策略。
如果需要跨 loader 或跨进程复用，可以传入 cache store：

```dart
final bundle = await JsUiBundle.packageNetwork(
  root: Uri.parse('https://example.com/profile/'),
  cacheStore: JsUiFileNetworkCacheStore(
    directory: Directory('quickjs_ui_cache'),
  ),
);
```

`JsUiFileNetworkCacheStore` 以 URL hash 为文件名保存 body、etag 和 cachedAt。
当前实现只做基础持久缓存，不做复杂淘汰；生产应用可以通过自定义
`JsUiNetworkCacheStore` 接入自己的缓存目录、容量限制和迁移策略。

## 校验规则

发布包 loader 至少应校验：

- 包根存在 `main.mjs` 和 `manifest.json`。
- `manifest.schemaVersion` 是当前支持版本。
- `manifest.id`、`manifest.version`、`manifest.entry` 非空。
- `manifest.entry == "main.mjs"`。
- `modules` 必须包含 `main.mjs`。
- 所有 module/resource 路径不能逃出包根。
- `sha256` 如果声明，必须是 64 位十六进制字符串，并且内容 hash 必须匹配。
- 实际静态 import 到的本地 module 必须在 `modules` 中声明。
- `permissions` 只作为声明，不能绕过宿主授权。

## 与 quickjs core 的边界

发布包格式属于 `quickjs_ui`，不进入 `quickjs` core。core 仍然只接收最终转换出的 `JsPlugin`、module source、manifest metadata 和 host features。

也就是说：

```text
发布包 root/zip/network
  -> quickjs_ui loader 校验 manifest/resources
  -> JsUiBundle
  -> JsPlugin
  -> quickjs core runtime
```

core 不需要知道目录、zip、网络缓存、图片资源或 UI schema 细节。
