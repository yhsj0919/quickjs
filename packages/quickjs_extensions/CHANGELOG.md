# 更新日志 / Changelog

## 0.1.0-dev.1

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

### English

- Added unified Core-only, JSUI-only, and hybrid extension models.
- Added manifests, installation registry, sessions, and extension-scoped storage.
- Added the Core/JSUI bridge, UI routes, and interaction flow handling.
- Added asset, file, network, and ZIP extension package loaders.
- Added the unified manager, file persistence, restart restoration, update rollback, and calls by plugin ID.
- Added manifest v2, compatibility policies, legacy Core/JSUI adapters, numeric versions, and remote updates.
- Preserved and persisted resource references from legacy JSUI packages.
- Persisted embedded non-JavaScript package resources for restart restoration.
- Added versioned KV migrations with namespace rollback on failure.
- Prevented stored extension IDs from being overwritten before restoration.
- Reused the lemon_js SharedPreferencesAsync KV by default with extension ID namespaces.
- Added shared extension HTTP sessions, bounded calls, default timeouts,
  cancellation, manual restart, and lazy recovery from failed runtimes.
