# quickjs_extensions

`quickjs_extensions` 是 `lemon_js` 与 `lemon_js_ui` 之上的统一插件组合层。一个安装单元可以只提供 Core 数据能力、只提供 JSUI 页面，或同时提供两者。它不会引入新的 JavaScript 引擎或 UI 渲染协议。

## 能力

- `QuickjsExtension.js(...)`：纯 Core 插件。
- `QuickjsExtension.ui(...)`：纯 JSUI 插件。
- `QuickjsExtension.hybrid(...)`：Core 与 JSUI 混合插件。
- `QuickjsExtension.load(...)`：根据统一包和 manifest 自动判定插件形态。
- `QuickjsExtensionSession`：懒加载并常驻 Core runtime，页面销毁不影响 Session。
- `quickjs_extensions/storage`：按插件 ID 隔离的 KV 模块。
- `quickjs_extensions/plugin_service`：JSUI 调用同 Session Core 的受限 bridge。
- `QuickjsExtensionRegistry`：按 contract 或 flow 查询已安装插件。
- `QuickjsExtensionView.route(...)`：打开 manifest 声明的 JSUI route。
- `QuickjsExtensionFlowRunner`：处理 `interactionRequired` 并限制为一次重试。

## 安装

```yaml
dependencies:
  quickjs_extensions: ^0.1.0-dev.1
```

```dart
import 'package:quickjs_extensions/quickjs_extensions.dart';
```

## 统一 manifest

```json
{
  "schemaVersion": 2,
  "id": "site.example",
  "name": "示例站点",
  "description": "提供示例站点的数据和认证能力",
  "version": "1.0.0",
  "versionCode": 10000,
  "compatibilityCode": "lemon-content-source-v1",
  "service": {
    "entry": "service/main.mjs",
    "contract": "content-source/v1",
    "publicExports": ["getHome", "search"],
    "uiExports": ["submitLogin"]
  },
  "ui": {
    "routes": {
      "authentication": {
        "entry": "ui/authentication.mjs",
        "title": "登录"
      }
    }
  },
  "flows": {
    "authentication": {"route": "authentication"}
  },
  "permissions": ["network", "storage"]
}
```

manifest 中的模块路径是安装包内的相对路径。`quickjs_extensions` 会在加载 Core 时自动添加插件 ID 命名空间。

## 加载与安装

### 从不同来源加载

目录形式以 `manifest.json` 为入口，Core 和 JSUI 的相对导入会被递归收集：

```dart
final assetPackage = await QuickjsExtensionPackage.asset(
  manifestAsset: 'assets/extensions/site/manifest.json',
);
final filePackage = await QuickjsExtensionPackage.file(
  manifestPath: '/plugins/site/manifest.json',
);
final networkPackage = await QuickjsExtensionPackage.network(
  manifestUrl: Uri.parse('https://example.com/site/manifest.json'),
);
```

生产分发可使用一个包含 `manifest.json`、Core 和 JSUI 模块的 ZIP：

```dart
final package = await QuickjsExtensionPackage.assetZip(
  assetKey: 'assets/plugins/site.zip',
);
// 也支持 fileZip(...)、networkZip(...) 和 zipBytes(...)。
```

无论来源如何，加载后都归一化为同一个 `QuickjsExtensionPackage`。

## 统一插件管理

应用启动时创建 Manager。桌面和移动端可以使用文件 Store 持久化安装记录与插件源码：

```dart
final manager = QuickjsExtensionManager(
  store: QuickjsExtensionFileStore(directoryPath: extensionDirectory),
  storage: persistentExtensionKvStorage,
  compatibilityRegistry: QuickjsExtensionCompatibilityRegistry([
    QuickjsExtensionCompatibilityPolicy(
      compatibilityCode: 'lemon-content-source-v1',
      requiredPublicExports: const {'getPluginInfo'},
      optionalPublicExports: const {'getHome', 'search', 'getDetail'},
    ),
  ]),
  uiPluginsResolver: resolveThirdPartyUiPlugins,
);

await manager.restore();
```

`restore()` 只恢复安装项、Registry 和 Session，Core runtime 保持懒加载。第三方
`QuickjsUiPlugin` 包含宿主原生对象，不能写入 JSON，因此由 `uiPluginsResolver` 按插件
ID 重新注入。Web 平台应实现 `QuickjsExtensionStore`，接入 IndexedDB 或其他持久化方案。

```dart
await manager.installAsset(
  manifestAsset: 'assets/extensions/site/manifest.json',
  grantedPermissions: const {'network', 'storage'},
);
await manager.update('site.example', newPackage);
await manager.disable('site.example');
await manager.enable('site.example');
await manager.uninstall('site.example', clearStorage: false);

final installed = manager.extensions;
```

插件可以只实现部分可选方法，但必须实现策略中的必需方法。内部辅助函数以及没有写入
manifest 的额外导出不参与校验。可以使用 `manager.supports(id, method)` 或
`manager.servicesForMethod(contract, method)` 查询能力。

按 ID 调用指定插件：

```dart
final result = await manager.call('site.example', 'getHome');
```

也可以按 contract 调用。存在多个实现时必须指定 `pluginId`，不会随机选择：

```dart
final result = await manager.callContract(
  'content-source/v1',
  'getHome',
  pluginId: 'site.example',
);
```

### 旧 Core 与 JSUI 包

统一 Extension 必须携带 manifest，不接受裸文件。旧 Core 和 JSUI 可以显式指定格式，
从裸 `main.mjs` 递归加载相对模块：

```dart
await manager.installAssetEntry(
  entryAsset: 'assets/legacy/main.mjs',
  format: QuickjsExtensionPackageFormat.core,
  coreAdapter: QuickjsCorePackageAdapter(
    id: 'legacy.source',
    name: 'Legacy source',
    description: 'Legacy Core plugin',
    version: '1.0.0',
    versionCode: 10000,
    compatibilityCode: 'lemon-content-source-v1',
    contract: 'content-source/v1',
    publicExports: const ['getPluginInfo', 'search'],
  ),
);
```

同样支持 `installFileEntry`、`installNetworkEntry`，以及在 ZIP 安装方法中指定
`QuickjsExtensionPackageFormat.core/ui`。默认格式始终为 `extension`。

### 更新

Manager 使用 `versionCode` 比较版本，默认拒绝重复版本和降级：

```dart
final check = await manager.checkForUpdate('site.example');
if (check.available) {
  await manager.downloadAndUpdate('site.example', check.info);
}
```

更新描述需要提供 ID、展示版本、数字版本、兼容码和 HTTPS 下载地址。下载包仍会经过
manifest、兼容策略和版本一致性校验，失败时保留当前版本。

### 底层手动安装

不需要持久化管理时，仍可直接使用 Package、Registry 和 Installer：

```dart
final extension = await QuickjsExtension.load(
  QuickjsExtensionPackage(
    manifestSource: manifestSource,
    serviceModules: {
      'service/main.mjs': serviceSource,
    },
    uiModules: {
      'ui/authentication.mjs': authenticationPageSource,
    },
  ),
);

final registry = QuickjsExtensionRegistry();
final installer = QuickjsExtensionInstaller(registry: registry);

final installed = installer.install(
  extension,
  grantedPermissions: const {'network', 'storage'},
  sharedMounts: [commonHostMount],
  serviceMounts: [networkMount],
  uiMounts: [uiHostMount],
);
```

manifest 声明权限不等于已经授权。只有 `grantedPermissions` 中的权限才会进入 Session；未授权的 route 无法打开。

## 调用 Core

宿主原生页面只能调用 `publicExports`：

```dart
final result = await installed.session.callPublic(
  'getHome',
  arguments: const [],
);
```

JSUI 通过绑定模块调用 `uiExports`，调用时不接收插件 ID：

```js
import pluginService from 'quickjs_extensions/plugin_service';
import storage from 'quickjs_extensions/storage';

const result = await pluginService.call('submitLogin', account, password);
await storage.set('session', result.data);
```

## 打开插件页面

```dart
QuickjsExtensionView.route(
  session: installed.session,
  route: 'authentication',
  initialProps: const {'reason': 'sessionExpired'},
)
```

UI Context 随页面销毁；Extension、Session 和已经启动的 Core runtime 保持存在，直到停用或卸载。

调用方向固定为 Flutter 宿主可调用 Core、也可打开 JSUI；JSUI 可通过绑定桥调用同一
Session 的 Core；Core 不可直接调用或控制 UI。需要交互时，Core 应返回
`interactionRequired`，由 Flutter 宿主决定是否打开对应 flow。

## 查询与交互流程

```dart
final sources = registry.servicesForContract('content-source/v1');
final loginFlow = registry.findFlow('site.example', 'authentication');
```

`QuickjsExtensionFlowRunner` 会在 Core 返回 `interactionRequired` 时启动对应 flow。只有 flow 返回 `completed` 才重试原调用，并且最多重试一次，避免认证循环。

## 存储与卸载

默认 `InMemoryQuickjsExtensionStorage` 仅适合开发和测试。正式宿主应实现 `QuickjsExtensionStorage`，接入自己的持久化存储。

```dart
await registry.disable('site.example');
registry.enable('site.example');
await registry.uninstall('site.example', clearStorage: true);
```

停用默认保留 KV；卸载时由 `clearStorage` 决定是否清除插件数据。

## 示例

- [统一包加载、安装和查询](example/quickjs_extensions_example.dart)
- [可运行混合插件：独立 manifest、Core MJS 与 JSUI MJS](https://github.com/yhsj0919/quickjs/tree/main/examples/lemon_js_example/assets/extensions/hybrid_demo)

这里仅保留最小入门示例。完整设计说明、API 用法和测试示例请查看
[GitHub 仓库](https://github.com/yhsj0919/quickjs)。

## 当前边界

当前已提供 manifest v2、兼容策略、旧 Core/UI 适配、内存 Store、本地文件 Store、安装
恢复、更新检查和更新失败回滚；旧 JSUI 包声明的资源引用也会随统一安装包持久化。包内
非 JS 资源字节副本、网络图标缓存、Web 持久化 Store、
插件签名、摘要校验、远程目录、自动更新策略和数据库版 KV 由宿主接入或后续版本提供。
