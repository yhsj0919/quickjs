# quickjs_extensions

`quickjs_extensions` 是 `lemon_js` 与 `lemon_js_ui` 之上的统一插件管理层。一个安装包可以
只包含 Core 数据服务、只包含 JSUI 页面，或同时包含两者。Manager 负责安装、恢复、更新、
启停、卸载、按 ID 调用和插件级 KV 隔离；插件管理页面由宿主业务层实现。

## 安装

```yaml
dependencies:
  quickjs_extensions: ^0.1.0-dev.1
```

```dart
import 'package:quickjs_extensions/quickjs_extensions.dart';
```

## 插件目录

```text
site_plugin/
├── manifest.json
├── service/
│   └── main.mjs
└── ui/
    └── login.mjs
```

统一 Extension 必须包含 manifest；旧 Core 或 JSUI 裸入口需要通过对应 adapter 显式安装。

## 最小 manifest

```json
{
  "schemaVersion": 2,
  "id": "site.example",
  "name": "示例站点",
  "description": "提供数据和登录页面",
  "version": "1.0.0",
  "versionCode": 10000,
  "compatibilityCode": "content-source-v1",
  "service": {
    "entry": "service/main.mjs",
    "contract": "content-source/v1",
    "publicExports": ["getHome"],
    "uiExports": ["submitLogin"]
  },
  "ui": {
    "routes": {
      "login": {
        "entry": "ui/login.mjs",
        "title": "登录"
      }
    }
  },
  "flows": {
    "authentication": {"route": "login"}
  },
  "capabilities": {
    "required": {"network": 1},
    "optional": {"crypto": 1}
  },
  "permissions": ["network", "storage"]
}
```

插件可以只实现 contract 的部分可选方法，但必须实现宿主兼容策略声明的必需方法。插件的
内部辅助函数不影响校验。

## Core 模块

```js
export function getHome() {
  return { items: [] };
}

export async function submitLogin(account, password) {
  return { ok: true, account };
}
```

## JSUI 调用同插件 Core

```js
import { ElevatedButton, Page, Text } from 'quickjs_ui';
import pluginService from 'quickjs_extensions/plugin_service';
import storage from 'quickjs_extensions/storage';

export default Page({
  name: 'LoginPage',
  createState() { return { status: '未登录' }; },
  build(state, props, page) {
    return ElevatedButton({
      child: Text(state.status),
      onPressed: page.login()
    });
  },
  async login() {
    const result = await pluginService.call('submitLogin', 'demo', 'password');
    await storage.set('session', result);
    return { status: result.ok ? '已登录' : '登录失败' };
  }
});
```

JSUI 只能调用同一 Session 中 manifest 声明的 `uiExports`，不接收任意插件 ID。Core
不能直接控制 UI；需要交互时应返回业务状态，由 Flutter 决定是否打开 flow。

## 创建 Manager

```dart
final manager = QuickjsExtensionManager(
  compatibilityRegistry: QuickjsExtensionCompatibilityRegistry(
    <QuickjsExtensionCompatibilityPolicy>[
      QuickjsExtensionCompatibilityPolicy(
        compatibilityCode: 'content-source-v1',
        requiredPublicExports: const <String>{'getHome'},
        optionalPublicExports: const <String>{'search', 'getDetail'},
      ),
    ],
  ),
);

await manager.restore();
```

`store` 可以省略：原生平台默认保存到应用支持目录，Web 默认使用 SharedPreferences Web
后端。宿主可传入自定义 `QuickjsExtensionStore`。插件 KV 默认使用
`SharedPreferencesQuickjsKeyValueStore`，并按插件 ID 隔离。

## 加载、安装和调用

```dart
final package = await QuickjsExtensionPackage.asset(
  manifestAsset: 'assets/extensions/site_plugin/manifest.json',
);

await manager.install(
  package,
  grantedPermissions: const <String>{'network', 'storage'},
);

final home = await manager.call('site.example', 'getHome');
```

还支持 `file`、`network`、`assetZip`、`fileZip`、`networkZip` 和 `zipBytes`。不同来源最终
都会归一化为 `QuickjsExtensionPackage`。

打开插件页面：

```dart
final installed = manager.find('site.example')!.installed!;

QuickjsExtensionView.route(
  session: installed.session,
  route: 'login',
  initialProps: const <String, Object?>{},
)
```

第三方 `QuickjsUiPlugin` 不能序列化，应通过 Manager 的 `uiPluginsResolver` 在恢复时按
插件 ID 重新注入。

## 更新与数据迁移

Manager 会校验插件 ID、`compatibilityCode` 和数字 `versionCode`，默认拒绝同版本和
降级，也不会在尚未调用 `restore()` 时覆盖 Store 中的同 ID 插件。

插件升级需要修改 KV 结构时，提高 `storageVersion` 并声明：

```json
{
  "storageVersion": 2,
  "service": {
    "storageMigrationExport": "migrateStorage"
  }
}
```

```js
export async function migrateStorage(fromVersion, toVersion) {
  // 使用 quickjs_extensions/storage 迁移当前插件命名空间。
}
```

迁移或新版本激活失败时，Manager 会恢复旧 KV 和旧安装记录。

## 资源和能力

目录、asset 和网络插件通过 manifest 的 `resources` 列出需要持久化的非 JS 文件；ZIP
中的非 JS 文件会自动收集。必需宿主能力缺失时安装会抛出包含完整检查结果的
`QuickjsExtensionCapabilityException`；可选能力缺失只报告，不阻止安装。

Manager 默认提供隔离 KV、网络/Axios 和 Web Crypto。宿主可通过
`QuickjsExtensionOptionalCapabilities` 替换或关闭。

## 管理 API

```dart
final installed = manager.extensions;
await manager.disable('site.example');
await manager.enable('site.example');
await manager.uninstall('site.example', clearStorage: false);
```

Manager 只提供无 UI 的状态和管理 API，安装列表、权限确认和更新页面由宿主业务层负责。

## 示例与设计

- [pub 包最小示例](example/quickjs_extensions_example.dart)
- [可运行混合插件](https://github.com/yhsj0919/quickjs/tree/master/examples/lemon_js_example/assets/extensions/hybrid_demo)
- [完整 Flutter 示例](https://github.com/yhsj0919/quickjs/tree/master/examples/lemon_js_example)
- [混合插件设计](https://github.com/yhsj0919/quickjs/blob/master/docs/hybrid_plugin_design.md)

完整可运行工程位于 GitHub；pub 包中保留最小 Dart 示例。
