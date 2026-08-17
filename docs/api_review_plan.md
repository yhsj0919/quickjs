# Lemon JS 公开 API 审查计划

本文档是四个 package 的公开 API 审查清单。每完成并验证一项，就将对应复选框改为
`[x]`。审查以实际调用是否简洁为第一目标，公开命名一致性为第二目标；内部全局改名在
每个 package 的公开方案稳定后集中完成。

## 审查原则

- 优先检查对外暴露的方法、构造函数、参数、返回值和默认值。
- 每项审查必须先写出实际最小调用代码，再判断是否繁琐。
- 常用调用应尽量减少必填参数、中间对象和内部概念。
- 高级能力可以保留，但不应增加基础调用的复杂度。
- 不保留仅用于兼容旧名称的别名或重复路径。
- 项目自有的公开和内部标识应消除 `Quickjs` / `quickjs` 前缀。
- 仅保留底层 QuickJS 引擎、FFI/ABI、真实二进制名、既定包或协议标识、资源路径，
  以及描述引擎本身时的 `QuickJS` 文本。
- 每个 package 完成后同步代码、测试、示例和文档，并执行该 package 的验证。

## 状态说明

- `[x]`：语义已经确认、代码已经修改并通过对应验证。
- `[ ]`：尚未完整审查，或虽有改动但仍未按实际调用重新确认。
- 已经局部改过但未完成整组审查的项目保持 `[ ]`，避免把“改过”误认为“审完”。

## 1. lemon_js

### 1.1 创建与执行

- [x] 审查 `lemon_js.dart` 的全部公开导出；多 Context/内部组合保持独立入口，主入口隐藏后端协议解析函数 parseJsExceptionPayload。
- [x] 审查 `JsEngine.create()`；无参数即为最小创建，options/moduleLoader/scripts/modules/methods/features/plugins/onConsole 均为独立职责，不合并。
- [x] 主入口只暴露 `JsEngine`；`JsRuntime` / `JsContext` 多 Context 高级能力移至
  `lemon_js_context.dart`。
- [x] 保留 `eval()` 与 `run()` 两种执行语义，并写清同步执行与 Promise 执行差异。
- [x] 对 `eval()` 与 `run()` 暴露 `evalRaw()` / `runRaw()` 原始结果变体。
- [x] 提供 `call(method, args)`，避免调用全局方法时手工拼接 JavaScript。
- [x] `JsFunctionHandle` 保留 `call/run` 及对应 Raw 变体，与 Engine 的同步/Promise
  执行语义保持一致。
- [x] 将模块执行命名统一到 `runModule()`，模块参数使用 `name`。
- [x] 保留 `moduleLoader`，并明确它是模块源码的懒加载回调。
- [x] 审查 `runModule()` 与 `runCommonJs()`；二者分别执行 ES Module 图与 CommonJS 包装/缓存，不增加转发别名，统一 run 格式留待执行抽象重构。
- [x] 审查 timer pump、restart、dispose 和状态；三者职责独立，删除 create 完成前不可观察且从未赋值的 JsRuntimeState.creating。

### 1.2 创建配置与宿主能力

- [x] `maxPendingEvaluations` 简化为 `maxPendingTasks`，注释明确只计算等待任务。
- [x] `JsOptions` 仅保留内存字节、栈字节和最大等待任务数；参数、单位、默认值及
  平台差异已有明确注释。
- [x] 将原 Mount/Capability 注入模型统一为 `JsFeatures` 语义。
- [x] `JsScript` 简化为默认 `JsScript` 构造；`JsModule` 删除重复的
  `esModule/esModuleAsset`；`JsHostMethod` 简化为默认构造。
- [x] 审查 web/essential/node 能力；统一为外部 WebFeatures/EssentialFeatures/NodeFeatures 类型，删除 JsFeatures factory 转发层。
- [x] Fetch、WebCrypto、Storage、WebSocket 保持直接构造；Axios 脚本迁入 Core 并支持
  `AxiosFeatures()` 零参数创建，同时保留自定义 path 和共享 Session。
- [x] 审查 asset 模块 loader；简化为 assetModuleLoader，prefix 保持“模块名到 asset key 的目录前缀”语义。

### 1.3 Dart 与 JavaScript 互调

- [x] 统一方向语义：Dart → JS 使用 `inject*`，JS → Dart/JS 句柄使用 `bind*`。
- [x] 对外使用 `injectFunction`、`injectObject`、`injectClass`、`injectStream`。
- [x] 对外使用 `bindFunction`、`bindStream`。
- [x] `JsAccessor` 和 `JsMethod` 自带名称，`JsMembers.accessors/methods` 使用列表。
- [x] 多个对象和类共用 `JsMembers` 描述结构，移除重复模型。
- [x] 对象与类继续共用显式 `JsMembers` 描述；反射注入作为后续独立能力，不在当前
  显式约束 API 上叠加兼容层。
- [x] 句柄只负责调用与 `dispose`；删除会重启整个引擎的 `JsFunctionHandle.cancel()`，
  runtime 取消由用户显式调用 `engine.restart()`；内部 handle ID 不再公开。
- [x] Stream 方向保持 `injectStream`（Dart → JS async iterable）和 `bindStream`
  （JS sink → Dart Stream），关闭、错误与背压语义已有明确注释。
- [x] 审查结构化值、JsUndefined、二进制值和转换异常；undefined 保持单例，ArrayBuffer/Uint8Array 统一为 Uint8List，不支持值统一抛转换异常。

### 1.4 Plugin 与模块包

- [x] `assetKey` 及同义资源参数统一为 `path`。
- [x] 审查 JsPluginManifest 与最小插件创建；单文件使用 JsPlugin.source，仅 id/version/source/exports 必填，多模块才显式创建 Manifest。
- [x] 审查 `JsPlugin` 的 `source/asset/assets/sources/manifestAsset/fromManifest`。
- [x] 创建时用 `plugins:`，运行时用 `loadPlugin()`；插件到 Features 的转换移出公开 API。
- [x] `JsPluginClient.init` 改用命名参数；Registry 调用拆分 pluginId 与 method，避免
  拼接 `pluginId.method`。
- [x] 已加载插件使用 `callPlugin`，显式插件对象使用 `callPluginExport`，删除
  `callPlugin` 动词。
- [x] `JsZipPlugin` 保留 asset/bytes/archive 三种真实来源，`archive` 简化为
  `archive`。

### 1.5 错误、诊断与全局命名

- [x] 审查全部 JsException 与 kind；各类型对应独立恢复语义，保留稳定分类，内部 payload parser 已从主入口隐藏。
- [x] 审查 SourceMap 注册和位置类型；保留创建、注册、查询和移除入口，明确生成位置行列基准及当前异常重映射行为。
- [x] 审查 Inspector/debug API；debugInspect 属于 Engine 的直接诊断能力，返回类型继续随主入口导出，避免入口割裂。
- [x] 审查 Web/原生入口一致性；统一使用 lemon_js.dart，Web 注册入口不额外公开 API，并记录 stackLimit 与 WebSocketFeatures 平台差异。
- [x] Flutter Web 插件注册类 `QuickjsWeb` 改为 `JsWeb`，同步 plugin metadata。
- [x] 清理 Core 项目自有 Quickjs/quickjs 标识与可改 Dart 文件名；仅保留引擎事实、C ABI/bindings、Web 资源协议、跨语言 wire 字段及 process.versions.quickjs。
- [x] 同步 Core README、API 文档和所有示例；已删除公开名、旧参数、旧能力 factory、旧清单名和旧 Dart 路径扫描清零。
- [x] Core Analyze 通过；包含 WebSocket 在内的 241 项原生测试通过。
  关键 Web 验证已使用正确的 Chrome platform 参数启动，但当前环境连续三次无法
  启动 Chrome，尚待可用环境复验。

## 2. lemon_js_ui

### 2.1 创建与加载

- [x] 审查主入口的全部公开导出；移除内部 JS helper 与低层 Session，保留 View
  配置、公开返回类型和自定义组件扩展所需类型。
- [x] 审查 `JsUiView.plugin/asset/file/network`；各入口只要求对应来源参数，其余配置
  均可选，并拒绝同时传入外部 controller 与其 runtime/console 配置。
- [x] 审查 Runtime、Session、Controller 是否向普通使用者暴露过多层级；主入口保留
  View 所需的 Runtime 与 Controller，低层 Session 移至 `lemon_js_ui_session.dart`。
- [x] `JsUiRuntime` 删除无效池化参数，统一为 `maxContexts/options`，并删除无效的
  `idleCount` 与 `release(reusable:)`。
- [x] `JsUiController` 不再暴露底层 `session`，只提供 Inspector 实际需要的只读
  `features`。
- [x] 审查 Bundle、Manifest、模块、asset、file、network、ZIP 的加载入口。
- [x] `JsUiBundle` 来源命名统一为 `sources/packageAsset/packageFile/packageNetwork`、
  `archiveAsset/archiveFile/archiveBytes`、`loadEntry/loadManifest/fromManifest`；资源参数
  统一使用 `path`。
- [x] `JsUiManifest.schemaVersion` 与 `JsUiCacheManifest.mode` 使用和 JSON 解析一致的
  默认值，手工创建只要求真正的业务字段。
- [x] 审查资源 resolver/cache/loader 的参数和宿主配置复杂度。
- [x] 合并 `JsUiNetworkLoader.loadPackageWithRefresh()` 到 `loadPackage()` 的
  `refreshMode` 参数，删除重复加载路径。
- [x] `JsUiResourceReference` 的协议字段统一为字符串 `uri`，解析结果明确为
  `parsedUri`，消除原 `location` 与 `uri` 类型冲突。
- [x] 默认资源约束简化为 `JsUiResourcePolicy.renderer()`；Cache 保留
  `maxAge/maxBytes/maxEntries` 三个相互独立的限制。

### 2.2 功能与交互

- [x] 审查 Host features 与权限策略的创建和注入方式。
- [x] Host 注入只保留结构化 `JsUiCapabilityGroup.methods()`；删除丢失回调约束的
  `functions(Map<String, Function>)`，以及重复的 `toFeatures()` / `methodMaps`。
- [x] 运行时注入聚合类 `JsUiHostCapabilities` 改为 `JsUiHostFeatures`；具体
  capability 枚举和 permissions 保留协议语义。
- [x] 审查导航器、路由参数、返回值和页面生命周期。
- [x] 导航模型简化为 `JsUiRoute/JsUiRouteRequest/JsUiRoutePolicy/JsUiRouteGuard`；
  常用入口统一为 `JsUiNavigator.push()`，深度限制为 `maxRouteDepth`。
- [x] 路由动画只保留 `material/none/fade/slide/scale` 约束构造，隐藏可产生无效参数
  组合的通用构造。
- [x] Controller/Session 生命周期参数使用 `JsUiLifecycle` 枚举，字符串仅保留在 JS
  协议边界；普通生命周期与路由调度生命周期继续使用不同方法。
- [x] 审查组件 registry、plugin、render context 和自定义组件注册代码。
- [x] `JsUiPagePlugin` 的内联与资源来源统一为 `source` / `asset`，版本默认值一致。
- [x] 审查事件、方法回调、状态更新和异步边界。
- [x] 审查 Snapshot、错误覆盖层、Inspector 和性能报告 API。
- [x] 删除重复的 `exportPageSnapshotMap()`，统一使用
  `exportPageSnapshot().toMap()`。
- [x] 删除重复的 `JsUiInspector.buildSnapshotMap()`，统一使用
  `buildSnapshot().toMap()`。
- [x] `JsUiPlugin` 构造参数简化为 `configure:` 并私有保存；Registry 删除公开 Map
  构造，用户统一通过类型明确的 `register/registerLifecycle` 注册。
- [x] `JsUiRenderContext.dispatch()` 合并进 `dispatch()` 的可选参数，普通事件与
  高频合并事件共用一个入口。

### 2.3 协议、命名与验证

- [x] 明确 Dart 公共 API 与 JS 内部协议的命名边界。
- [x] 保留确属生命周期协议的 `mount`，清除错误用于“注入能力”的 mount。
- [x] 清理 UI 项目自有 `Quickjs/quickjs` 标识；记录必须保留的 `quickjs_ui` 协议项。
- [x] 同步 Dart 文档、JS 声明文件、生成器和示例；旧公开名称扫描清零，helper
  生成源一致性测试通过。
- [x] 运行 UI analyze、全量测试、生成一致性及关键 Widget 测试（244 项通过）。

## 3. lemon_js_ui_video_player

- [x] 审查 package 主入口和全部公开类型；内部 renderer builder 不再公开。
- [x] 审查插件创建、注册和接入 `JsUiView` 的最小代码。
- [x] 审查视频组件 props、默认值和必填参数；声明文件删除任意属性签名并补齐
  `showLoading` 与资源引用类型。
- [x] 审查播放控制方法、事件名和 Dart/JS 数据结构；记录 token、进度节流和事件载荷。
- [x] 审查 controller、播放器实例和资源释放生命周期。
- [x] 清理项目自有 `Quickjs/quickjs` 标识；仅保留包名、文件名和
  `quickjs_ui/video_player` 既定模块标识。
- [x] 同步 README、JS 声明、示例和测试。
- [x] Analyze 通过，全量 3 项测试通过，包括进度风暴与 togglePlay 用例。

## 4. lemon_js_extensions

### 4.1 创建、Package 与安装

- [x] 从实际最小代码重新审查 `JsExtensionManager` 创建复杂度；只保留安全边界所需的
  `constraints` 必填，其余依赖和执行配置均有默认值。
- [x] `JsExtensionCompatibilityPolicy` 简化为 `JsExtensionConstraint`，集合为
  `JsExtensionConstraints`，并写清约束语义。
- [x] Manager 队列和超时参数统一为 `maxPendingTasks` / `callTimeout`。
- [x] `JsExtensionOptionalCapabilities` 简化为 `JsExtensionFeatures`，参数为 `features`。
- [x] Features 工厂参数简化为 `storageFactory/httpFactory/cryptoFactory`，额外能力使用
  `extraCapabilities`。
- [x] 审查 Manifest 全部字段、嵌套类型及手工创建复杂度；Dart 手工创建的
  `description/versionCode` 默认 `''/0`，安装包 JSON 解析继续严格必填。
- [x] 审查 `JsExtensionPackage` 创建入口；Manifest 保留 `asset/file/network`，ZIP 保留三种来源与 bytes，裸 Core/UI 模块统一为 `moduleAsset/moduleFile/moduleNetwork`，由 sealed Adapter 决定类型。
- [x] 删除四个 `formatted*Zip` 重复方法，将 `format` 合入标准 ZIP 工厂。
- [x] `JsExtensionPackageFormat.extension` 改为 `manifest`。
- [x] Adapter 类型统一为
  `JsExtensionAdapter/JsExtensionCoreAdapter/JsExtensionUiAdapter`。
- [x] 单模块安装方法统一为 `installAssetModule/installFileModule/installNetworkModule`。
- [x] 单模块来源参数统一为 asset/file 使用 `path`，network 使用 `url`。
- [x] Manager 删除 9 个按来源重复的 install 包装方法；Package 负责创建，Manager 统一使用 `install(package)`。

### 4.2 管理、调用与生命周期

- [x] 审查 install/update/restore/enable/disable/uninstall/dispose；安装、更新、启停、卸载与仅释放实例职责独立，不合并为含糊状态开关。
- [x] 审查 `call/callContract/supports/servicesFor*`；保留精确调用、契约选择与启用状态筛选，删除无调用且重复的 Constraint.supports。
- [x] 审查 Session、Registry 和 Installer；Session/View 返回类型、Registry/Flow 注入及无持久化低层安装均有独立用途，普通应用仍以 Manager 为首选。
- [x] 审查 Flow 调用、交互恢复、状态和结果类型；Manager.call 保持纯 Core 调用，FlowRunner.call 负责按需打开 UI 并最多重试一次，Core/UI 状态类型保持独立。
- [x] 审查 Storage、迁移、Store 和更新检查 API；运行时 KV 与安装记录 Store 保持分离，删除 Storage 兼容别名，更新继续采用检查与下载更新两步。
- [x] 审查 `JsExtensionView` 创建和 UI 插件 resolver；session/route/临时 routeFeatures 职责独立，resolver 仅在恢复时重建不可序列化的 Dart UI 插件。
- [x] 能力检查结果统一为 `JsExtensionCapabilityReport`，异常字段使用 `report`。

### 4.3 命名、文档与验证

- [x] 清理 Extensions 项目自有 `Quickjs/quickjs` 标识及可改文件名；内部文件统一为 extension_*，仅保留 quickjs_ui 协议模块名与实际仓库 URL。
- [x] 同步 README、设计文档、示例和 manifest 文档；已删除 API、旧参数名与旧内部文件名扫描清零。
- [x] 运行 Extensions analyze 和全量测试（Analyze 0 问题，36 项测试通过）。

## 5. 四包交叉复核

- [x] 四个 package 的 README 均提供可直接使用的最小代码，分别覆盖 Core 执行、JSUI 页面、视频插件和 Extension 安装调用。
- [x] `create/load/install/run/eval/call/inject/bind` 动词及 `features/plugin/module` 类型边界已按命名规范和四包真实签名交叉确认。
- [x] 相同概念统一使用 `name/module/method/path/url/timeout/maxPendingTasks`；来源专属参数和不同层级默认值均有独立语义。
- [x] Dart 公开层无废弃兼容 API；删除 JSUI 未使用的 `defineComponent/action/event` 重复导出，并补全正式 `Component()` 类型声明。
- [x] 非保留 `Quickjs/quickjs` 标识已清零；平台插件壳统一为 `LemonJsPlugin/lemon_js_plugin`，仅保留引擎 C ABI、Web bridge 及 `quickjs_ui` 包/协议身份。
- [x] 检查四包公开 API 注释覆盖和文档代码可编译性；四包
  `public_member_api_docs` 均已清零，UI 整包 Analyze 0 问题。
- [ ] 四包及示例 Analyze 通过；Core 241 项、UI 244 项、
  Video 3 项、Extensions 36 项、示例 58 项测试通过；Windows 平台插件 target 编译通过。
  仅当前环境无法启动 Chrome 的关键 Web 验证尚未闭环。
- [x] 输出完整破坏性变更清单和迁移对照表；见
  `docs/breaking_api_migration.md`。
