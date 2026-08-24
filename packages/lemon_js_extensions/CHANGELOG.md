# 更新日志 / Changelog

## 0.2.1

- 升级 `archive`、`http` 与 `path_provider` 依赖。
- 升级到 `lemon_js ^0.2.1` 与 `lemon_js_ui ^0.2.1`。
- Upgraded the `archive`, `http`, and `path_provider` dependencies.
- Upgraded to `lemon_js ^0.2.1` and `lemon_js_ui ^0.2.1`.

## 0.2.0

### 中文

- **破坏性更新：** Extensions 的公开类型、Package 创建、Manager 安装与调用 API 已整体
  重构，且不提供旧名称兼容别名。升级前必须阅读
  [破坏性 API 迁移指南](../../docs/breaking_api_migration.md)。
- 公开类型统一使用 `JsExtension*`，包括 `JsExtensionStoreEntry`、
  `JsExtensionMemoryStore`、`JsExtensionManagerState`、`JsExtensionManagerEntry` 和
  `JsExtensionInstallation`。
- Package 来源统一为 manifest、module 和 ZIP 构造；删除 Manager 中按来源重复的安装方法，
  统一使用 `manager.install(package)`。
- Adapter 统一为 `JsExtensionAdapter`、`JsExtensionCoreAdapter` 和
  `JsExtensionUiAdapter`。
- 能力配置统一为 `JsExtensionFeatures` 和 `storageFactory/httpFactory/cryptoFactory`；队列与超时
  参数统一为 `maxPendingTasks` / `callTimeout`。
- 插件调用不再拼接 `pluginId.method`，改为独立的 `pluginId` 与 `method` 参数。
- Store、Session、Flow、更新检查、资源恢复和 KV 迁移 API 已同步统一命名和职责边界。

### English

- **Breaking update:** Extension public types, package construction, manager installation, and call APIs
  have been comprehensively refactored. No compatibility aliases are provided. Read the
  [breaking API migration guide](../../docs/breaking_api_migration.md) before upgrading.
- Standardized public types on `JsExtension*`, including `JsExtensionStoreEntry`,
  `JsExtensionMemoryStore`, `JsExtensionManagerState`, `JsExtensionManagerEntry`, and
  `JsExtensionInstallation`.
- Standardized package sources around manifest, module, and ZIP constructors; removed source-specific
  manager installation wrappers in favor of `manager.install(package)`.
- Standardized adapters on `JsExtensionAdapter`, `JsExtensionCoreAdapter`, and
  `JsExtensionUiAdapter`.
- Standardized capability configuration on `JsExtensionFeatures` and
  `storageFactory/httpFactory/cryptoFactory`, with `maxPendingTasks` / `callTimeout` for queue and timeout
  limits.
- Replaced concatenated `pluginId.method` calls with separate `pluginId` and `method` parameters.
- Standardized Store, Session, Flow, update-check, resource-restoration, and KV-migration API names and
  responsibility boundaries.

## 0.1.0

### 中文

- 新增统一的 Core、JSUI 与混合扩展模型。
- 新增统一 manifest、安装注册、Session 和按插件隔离的 KV 存储。
- 新增 Core/JSUI 调用桥接、页面路由与交互流程处理。
- 新增 asset、file、network 与 ZIP 扩展包加载入口。
- 新增统一 Manager、文件持久化、重启恢复、更新回滚和按插件 ID 调用。
- Manager 的 Store 改为可选，原生平台与 Web 会自动选择默认持久化实现。
- 新增 manifest v2、兼容策略、旧 Core/JSUI 格式适配、数字版本和远程更新流程。
- 新增版本化的必需/可选宿主能力声明、安装预检和结构化缺失能力错误。
- 保留并持久化旧 JSUI 包中的资源引用。
- 持久化统一包内的非 JavaScript 资源，并在恢复后重建为 JSUI 内嵌资源。
- 增加 `storageVersion` 与插件内部 KV 迁移导出，失败时恢复原命名空间。
- 安装和更新严格校验插件 ID、兼容码与数字版本，阻止未恢复状态下的同 ID 覆盖。
- 默认组合隔离 KV、Fetch/XHR 和 Web Crypto 全部现有实现；宿主可以整体关闭或按 factory
  替换，可选能力不由权限声明触发。
- 增加共享网络 Session 构件、调用上限、默认超时、
  手动重启和故障 Runtime 惰性恢复；重启会明确丢弃 Runtime 内存状态。
- 重写 README，补充完整的 manifest、Core/JSUI 互调、Manager、资源持久化、KV 迁移和管理
  API 示例，并修正 GitHub 文档链接。

### English

- Added unified Core-only, JSUI-only, and hybrid extension models.
- Added manifests, installation registry, sessions, and extension-scoped storage.
- Added the Core/JSUI bridge, UI routes, and interaction flow handling.
- Added asset, file, network, and ZIP extension package loaders.
- Added the unified manager, file persistence, restart restoration, update rollback, and calls by plugin ID.
- Added manifest v2, compatibility policies, legacy Core/JSUI adapters, numeric versions, and remote updates.
- Added versioned required and optional host capability declarations, installation inspection, and structured
  missing-capability errors.
- Preserved and persisted resource references from legacy JSUI packages.
- Persisted embedded non-JavaScript package resources for restart restoration.
- Added versioned KV migrations with namespace rollback on failure.
- Prevented stored extension IDs from being overwritten before restoration.
- Added automatic default Store selection: application-support files on native platforms and
  SharedPreferences on Web.
- Reused the lemon_js SharedPreferencesAsync KV by default with extension ID namespaces, and provided
  storage, network/Axios, and Web Crypto as replaceable optional capabilities.
- Added shared extension HTTP sessions, bounded calls, default timeouts,
  manual restart, and lazy recovery from failed runtimes; runtime restart explicitly discards in-memory
  JavaScript state.
- Reworked the README with complete manifest, Core/JSUI interop, manager, embedded resources, KV migration,
  and management API examples, and corrected GitHub documentation links.
