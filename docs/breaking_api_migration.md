# Lemon JS 破坏性 API 迁移指南

本指南覆盖当前未发布重构中四个 package 的公开 API 变更。此次重构不提供旧名称兼容别名；
应用应一次性更新 import、类型、构造参数和调用方法。QuickJS 引擎 ABI、`quickjs_ui` 模块
specifier、资源协议标识和实际二进制名称不在 Dart API 改名范围内。

## 入口与类型前缀

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| `Quickjs` | `JsEngine` | 普通单 Context 使用 `JsEngine.create()`。 |
| `QuickjsRuntime` / `QuickjsContext` | `JsRuntime` / `JsContext` | 从 `package:lemon_js/lemon_js_context.dart` 导入多 Context 高级 API。 |
| `Quickjs*` Core 类型 | 对应 `Js*` 类型 | 项目 API 统一去掉实现名称前缀。 |
| `QuickjsUi*` / `QuickJSUI*` | 对应 `JsUi*` | `quickjs_ui` 模块名和协议字符串保持不变。 |
| `QuickjsExtension*` | 对应 `JsExtension*` | 扩展系统统一使用 `JsExtension` 前缀。 |
| `QuickjsPlugin` 平台壳 | `LemonJsPlugin` | Android namespace 同时改为 `xyz.yhsj.lemon_js`。 |

主入口 `package:lemon_js/lemon_js.dart` 只暴露普通 Engine API。需要自行管理 Runtime 和
Context 时改用：

```dart
import 'package:lemon_js/lemon_js_context.dart';
```

## Core 执行与互调

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| `evalModule(...)` | `runModule(name: ..., source: ...)` | ES Module 执行统一使用 `run` 动词。 |
| `evalCommonJs(...)` | `runCommonJs(...)` | CommonJS 包装与缓存语义不变。 |
| `JsModule.specifier` | `JsModule.name` | 模块标识参数统一为 `name`。 |
| `callModule(name: ..., method: ...)` | `callModule(module: ..., method: ...)` | `module` 明确表示模块名。 |
| 手工拼接全局函数调用 | `engine.call(method, args)` | 原始 bridge 结果使用 `callRaw`。 |
| 旧同步/异步混合执行入口 | `eval` / `run` | `eval` 执行普通源码；`run` 执行可含 `await`/`return` 的异步函数体。 |
| 旧原始结果入口 | `evalRaw` / `runRaw` | `Raw` 变体返回 bridge 字符串。 |
| `bindObject` | `injectObject` | Dart 提供给 JS 的能力统一使用 `inject`。 |
| `bindClass` | `injectClass` | 同上。 |
| `bindStreamSink` | `injectStream` | Dart Stream 暴露为 JS async iterable。 |
| `receiveStream` | `bindStream` | JS sink 输出绑定为 Dart Stream。 |
| 旧全局函数绑定 | `injectFunction` / `bindFunction` | Dart → JS 用 `injectFunction`；取得 JS 句柄用 `bindFunction`。 |
| `JsFunctionHandle.cancel()` | 无直接替代 | 句柄仅负责调用和 `dispose()`；取消整个 runtime 请显式 `engine.restart()`。 |
| `maxPendingEvaluations` | `maxPendingTasks` | 只计算等待中的任务。 |

## Core Features、模块与插件

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| `JsMount` / `JsCapabilities` | `JsFeatures` | 宿主能力、脚本、模块和方法统一为 Features。 |
| `mounts:` / `hostCapabilities:` | `features:` | 创建 Engine、Runtime 或 Context 时直接传 Features。 |
| `mount()` | `loadFeatures()` | 运行时加载基础功能。 |
| `FetchMount` | `FetchFeatures` | 直接构造并传入 `features`。 |
| `AxiosMount` | `AxiosFeatures` | Axios 资源已迁入 Core；默认构造无需资源路径。 |
| `WebSocketMount` | `WebSocketFeatures` | Web 平台能力差异见 Core README。 |
| `WebCryptoMount` | `WebCryptoFeatures` | 直接构造。 |
| `StorageMount` | `StorageFeatures` | 直接构造。 |
| Web/Essential/Node mount factory | `WebFeatures()` / `EssentialFeatures()` / `NodeFeatures()` | 不再通过 `JsFeatures` factory 转发。 |
| `assetKey:` | `path:` | asset 和包内资源参数统一使用 `path`。 |
| `JsScript.*` 重复构造 | `JsScript(...)` | 普通源码使用默认构造。 |
| `JsModule.esModule*` | `JsModule(...)` / 对应 asset 构造 | 删除重复 ES Module 构造路径。 |
| `JsHostMethod.*` 重复构造 | `JsHostMethod(...)` | 使用默认构造。 |
| 创建时旧插件字段 | `plugins:` | 运行时使用 `loadPlugin()`。 |
| 旧插件资源/模块 `specifier` | `name` | 插件模块命名与 Core 模块一致。 |
| 拼接 `pluginId.method` | 分离的 `pluginId`、`method` | Registry 和 Client 不再解析拼接字符串。 |
| 已加载插件旧调用 | `callPlugin(pluginId, method, ...)` | 显式插件对象改用 `callPluginExport(plugin, method, ...)`。 |

## lemon_js_ui

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| 低层 Session 从主入口导入 | `lemon_js_ui_session.dart` | 普通页面继续只使用 `JsUiView`/`JsUiController`。 |
| Runtime 池化参数和 `release(reusable:)` | `maxContexts`、`options`、无参数 `release()` | 每次 lease 都对应隔离 Context。 |
| `JsUiHostCapabilities` | `JsUiHostFeatures` | 表示注入页面的宿主功能。 |
| capability `functions(Map<String, Function>)` | `JsUiCapabilityGroup.methods(...)` | 保留类型明确的回调约束。 |
| `toFeatures()` / `methodMaps` | 删除 | 直接使用结构化 Host Features。 |
| 旧导航 route/page 类型 | `JsUiRoute` / `JsUiRouteRequest` / `JsUiRoutePolicy` / `JsUiRouteGuard` | 常用导航入口统一为 `JsUiNavigator.push()`。 |
| `maxDepth`（导航策略） | `maxRouteDepth` | 与 UI 节点深度区分。 |
| 字符串生命周期参数 | `JsUiLifecycle` | 字符串只存在于 JavaScript 协议边界。 |
| `JsUiPagePlugin.inline` | `JsUiPagePlugin.source` | asset 来源使用 `JsUiPagePlugin.asset(path: ...)`。 |
| `exportPageSnapshotMap()` | `exportPageSnapshot().toMap()` | 删除重复返回 Map 的入口。 |
| `JsUiInspector.buildSnapshotMap()` | `buildSnapshot().toMap()` | 同上。 |
| `JsUiRenderContext.dispatchCoalesced()` | `dispatch(..., kind:, defaultCoalesceKey:)` | 命令和高频采样共用一个入口。 |
| `JsUiNetworkLoader.loadPackageWithRefresh()` | `loadPackage(refreshMode: ...)` | 刷新策略成为标准加载参数。 |
| `JsUiResourceReference.location` | `uri` | 字符串协议值使用 `uri`，解析结果使用 `parsedUri`。 |
| Bundle 旧来源构造 | `sources` / `packageAsset` / `packageFile` / `packageNetwork` | ZIP 使用 `archiveAsset` / `archiveFile` / `archiveBytes`。 |
| JS helper `defineComponent` / `action` / `event` | 删除 | 直接使用正式 `Component()` 和标准节点/事件对象。 |

`quickjs_ui`、`quickjs_ui/video_player`、`quickjs_ui.runtime.v1` 等模块和协议标识不得随
Dart 类型一起改名。

## lemon_js_ui_video_player

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| 公开 renderer builder | 删除 | 通过 `JsUiPlugin` 注册视频组件。 |
| 任意 TypeScript props 索引签名 | 明确的组件 props | 未声明属性现在会被类型检查拒绝。 |
| 缺失的加载状态配置 | `showLoading` | 声明与 Dart renderer 支持保持一致。 |

应用仍通过 `JsUiView(..., uiPlugins: [videoPlayerPlugin])` 接入，播放器实例和 controller
由插件生命周期释放。

## lemon_js_extensions

| 旧 API | 新 API | 迁移说明 |
| --- | --- | --- |
| `JsExtensionCompatibilityPolicy` | `JsExtensionConstraint` | 集合类型为 `JsExtensionConstraints`。 |
| `JsExtensionOptionalCapabilities` | `JsExtensionFeatures` | Manager 参数名为 `features`。 |
| `storageProvider` / `httpProvider` / `cryptoProvider` | `storageFactory` / `httpFactory` / `cryptoFactory` | 额外能力放入 `extraCapabilities`。 |
| `maxPendingEvaluations` | `maxPendingTasks` | 与 Core 命名一致。 |
| `MemoryJsKvStore` / `SharedPreferencesJsKvStore` | `JsMemoryKvStore` / `JsSharedPreferencesKvStore` | Core 公开实现统一使用 `Js*` 前缀。 |
| 多个 `install*Package` Manager 包装方法 | `manager.install(package)` | 来源选择由 `JsExtensionPackage` 负责。 |
| 单模块旧安装方法 | `installAssetModule` / `installFileModule` / `installNetworkModule` | asset/file 参数为 `path`，网络参数为 `url`。 |
| `JsExtensionPackageFormat.extension` | `JsExtensionPackageFormat.manifest` | 表示带 manifest 的标准扩展包。 |
| 四个 `formatted*Zip` 构造 | 标准 ZIP factory 的 `format:` 参数 | 删除重复来源组合。 |
| 旧 Adapter 类型 | `JsExtensionAdapter` / `JsExtensionCoreAdapter` / `JsExtensionUiAdapter` | Adapter 决定裸模块类型。 |
| `StoredJsExtension` | `JsExtensionStoreEntry` | 持久化 Store 中的记录与可恢复包组合。 |
| `InMemoryJsExtensionStore` | `JsExtensionMemoryStore` | 扩展 Store 实现统一使用 `JsExtension*` 前缀。 |
| `ManagedJsExtensionState` / `ManagedJsExtension` | `JsExtensionManagerState` / `JsExtensionManagerEntry` | Manager 对外状态与条目统一使用所属抽象前缀。 |
| `InstalledJsExtension` | `JsExtensionInstallation` | 表示已安装扩展及其共享 Session。 |
| `JsExtensionStorage` 兼容别名 | `JsKvStore` | 运行时 KV 与安装记录 Store 保持分离。 |
| Manager 按来源安装 | `JsExtensionPackage.*` + `manager.install(...)` | Package 创建与安装职责分离。 |
| 拼接插件方法名 | `manager.call(pluginId, method, ...)` | 契约选择使用 `callContract(contract, method, pluginId: ...)`。 |

## 最小迁移示例

旧的 mount/bind 风格：

```dart
final runtime = await Quickjs.create(
  mounts: [FetchMount()],
);
await runtime.bindObject('host', object);
```

新的 Engine/Features/inject 风格：

```dart
final engine = await JsEngine.create(
  features: [FetchFeatures()],
);
await engine.injectObject(
  'host',
  JsObject(target: object, members: members),
);
try {
  final result = await engine.run('return await main()');
  print(result);
} finally {
  await engine.dispose();
}
```

扩展安装统一先创建 Package：

```dart
final package = await JsExtensionPackage.asset(
  manifestAsset: 'assets/example/extension.json',
);
final installed = await manager.install(package);
final result = await manager.call(installed.id, 'run');
```

## 迁移检查

迁移后建议执行以下扫描，结果只能包含 QuickJS 引擎事实、FFI/ABI、真实资源协议或
`quickjs_ui` 稳定标识：

```text
Quickjs|quickjs
JsMount|Mount\(|mounts:|hostCapabilities:
bindObject|bindClass|bindStreamSink|receiveStream
assetKey:|specifier:|maxPendingEvaluations
evalModule|evalCommonJs|loadPackageWithRefresh
```

最后分别运行四个 package 和示例工程的 Analyze/测试，并至少编译一次目标平台插件。
