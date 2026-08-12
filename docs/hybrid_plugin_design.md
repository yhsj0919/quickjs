# QuickJS 混合插件设计（讨论稿）

## 1. 目标与范围

宿主已经具备通用的原生数据解析与展示页面。不同站点返回相同的标准数据结构，宿主可以遍历已安装的数据源插件，将结果聚合或分别展示。

登录、验证码、扫码、风险验证和首次配置等流程差异很大，不适合继续由宿主预设页面。混合插件允许站点在保留标准 Core 数据能力的同时，使用 quickjs_ui 提供这些无法统一的交互流程。

混合插件是建立在现有 Core 插件与 quickjs_ui 插件之上的应用级安装包，不是第三套 JS 执行引擎或 UI 渲染协议。

```text
混合插件包
├── Core 插件：标准数据能力与站点业务逻辑
└── JSUI 插件：登录、验证、配置等自定义交互
```

本文只记录当前讨论形成的设计方向，不表示相关能力已经实现。

## 2. 已确定的设计原则

1. 宿主继续负责能够标准化的数据展示，不用 JSUI 重写通用原生页面。
2. Core 插件负责数据获取、认证请求、认证状态判断和凭据使用。
3. JSUI 负责宿主无法统一的认证、验证和配置交互。
4. 宿主根据 manifest 发现能力和入口，不再通过探测某个 JS 方法是否存在来决定页面行为。
5. 一个混合插件包可以包含 Core 和 JSUI 两种基础插件；宿主分别加载，但绑定到同一个宿主级 `QuickjsExtensionSession`。
6. 同一混合插件的 Core 与 JSUI 共享插件身份、权限和 KV 命名空间，但不要求运行在同一个 QuickJS Context。
7. 不同站点拥有不同 Session，存储和能力互相隔离。
8. JSUI 不得在运行时自行传入任意插件 ID 选择 Core；宿主根据当前 route 所属 Session 注入已绑定的 Core 能力。

## 3. 插件形态

统一安装包模型可以自然表达三种形态：

| 形态 | Core service | JSUI routes | 用途 |
| --- | --- | --- | --- |
| 数据插件 | 有 | 无 | 仅供宿主通用原生页面调用 |
| UI 插件 | 无或很少 | 有 | 独立 JSUI 页面或 UI 扩展 |
| 混合插件 | 有 | 有 | 标准数据展示与自定义交互并存 |

不建议让固定的 `type: "hybrid"` 成为加载依据。安装器应根据 manifest 中实际声明的 `service`、`ui` 和 `flows` 判断能力；“混合插件”可以作为派生分类用于展示。

### 3.1 架构决策：使用独立基础包

混合插件采用独立基础包实现，不放入最底层的 `package:lemon_js`，也不作为 quickjs_ui 内部的附属功能。包名确定为 `lemon_js_extensions`。

```text
业务宿主
    ↓
lemon_js_extensions
├── 依赖 lemon_js
└── 依赖 lemon_js_ui
        ↓
lemon_js_ui -> lemon_js
```

依赖方向必须保持单向：

- `lemon_js` 只负责 JS runtime、模块、Core 插件、mount/provider 和底层生命周期，不依赖 lemon_js_ui 或 `lemon_js_extensions`；
- lemon_js_ui 负责通用 JSUI 加载、渲染、事件、导航与页面生命周期，继续依赖 `lemon_js`，但不依赖 `lemon_js_extensions`；
- `lemon_js_extensions` 同时依赖 `lemon_js` 与 lemon_js_ui，提供二者的通用组合能力；
- 业务宿主可以直接使用 `lemon_js`、lemon_js_ui，也可以选择依赖 `lemon_js_extensions`，由业务层解释登录、内容源、播放器等具体语义。

`lemon_js_extensions` 是可选的插件系统与组合语法糖层。它不取代 `lemon_js` 和 `lemon_js_ui` 的独立使用方式。它负责：

- 统一混合插件包和 manifest；
- `InstalledQuickjsExtension` 与 `QuickjsExtensionSession`；
- service、UI bundle/routes 和资源的组合加载；
- 同插件 scoped KV、权限和 host capabilities 的绑定；
- JSUI 到同 Session Core 的受限 service bridge；
- 通用安装、启用、停用、卸载和兼容性基础机制；
- 不带业务语义的 route 与扩展 metadata 暴露。

它不负责：

- `content-source/v1` 等具体数据协议；
- “需要登录”结果的业务解释和产品交互；
- 播放器、详情页或阅读器等页面插槽；
- 用户选择哪个替代页面；
- 插件 UI 失败后回退哪个系统页面。

后续的可选页面替换能力属于业务宿主：系统 UI 永远作为默认和兜底，业务层可以选择通用 JSUI 页面提供者，失败时回退系统 UI。通用 UI 插件自身仍有安装 ID，但不固定绑定某个站点 ID；运行时由业务层建立受限的页面 Session。该模型可以使用 `lemon_js_extensions` 提供的包、UI route 和隔离基础设施，但页面插槽及回退规则不进入 `lemon_js_extensions` 的通用协议。

### 3.2 统一公开命名与构造变体

`lemon_js_extensions` 只公开一套主体命名，不为 JS、UI 和混合形态建立三套平行的 package、installer、session 或 installed 类型。

统一公开入口：

```dart
import 'package:lemon_js_extensions/lemon_js_extensions.dart';
```

统一主体类型与构造变体：

```dart
QuickjsExtension.js(...)
QuickjsExtension.ui(...)
QuickjsExtension.hybrid(...)
```

也支持从统一 manifest 自动加载：

```dart
final extension = await QuickjsExtension.load(package);
```

形态由实际组件派生，而不是驱动三套加载流程：

```text
只有 service -> js
只有 ui      -> ui
service + ui -> hybrid
```

统一使用以下命名族：

```text
QuickjsExtension
QuickjsExtensionManifest
InstalledQuickjsExtension
QuickjsExtensionSession
QuickjsExtensionRegistry
QuickjsExtensionInstaller
QuickjsServiceComponent
QuickjsUiComponent
```

不引入 `InstalledCorePlugin`、`InstalledUiPlugin`、`InstalledHybridPlugin` 等平行公开类型。`.js`、`.ui`、`.hybrid` 只是同一个 `QuickjsExtension` 的构造与分类变体。

底层能力仍保持独立可用：

```dart
// 不经过 lemon_js_extensions，直接使用 Core 插件。
final plugin = QuickjsPlugin(...);

// 不经过 lemon_js_extensions，直接使用 JSUI bundle。
final bundle = QuickjsUiBundle(...);
```

`lemon_js_extensions` 必须通过 `lemon_js` 与 `lemon_js_ui` 的公开 API 完成组合，不要求简单使用者先包装成 `QuickjsExtension`，也不应让底层 API 依赖扩展系统。

### 3.3 View 命名与职责

现有 `QuickjsUiView` 保持原名和现有职责，不增加 `.js`、`.ui` 或 `.hybrid` 构造变体。它属于 quickjs_ui，只负责直接加载和渲染 JSUI 页面；现有 `.plugin`、`.asset`、`.file`、`.network` 描述页面来源，继续独立可用。

不采用以下 API：

```dart
QuickjsUiView.js(...)
QuickjsUiView.ui(...)
QuickjsUiView.hybrid(...)
QuickjsUiView.extension(...)
```

其中 `.js` 没有可渲染 UI，`.ui` 与类本身语义重复；`.hybrid`/`.extension` 会迫使 quickjs_ui 理解上层扩展系统，并造成 quickjs_ui 反向依赖 `lemon_js_extensions`。

`lemon_js_extensions` 新增 Session 感知的包装 View：

```dart
QuickjsExtensionView.route(
  session: session,
  route: 'authentication',
  initialProps: props,
)
```

它负责：

- 从 `QuickjsExtensionSession` 解析指定 UI route；
- 取得对应 bundle/plugin；
- 绑定宿主明确配置的 scoped KV、权限策略与 host mounts；
- 对 hybrid 变体注入绑定到同一 Session Core 的 service bridge；
- 最终委托现有 `QuickjsUiView` 完成加载和渲染。

```text
QuickjsExtensionView.route
        ↓ 解析 extension/session/route/mounts
QuickjsUiView
        ↓
Flutter Widget
```

统一命名关系为：

```text
QuickjsUiView
├── .plugin
├── .asset
├── .file
└── .network

QuickjsExtension
├── .js
├── .ui
└── .hybrid

QuickjsExtensionView
└── .route
```

`package:lemon_js_extensions/lemon_js_extensions.dart` 作为扩展系统的统一导出入口，可以同时导出 `QuickjsExtension`、`QuickjsExtensionView` 等扩展 API，以及使用扩展 API 时必要的 `lemon_js`、`lemon_js_ui` 公共类型。直接依赖 `lemon_js_ui` 的使用者仍从其原入口使用 `QuickjsUiView`，不需要引入扩展包。

## 4. QuickjsExtensionSession

每个已安装并启用的站点插件对应一个独立 Session：

```text
QuickjsExtensionSession(site.example1)
├── Core runtime/context（可以长期存在）
├── JSUI context（打开页面时创建，可以随页面销毁）
├── scoped KV：site.example1
├── granted permissions
└── bound host capabilities
```

多个站点之间完全隔离：

```text
site.example1 -> Session1 -> KV/site.example1
site.example2 -> Session2 -> KV/site.example2
site.example3 -> Session3 -> KV/site.example3
```

Session 是宿主级的身份和资源边界，不等同于 QuickJS Context。JSUI 页面关闭或 Context 销毁不应销毁整个插件 Session；插件卸载或停用策略决定 Session 和存储的最终处理。

插件 ID 必须来自宿主验证过的安装记录。JS 只能看到已经绑定到当前 Session 的 KV 和 service bridge，不能伪造其他插件 ID。

### 4.1 常驻生命周期

`QuickjsExtension` 一般是创建并注册后常驻系统内存的稳定对象，不是一次调用或一个页面的临时包装器。其默认 `QuickjsExtensionSession` 与 extension 使用同一长期生命周期。

默认生命周期规则：

- 创建并注册 extension 后，其身份、manifest、组件描述和默认 Session 持续存在；
- `.js` 和 `.hybrid` 的 Core runtime 默认长期存在，供宿主原生页面和 JSUI service bridge 反复调用；
- Core runtime 可以延迟到第一次调用时创建，但一旦创建，默认保留到 extension 停用、卸载、替换或应用关闭；
- `.ui` 和 `.hybrid` 的 JSUI 页面 Context 按 route 创建，随页面销毁，不影响常驻 extension、默认 Session 或 Core runtime；
- 页面关闭不能隐式 dispose extension；
- 临时调用方必须显式 `dispose()`，插件管理系统则由 registry/installer 统一管理释放；
- 停用停止新调用和新页面创建，并按确定的停止策略释放 runtime，但不默认删除 KV；
- 卸载释放所有 runtime、注销 route/service，并根据卸载选项保留或清除 scoped KV；
- 升级使用新的 extension/session/runtime 原子替换旧实例，不能直接修改正在执行的实例。

常驻对象与常驻 runtime 是两个层次。extension 和默认 Session 固定常驻；Core runtime 允许首次调用时懒创建，但不采用每次调用后销毁的默认策略。未来如增加内存压力下的空闲回收，应作为显式可配置策略，并保证 Session 身份和持久状态不变。

由于 runtime 默认长期存在，能力配置应在 Session 启动前完成。启动后修改 mounts 不能被视为普通字段更新；如果底层需要重建 runtime，应通过明确的 reconfigure/restart 或扩展替换流程，并处理在途调用。

### 4.2 能力的统一管理与分别注入

基础能力由 `QuickjsExtensionSession` 统一配置和授权，但 Core 与 JSUI 通常处于不同 Context，创建各自 runtime 时分别注入：

```text
Core runtime = authorized sharedMounts + serviceMounts

UI runtime = authorized sharedMounts
           + uiMounts
           + routeMounts
           + hybrid service bridge
           + quickjs_ui runtime mounts
```

- `sharedMounts` 同时提供给 Core 与 UI，例如连接同一个 Session 后端的 scoped KV；
- `serviceMounts` 只提供给 Core，例如完整网络、认证和数据处理能力；
- `uiMounts` 只提供给 JSUI，例如剪贴板、文件选择和页面交互能力；
- `routeMounts` 在 `QuickjsExtensionView.route()` 创建具体页面时补充，例如只有扫码登录页获得相机能力；
- hybrid service bridge 默认绑定当前 Session 的 Core，不接收任意 pluginId，也不把 Core 的全部底层能力暴露给 UI。

manifest 权限声明不等于实际注入。宿主授权后才可进入相应 runtime 的有效 mounts。

## 5. KV 存储边界

核心提供可被 JS 调用的 `QuickjsKeyValueStore`，默认实现使用
`SharedPreferencesAsync`。混合插件 Manager 按照插件 ID 绑定 namespace，Core 与 JSUI
使用同一个插件命名空间；宿主可以替换具体 Store。

宿主负责：

- 可信插件 ID 与命名空间绑定；
- 跨插件访问隔离；
- 持久化、并发一致性和底层安全；
- 日志中不泄露 KV value；
- 容量限制以及卸载、清除数据策略。

插件负责：

- key 和 value 的业务结构；
- Cookie、Token、账号及中间流程状态的保存；
- 认证过期、刷新与注销清理；
- 哪些数据构成有效认证状态。

宿主不解析或限制插件具体保存什么。JS API 不接收插件 ID，例如：

```js
await storage.get('session');
await storage.set('session', value);
await storage.remove('session');
await storage.containsKey('session');
await storage.keys();
await storage.clear();
```

不提供以下形式：

```js
// 禁止由 JS 选择其他插件的命名空间。
await storage.get('other.plugin', 'session');
```

## 6. 安装包与 manifest 方向

建议一个物理安装包同时携带 service、UI modules 和资源：

```text
manifest.json
service/
  main.mjs
ui/
  authentication.mjs
  verification.mjs
assets/
  icon.png
```

来源加载统一收敛到 `QuickjsExtensionPackage`。开发期支持以 `manifest.json`
为入口从 asset、file 或 network 目录递归加载相对模块；生产分发支持
asset ZIP、file ZIP、network ZIP 和内存 ZIP 字节。来源层完成后统一交给
`QuickjsExtension.load(...)`，安装、Session 和调用层不区分物理来源。

讨论阶段的 manifest 示例：

```json
{
  "schemaVersion": 2,
  "id": "site.example1",
  "name": "站点1",
  "description": "提供站点1的数据查询和认证能力",
  "version": "1.0.0",
  "versionCode": 10000,
  "compatibilityCode": "lemon-content-source-v1",
  "icon": "assets/icon.png",
  "homepage": "https://example.com",
  "updateUrl": "https://example.com/plugin/manifest.json",
  "downloadUrl": "https://example.com/plugin/site.example1.zip",
  "service": {
    "entry": "service/main.mjs",
    "contract": "content-source/v1",
    "publicExports": ["getHome", "search", "getDetail"],
    "uiExports": ["submitLogin", "sendCode"]
  },
  "ui": {
    "routes": {
      "authentication": {
        "entry": "ui/authentication.mjs",
        "title": "登录站点1"
      }
    }
  },
  "flows": {
    "authentication": {
      "route": "authentication"
    }
  },
  "capabilities": {
    "required": {"network": 1},
    "optional": {"cookieJar": 1}
  },
  "permissions": ["network", "storage"]
}
```

当前统一 Extension manifest 使用 `schemaVersion: 2`。职责划分：

- `id` 是不可变的插件唯一标识；
- `name` 是展示给用户的插件名称；
- `description` 是插件用途的简短说明；统一 Extension manifest 中必须提供且不能为空；
- `version` 是安装、更新、降级和兼容判断使用的插件版本号，建议采用 SemVer；
- `versionCode` 是非负整数形式的内部版本序号，用于确定更新先后，发布新版本时必须递增；
- `compatibilityCode` 表示宿主兼容分组，并关联必需/可选公开方法策略；
- `capabilities.required/optional` 分别声明宿主能力最低版本；必需能力缺失时拒绝安装，
  可选能力缺失时允许安装并向宿主报告；
- `icon` 可以是插件包内相对资源路径或绝对 HTTPS 网络地址；推荐随 ZIP 分发，网络图标作为兼容选择；
- `homepage` 是插件介绍、帮助或项目主页；
- `updateUrl` 是宿主检查最新版本信息的地址；
- `downloadUrl` 是当前版本或更新版本安装包的下载地址；
- `service` 描述程序调用入口和数据协议；
- `ui.routes` 描述 JSUI 页面；
- `flows` 描述宿主可以启动的自定义交互流程；
- route 默认绑定同一个混合插件中的 service；
- 第一版优先支持一个 service，不提前引入跨包或多 service 依赖。

统一 Extension 格式必须包含 manifest，不支持把裸 `.mjs` 当作 Extension 自动推断。
`description` 属于统一安装、权限确认和插件管理页面需要的基本信息，因此与 `id`、`name`、
`version` 一样作为必填字段，而不是放在可选 `metadata` 中。

`version` 用于向用户展示，不要求宿主仅依赖其文本进行排序；`versionCode` 用于机器比较，
新包的 `versionCode` 大于已安装值才视为升级，等于时视为同一构建，小于时视为降级并默认
拒绝。`versionCode` 不代表接口版本，接口兼容仍由 `compatibilityCode` 判断。

`id` 在同一宿主安装空间内全局唯一。普通 `install` 遇到已经存在的 ID 必须拒绝，不能
隐式覆盖；只有显式 `update(installedId, package)` 可以替换现有安装项。更新包必须满足：

- manifest `id` 与目标已安装 ID 完全一致；
- `versionCode` 默认必须大于已安装值；
- `compatibilityCode` 必须与当前安装项及宿主策略兼容；
- 包必须重新通过 manifest、接口、权限、资源和完整性校验；
- 更新失败时继续使用原安装包和安装记录；
- 显示名称 `name` 可以变化，不参与唯一性和所有权判断。

以下完整所有权校验属于后期安全优化，不阻塞第一阶段功能发布。仅比较 ID 不能阻止恶意作者制作同 ID 的安装包。完整的所有权校验需要在首次安装时记录
签名公钥或签名者指纹，后续更新必须由同一密钥签名。未实现签名之前，宿主应将更新限制
为原安装来源、宿主可信目录或用户明确确认的本地包；即使 `updateUrl` 相同，也仍需防范
域名失陷和内容被替换。

URL 字段使用绝对 HTTPS 地址。`homepage` 可以仅用于展示或跳转；`updateUrl` 返回的更新
描述应至少包含插件 ID、版本、下载地址以及后续引入的摘要/签名信息；`downloadUrl` 必须
下载完整的统一插件包，不能指向单独的 Core 或 JSUI 文件。通过 asset/file 安装的插件
可以不声明更新和下载地址，由宿主应用自己的插件目录或更新源管理。

这些地址全部来自不可信插件数据。宿主不得自动打开主页或无条件下载更新，应执行协议、
域名、重定向、文件大小和权限策略检查。网络 `icon` 同样只允许 HTTPS，必须应用独立的
图片 MIME、尺寸、响应体大小、缓存和超时限制；加载失败时使用系统默认图标，不能影响
插件安装、恢复或启动。`compatibilityCode`、主页、图标和下载地址都不能替代签名与内容
摘要。

混合插件不一定提供 JSUI 主页。默认用户入口仍可以是宿主通用原生页面，JSUI 只在认证等流程中出现。插件自定义的可视入口必须指向 JSUI route；Core entry 是程序调用入口，不是页面入口。

## 7. 安装与注册

建议安装过程以整个混合包为事务边界：

```text
读取并校验统一 manifest
          ↓
校验模块、资源、权限与兼容版本
          ↓
创建 InstalledQuickjsExtension 与 QuickjsExtensionSession
          ├── 有 service：注册 Core 数据插件
          ├── 有 ui：注册 JSUI bundle/routes
          └── 有 flows：注册宿主交互入口
```

概念模型：

```dart
final class InstalledQuickjsExtension {
  final QuickjsExtensionManifest manifest;
  final QuickjsExtensionSession session;
  final QuickjsPlugin? servicePlugin;
  final QuickjsUiBundle? uiBundle;
}
```

宿主可以提供两个查询视图，但不保存两套独立插件状态：

- `ServiceRegistry`：按 contract 查询可供原生页面遍历的 Core service；
- `InteractionFlowRegistry`：按 `pluginId + flowId` 查询 JSUI 交互入口。

二者都指向同一个 `InstalledQuickjsExtension` 和 `QuickjsExtensionSession`。

## 8. 标准数据调用

所有站点 Core 实现相同版本的数据协议，例如 `content-source/v1`。宿主只遍历已安装、启用且实现该 contract 的插件：

```text
原生页面
  ↓ 查询 content-source/v1
ServiceRegistry
  ├── site.example1 Core
  ├── site.example2 Core
  └── site.example3 Core
```

标准成功响应示例：

```json
{
  "status": "ok",
  "data": {
    "items": [
      {
        "id": "123",
        "title": "内容标题",
        "cover": "https://example.com/cover.jpg",
        "summary": "简介"
      }
    ],
    "nextCursor": "page-2"
  }
}
```

宿主模型必须附加来源插件 ID。宿主中的内容标识是 `(pluginId, remoteId)`，不能只使用站点返回的 `id`。

聚合加载时，某个来源需要认证或失败不应阻塞其他来源。宿主按来源维护 `loading`、`ready`、`interactionRequired`、`error`、`disabled` 等状态，先展示已经成功返回的数据。

## 9. 认证与自定义交互调用链

Core 不直接打开 UI。当数据调用需要登录或额外交互时，返回标准结果：

```json
{
  "status": "interactionRequired",
  "interaction": {
    "flow": "authentication",
    "reason": "sessionExpired"
  }
}
```

宿主处理流程：

```text
调用指定站点 Core
        ↓
返回 interactionRequired
        ↓
按 pluginId + flow 查找 JSUI route
        ↓
打开该插件的认证 JSUI
        ↓
JSUI 调用同一 Session 的 Core 并写入同一插件 KV
        ↓
JSUI 返回 completed / cancelled
        ↓
completed：宿主重试原 Core 调用一次
cancelled：保留该来源的未认证状态
```

重试必须有上限。认证流程完成后如果 Core 仍返回 `interactionRequired`，宿主应报告错误，不能循环打开页面。

在聚合页面中，不建议多个来源同时自动弹出登录页。需要认证的来源显示对应状态和操作入口，由用户选择登录哪个站点；认证成功后只刷新该来源。用户主动执行且必须认证的操作，可以直接启动对应 flow。

## 10. JSUI 与 Core 的连接

JSUI 的实时渲染数据传递与 Core 调用是两条不同通道：

```text
宿主 -> initialProps / setState -> JSUI 渲染
JSUI -> bound service bridge -> Core 业务调用
JSUI -> navigation.pop -> 宿主流程结果
```

`initialProps` 适合传入主题、语言、认证原因和当前操作上下文。用户提交账号、发送验证码或轮询扫码结果时，JSUI 通过绑定的 service bridge 主动调用 Core。

推荐由 Session 持有 Core runtime，JSUI Context 通过 bridge 调用：

```text
QuickjsExtensionSession
├── Core runtime/context
├── scoped KV
└── service bridge
        ↑
   JSUI Context
```

JS 调用形式可以是：

```js
const result = await pluginService.call('submitLogin', form);
```

`pluginService` 已绑定当前 Session，不接收 pluginId。宿主通用原生页面与登录 JSUI 因而使用同一个 Core 实例；UI Context 销毁不会重新定义 Core 生命周期。

`publicExports` 属于宿主理解的标准数据契约；`uiExports` 只供同插件 UI 使用，参数结构由插件自行定义。宿主负责访问控制和转发，不理解具体登录字段。

## 11. 宿主保留的能力

“业务 UI 插件化”不等于宿主完全没有原生壳层。宿主仍负责：

- 通用数据列表、详情、搜索和统一状态页面；
- 插件安装、升级、停用、卸载和恢复；
- 权限确认、网络策略和安全边界；
- KV 隔离及底层持久化；
- JSUI 加载、错误、崩溃和超时兜底；
- route 白名单和导航策略；
- 插件 UI 无法启动时的管理与清除数据入口。

## 12. 当前尚未实现的大功能

以下是相对于本设计的主要缺口，并不表示现有 Core 或 quickjs_ui 没有基础实现。

### 12.1 统一的混合插件包与 manifest（基础模型已开始实现）

`lemon_js_extensions` 已提供统一 manifest、service/UI/flow 描述、`.js/.ui/.hybrid`
构造和一致性校验，并支持 asset、file、network 目录以及 ZIP 物理包加载。
目前尚缺少签名、资源完整性校验和兼容版本策略。该能力保持在独立包中，
不修改 `lemon_js` 使其反向依赖 lemon_js_ui。

### 12.2 安装管理和持久化注册表（第一版已实现）

已提供 `QuickjsExtensionInstaller`、`InstalledQuickjsExtension` 和
`QuickjsExtensionRegistry`，支持注册、停用、启用、卸载以及按 contract/flow
查询。现已增加统一的 `QuickjsExtensionManager`，负责：

- 从 asset、file、network、ZIP 等来源安装，并将来源归一化为受管理的安装包；
- 查看全部安装项以及 enabled、disabled、broken 等状态；
- 启用、停用、卸载，并明确卸载时是否保留插件隔离 KV；
- 更新和失败回滚；显式降级和版本兼容策略仍待补充；
- 持久化插件 ID、版本、权限授权、启用状态、manifest 和模块源码；
- App 重启后读取安装记录并恢复 Registry，但不提前启动 Core runtime；
- 包丢失或损坏时只标记对应插件为 broken，不阻塞其他插件恢复。

Session、QuickJS runtime 和 JSUI Context 不持久化。恢复时重新读取受管理安装包并创建
Session，Core runtime 仍在首次调用时懒加载。Manager 默认自动选择平台 Store：原生
平台在应用支持目录使用文件 Store，Web 使用 SharedPreferences Web 后端；宿主仍可显式
替换为自定义 Store。当前本地文件 Store 使用临时文件和备份文件替换持久化记录；后续可
进一步保存不可变 ZIP 并增加摘要校验。

统一包现已将 manifest 声明的非 JavaScript 资源字节一并持久化；ZIP 内的非 JavaScript
文件会自动收集。恢复时这些资源被重建为 JSUI 可使用的内嵌资源，不再依赖原安装来源。
安装前同时检查内存、Registry 和持久化 Store，避免尚未执行 `restore()` 时覆盖同 ID
记录；更新继续要求 ID 和兼容码一致，并按 `versionCode` 控制升级、同版和降级。

manifest 可通过 `storageVersion` 描述插件 KV 结构版本。版本变化时，Manager 在激活新
版本前调用 `service.storageMigrationExport`，参数为旧版本和新版本；迁移前完整快照当前
插件命名空间，迁移或激活失败时恢复 KV 与旧安装记录。纯 UI 插件若需要改变 KV 结构，
应在混合包中提供迁移 service，或保持原 `storageVersion`。

### 12.3 QuickjsExtensionSession 生命周期与资源边界（第一版已实现）

已提供宿主级 Session，统一绑定插件身份、Core runtime、JSUI routes、KV、权限和 host
mounts。Core runtime 首次调用时创建并保持到停用或卸载；UI 页面销毁不影响 Session。
权限声明和授权不触发能力创建。Manager 通过明确的可选能力配置统一提供网络、存储和
加密默认实现；宿主可以关闭或替换，并可继续追加 `sharedMounts`、`serviceMounts` 和
`uiMounts`。
Core 调用使用有界串行队列和默认超时，停用/卸载会关闭 Runtime；故障 Runtime 清理后由下次
调用惰性重建，失败业务调用不会自动重放。升级过程中的页面与调用迁移仍待补充。

后续能力注入改造必须区分两层：Runtime、模块、生命周期、错误桥接等核心能力始终注入，
不参与权限控制；宿主可选能力由统一配置决定是否提供，不再根据权限声明临时创建 mount。
第一版默认提供的可选能力为 `storage`、`network` 和 `crypto`；`network` 默认直接注入
随 `lemon_js_extensions` 发布的 Axios，并同时提供 Fetch/XHR。默认权限策略为完全宽松，
宿主可以替换或关闭任一可选能力。`crypto` 默认启用 `QuickjsWebCryptoMount` 当前已经实现的
全部能力，包括 `randomUUID()`、`getRandomValues()`、SHA-1/256/384/512 digest，以及
HMAC-SHA-1/256 的 key import、sign 和 verify；不为尚未实现的算法声明能力。

manifest 权限只表达插件可能使用的受限能力。宿主可选择不限制、询问或禁用；能力缺失与
权限拒绝必须分别返回结构化结果。安装预检应向宿主报告插件声明但当前未实现的能力，运行时
调用缺失能力也必须返回明确错误，不能静默降级或依赖 `ReferenceError` 表达宿主兼容性。

### 12.4 Core 与 JSUI 的绑定 service bridge（第一版已实现）

已提供 `lemon_js_extensions/plugin_service` 模块，根据当前 Session 自动绑定 Core，仅允许
调用 manifest 的 `uiExports`，且不接受 pluginId。底层 provider 取消会向调用链传播，
默认超时、队列上限、手动重启和故障 Runtime 惰性恢复已经由 Session 统一处理。手动重启
会丢弃 Runtime 内存状态，并在下一次调用时重新创建 Runtime、执行插件 `init()`。

### 12.5 标准数据源 contract 与结果模型

需要正式定义 `content-source/v1` 的方法集合、请求参数、分页、统一数据结构、错误模型以及 `(pluginId, remoteId)` 来源标识。宿主遍历逻辑只能依赖版本化 contract，不能依赖任意 exports。

### 12.6 标准交互结果与 FlowRunner（基础版本已实现）

已定义 `interactionRequired`、`completed/cancelled/failed` 基础结果，并实现宿主侧 `FlowRunner` 串联 Core 调用与 JSUI route；交互完成后只重试一次。页面关闭与业务超时由宿主提供的 flow launcher 决定。

### 12.7 多来源聚合调度与原生页面状态

需要实现按 contract 枚举多个站点、并发限制、局部成功、来源级加载/认证/错误状态、用户触发认证和认证后局部刷新。不能让一个未登录或故障站点阻塞整个原生聚合页面。

### 12.8 manifest route 信息的完整传递与自动注册

quickjs_ui manifest 已经能够解析 `routes`，但 bundle 加载和宿主入口发现尚未形成完整链路。需要保证 route、名称、metadata 等安装信息在解析后仍可用于注册，并能根据已安装插件自动构建受控 route，而不是全部由 Dart 页面手工声明。

### 12.9 KV 并发和卸载策略的正式契约

现有插件隔离 KV 的方向可以保留，但需要明确 Core 与 JSUI 并发访问、原子更新或串行保证、容量限制、敏感值日志保护，以及升级、卸载、重新安装和“清除插件数据”的行为。

### 12.10 权限、兼容性和故障隔离

manifest 中声明权限不等于授权。需要将声明、用户授权与实际注入 capability 对齐，并定义 Core/JSUI 协议版本不兼容、模块损坏、Core 崩溃、JSUI 启动失败和插件超时时的隔离及恢复行为。

### 12.11 按插件 ID 调用与多实现选择

同一个 contract 可以安装多个实现，例如三个站点同时实现 `content-source/v1`。Flutter
宿主必须能够通过插件 ID 精确调用：

```dart
await manager.call(
  pluginId: 'site.example1',
  method: 'getHome',
  arguments: const [],
);
```

调用与选择规则：

- Flutter 宿主可以指定任意已安装、已启用且已授权插件的 ID 调用 `publicExports`；
- 宿主可以按 contract 枚举多个插件，逐个或受控并发调用并保留来源 ID；
- 未指定插件 ID 且 contract 只有一个实现时可以便捷调用；存在多个实现时必须报歧义错误，不能随机选择；
- Flow 使用 `pluginId + flowId` 精确定位，认证完成后只重试原插件调用；
- JSUI 只能通过当前 Session 的绑定 bridge 调用 `uiExports`，不接收 pluginId，禁止跨插件调用；
- Core 不可主动调用 UI，只能返回 `interactionRequired`，由 Flutter 宿主决定是否打开对应 route。

### 12.12 简化的兼容码与不饱和接口校验（已实现）

第一阶段不引入完整的参数和返回值 Schema 系统，而是在统一 manifest 增加
`compatibilityCode`，由宿主注册对应的兼容策略。该字段只表示插件声称兼容某一套宿主
接口，不是签名或安全校验，不能用于证明来源可信或防止包被篡改。

```json
{
  "compatibilityCode": "lemon-content-source-v1",
  "service": {
    "publicExports": ["getPluginInfo", "search"]
  }
}
```

宿主策略同时声明必需和可选公开方法：

```dart
QuickjsExtensionCompatibilityPolicy(
  compatibilityCode: 'lemon-content-source-v1',
  requiredPublicExports: const {'getPluginInfo'},
  optionalPublicExports: const {
    'getHome',
    'search',
    'getDetail',
    'getCategories',
  },
)
```

安装、更新和重启恢复时执行相同校验：

- `compatibilityCode` 必须存在，并与宿主注册的策略精确匹配；
- 必须存在 Core service；
- `requiredPublicExports` 必须全部声明并真实导出为函数；
- 插件允许不饱和实现，可只选择部分 `optionalPublicExports`；
- manifest 中声明的 `publicExports` 必须属于必需或可选方法集合；
- manifest 声明的方法必须由入口模块真实导出为函数；
- 插件内部辅助函数以及未写入 manifest 的额外导出不参与兼容性校验，也不能由宿主调用；
- 不匹配的安装和更新在写入 Store 前拒绝；重启恢复时不匹配的旧插件标记为 `broken`；
- Manager 已提供 `supports(pluginId, method)`，并允许按 contract 和 method 筛选实现者。

示例结果：

```text
getPluginInfo + search       -> 允许安装
getPluginInfo + getHome      -> 允许安装
只有 search                  -> 拒绝，缺少必需方法
getPluginInfo + unknownApi   -> 拒绝，声明了未知公开接口
```

`uiExports` 第一版仍作为插件 UI 与自身 Core 之间的私有契约，只校验 manifest 声明的方法
真实存在，不纳入宿主公共接口白名单。若以后出现需要统一的登录 UI 协议，再单独为其增加策略。

### 12.13 插件展示与更新元数据（基础字段和更新流程已实现）

将 `name`、`version`、`versionCode` 以及新增的 `icon`、`homepage`、`updateUrl`、
`downloadUrl` 作为统一
manifest 的正式字段，不继续放在无约束的 `metadata` 中。安装记录保存安装时解析出的元数据，
插件列表无需启动 Core runtime 即可展示名称、图标、版本、主页和更新状态。

计划补充：

- 包内及 HTTPS 网络图标读取、缓存、MIME/尺寸限制和失败时的系统默认图标；
- `versionCode` 整数比较、重复版本识别和禁止默认降级；`version` 仅作为展示版本；
- 更新描述模型，校验其插件 ID 与当前安装项一致；
- `updateUrl` 检查更新并解析目标版本、下载地址、摘要和发行说明；
- `downloadUrl` 下载后仍走临时包解析、兼容码、公开接口、权限和完整性校验；
- 网络失败、无更新和更新包损坏不改变当前已安装版本；
- 宿主可以覆盖或禁用插件自带更新地址，统一使用自己的可信插件目录。

更新身份校验分为两层：第一阶段使用当前 Manager 已有的重复 ID 安装拒绝和更新目标 ID
一致性检查；后期安全优化再补充 `versionCode`、兼容码、原始来源绑定、摘要与签名者指纹
校验。只有签名者一致才能
从安全意义上防止第三方使用相同 ID 覆盖原插件。

### 12.14 Service 运行模式与后台限制（记录，暂不实现）

存在 Core service 的插件后续需要声明期望的运行模式，但 manifest 只能提出请求，最终由
宿主平台能力、宿主策略和用户授权共同决定。纯 UI 插件没有 service，不涉及 Core 后台
运行；JSUI Context 在页面关闭时正常销毁。

计划中的结构：

```json
{
  "service": {
    "entry": "service/main.mjs",
    "runtime": {
      "mode": "onDemand",
      "idleTimeoutSeconds": 300,
      "background": false
    }
  }
}
```

运行模式语义：

- `onDemand`：默认模式，首次调用时创建，空闲达到宿主允许的时间后可以回收；
- `resident`：首次调用后仅在 App 前台生命周期内常驻，进入后台时宿主仍可暂停或销毁；
- `background`：表示插件需要受控后台任务，不代表允许无限循环或无限期常驻。

不允许插件仅依靠 `setInterval` 等方式自行获得后台常驻能力。真正的后台工作应声明有限的
任务 ID、导出方法和建议执行条件，由宿主调度一次性调用，并应用超时、取消、并发、电量、
网络和平台后台限制。插件停用、卸载或更新时必须取消对应任务。

```text
插件声明的运行模式
        ∩
宿主允许的运行模式
        ∩
用户授予的后台权限
        =
实际运行能力
```

当前 `QuickjsExtensionSession` 在 Core 首次调用后保持到停用、卸载、Manager 释放或进程
结束，行为接近 `resident`。本阶段不改变现有行为，也不增加 runtime manifest 字段、空闲
回收器或后台调度 API；待有真实后台任务场景后再实现，并优先将默认模式收敛为
`onDemand`。

### 12.15 现有 Core、JSUI 与统一扩展包兼容（已实现）

`lemon_js_extensions` 是上层组合和管理能力，不替代原有 `lemon_js` Core 插件或
`lemon_js_ui` 页面包。三种格式继续各自存在，并由 Manager 在安装入口显式选择输入格式：

```dart
enum QuickjsExtensionPackageFormat {
  extension,
  core,
  ui,
}
```

建议保留 `QuickjsExtensionPackageFormat` 这个名称，不使用 `ExtensionType`。原因是现有
`QuickjsExtensionKind.js/ui/hybrid` 已表示加载完成后实际包含的能力类型，而这里表示安装
来源的物理包格式。分开命名可避免把“输入格式”和“派生能力形态”混为一谈。

Manager 安装入口默认使用统一扩展格式：

```dart
await manager.installAssetZip(
  assetKey: 'assets/plugins/site.zip',
  format: QuickjsExtensionPackageFormat.extension,
);
```

`format` 默认值为 `extension`，旧格式必须显式指定：

```dart
await manager.installAssetZip(
  assetKey: 'assets/plugins/legacy_core.zip',
  format: QuickjsExtensionPackageFormat.core,
);

await manager.installAssetZip(
  assetKey: 'assets/plugins/legacy_ui.zip',
  format: QuickjsExtensionPackageFormat.ui,
);
```

格式职责：

- `extension`：读取统一 Extension manifest，可派生为 Core-only、UI-only 或 hybrid；
- `core`：使用现有 `QuickjsZipPlugin`/`QuickjsPlugin` 规则读取旧 Core 插件，再由显式适配信息包装为 Core-only Extension；
- `ui`：使用现有 `QuickjsUiBundle` 包格式读取旧 JSUI 包，再由显式适配信息包装为 UI-only Extension；
- 不根据 ZIP 内文件进行模糊猜测，避免多个 `manifest.json` 或相似目录导致错误识别；
- 原 Core 和 JSUI API 继续可以绕过 Manager 单独使用，缺少统一 manifest 或兼容码不会破坏原加载方式；
- 旧插件进入 Manager 时需要宿主提供统一管理所缺少的 ID、展示元数据、兼容码、默认 route 或 contract 等适配信息；
- 只有能够持久化包内容和适配信息的安装项才能在 App 重启后自动恢复。

三种格式的入口规则明确如下：

| PackageFormat | 统一 manifest | 裸 `main.mjs` | 多文件相对导入 | asset/file/network 递归 |
|---|---:|---:|---:|---:|
| `extension` | 必须 | 不支持 | 支持 | 支持 |
| `core` | 可选 | 支持 | 支持 | 支持 |
| `ui` | 可选 | 支持 | 支持 | 支持 |

`core` 和 `ui` 裸文件模式都以显式传入的 `main.mjs` 为入口，递归解析相对模块与资源：

```text
main.mjs
├── import './modules/api.mjs'
├── import './components/card.mjs'
└── 引用 ./assets/icon.png
```

asset、file 和 network 使用相同的插件根边界，递归路径不能通过 `..`、绝对路径、重定向
或 URL 变形逃出根目录。裸文件没有统一 manifest，因此 Manager 安装时必须显式提供适配
信息：

- Core 裸文件：插件 ID、名称、描述、版本、contract、`publicExports`、`uiExports` 和权限；
- UI 裸文件：插件 ID、名称、描述、版本、默认 route、权限和需要重新注入的第三方 UI 插件；
- Manager 将入口源码、递归 JavaScript 模块、JSUI 资源引用和这些适配信息一起持久化，
  保证 App 重启后可以恢复；
- 不扫描 JavaScript 源码猜测 exports、contract、插件 ID 或权限。

裸 Core/UI 兼容模式是对旧基础插件的显式包装，不改变它们独立于 Manager 使用时的原有
API。需要混合 Core 与 UI、统一更新或完整展示元数据时，应制作带 manifest 的
`extension` 包。

协议版本继续各管各的：

```text
Extension schemaVersion
        ├── 管理统一 manifest 结构
Core contract / compatibilityCode
        ├── 管理宿主公共接口兼容
JSUI runtime protocol version
        └── 管理页面渲染协议兼容
```

Manager 只负责协调并汇总校验结果，不用 Extension 的版本字段替代 Core 或 JSUI 自己的
协议版本，也不要求底层两个包反向依赖 `lemon_js_extensions`。

## 13. 后续待讨论问题

前四阶段完成后，仍留待后续阶段处理的问题如下：

- 内存压力下是否需要提供显式的 Core runtime 空闲回收策略；默认是首次使用后常驻；
- 一个混合包是否允许多个 service；
- 是否允许 UI 声明对其他插件 service 的依赖；第一版建议禁止；
- KV 是否需要 compare-and-set/事务，还是由 Session 保证串行；
- 插件升级时正在运行的 Core 调用和 JSUI 页面如何迁移；
- 插件签名、摘要、来源信任、ID 抢占防护、远程目录与自动更新策略；
- 权限声明、用户授权确认和后台执行限制；
- 可选 Cookie Jar：默认继续由 JS 手动读取、保存和发送 Cookie，不作为 Core 或混合插件
  的必需能力；后续如实现，以可空 `cookieJar` 注入，并按插件 ID 隔离。单次请求预计用
  `credentials: include` 启用自动发送和保存，用 `credentials: omit` 完全绕过 Jar，满足
  同一接口在登录态与匿名态之间切换；Web 仍遵循浏览器的 CORS、SameSite 和第三方
  Cookie 限制；
- 标准数据 contract 的具体字段与版本演进规则。

## 14. 建议实施顺序

1. 已完成 `QuickjsExtensionInstallRecord`、持久化 Store 接口和本地文件 Store。
2. 已完成 `QuickjsExtensionManager.restore()`、损坏隔离和懒加载 Session。
3. 已完成 asset、file、network、ZIP 统一加载，以及安装、更新回滚和可恢复卸载流程。
4. 已完成 `install/update/uninstall/list/enable/disable` 管理 API。
5. 已完成按 `pluginId` 调用、按 contract 枚举及多实现歧义检查。
6. 已完成 manifest schema 与 `compatibilityCode` 校验、必需/可选公开方法策略、
   `supports()` 与按方法筛选。
7. 已完成图标、主页、更新地址、下载地址、数字 `versionCode` 比较和更新描述模型。
8. 后续接入签名、摘要、来源绑定、ID 抢占防护、自动更新策略和更完整的权限模型。
9. 有真实场景后再实现 Service `onDemand/resident/background` 策略和受控后台任务调度。
10. 已完成 `QuickjsExtensionPackageFormat`，适配旧 Core ZIP、JSUI Package 和裸入口；
    默认仍为统一 Extension 格式。
11. 默认 Store 不满足业务需求时，由宿主提供自定义持久化适配。

插件管理页面属于宿主业务层，不列入 `lemon_js_extensions` 的开发计划；核心包只提供页面
所需的无 UI 管理 API 和状态数据。
