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

混合插件采用独立基础包实现，不放入最底层的 `package:lemon_js`，也不作为 quickjs_ui 内部的附属功能。包名确定为 `quickjs_extensions`。

```text
业务宿主
    ↓
quickjs_extensions
├── 依赖 lemon_js
└── 依赖 lemon_js_ui
        ↓
lemon_js_ui -> lemon_js
```

依赖方向必须保持单向：

- `lemon_js` 只负责 JS runtime、模块、Core 插件、mount/provider 和底层生命周期，不依赖 lemon_js_ui 或 `quickjs_extensions`；
- lemon_js_ui 负责通用 JSUI 加载、渲染、事件、导航与页面生命周期，继续依赖 `lemon_js`，但不依赖 `quickjs_extensions`；
- `quickjs_extensions` 同时依赖 `lemon_js` 与 lemon_js_ui，提供二者的通用组合能力；
- 业务宿主可以直接使用 `lemon_js`、lemon_js_ui，也可以选择依赖 `quickjs_extensions`，由业务层解释登录、内容源、播放器等具体语义。

`quickjs_extensions` 是可选的插件系统与组合语法糖层。它不取代 `lemon_js` 和 `lemon_js_ui` 的独立使用方式。它负责：

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

后续的可选页面替换能力属于业务宿主：系统 UI 永远作为默认和兜底，业务层可以选择通用 JSUI 页面提供者，失败时回退系统 UI。通用 UI 插件自身仍有安装 ID，但不固定绑定某个站点 ID；运行时由业务层建立受限的页面 Session。该模型可以使用 `quickjs_extensions` 提供的包、UI route 和隔离基础设施，但页面插槽及回退规则不进入 `quickjs_extensions` 的通用协议。

### 3.2 统一公开命名与构造变体

`quickjs_extensions` 只公开一套主体命名，不为 JS、UI 和混合形态建立三套平行的 package、installer、session 或 installed 类型。

统一公开入口：

```dart
import 'package:quickjs_extensions/quickjs_extensions.dart';
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
// 不经过 quickjs_extensions，直接使用 Core 插件。
final plugin = QuickjsPlugin(...);

// 不经过 quickjs_extensions，直接使用 JSUI bundle。
final bundle = QuickjsUiBundle(...);
```

`quickjs_extensions` 必须通过 `lemon_js` 与 `lemon_js_ui` 的公开 API 完成组合，不要求简单使用者先包装成 `QuickjsExtension`，也不应让底层 API 依赖扩展系统。

### 3.3 View 命名与职责

现有 `QuickjsUiView` 保持原名和现有职责，不增加 `.js`、`.ui` 或 `.hybrid` 构造变体。它属于 quickjs_ui，只负责直接加载和渲染 JSUI 页面；现有 `.plugin`、`.asset`、`.file`、`.network` 描述页面来源，继续独立可用。

不采用以下 API：

```dart
QuickjsUiView.js(...)
QuickjsUiView.ui(...)
QuickjsUiView.hybrid(...)
QuickjsUiView.extension(...)
```

其中 `.js` 没有可渲染 UI，`.ui` 与类本身语义重复；`.hybrid`/`.extension` 会迫使 quickjs_ui 理解上层扩展系统，并造成 quickjs_ui 反向依赖 `quickjs_extensions`。

`quickjs_extensions` 新增 Session 感知的包装 View：

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
- 自动注入 scoped KV、已授权权限与宿主 mounts；
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

`package:quickjs_extensions/quickjs_extensions.dart` 作为扩展系统的统一导出入口，可以同时导出 `QuickjsExtension`、`QuickjsExtensionView` 等扩展 API，以及使用扩展 API 时必要的 `lemon_js`、`lemon_js_ui` 公共类型。直接依赖 `lemon_js_ui` 的使用者仍从其原入口使用 `QuickjsUiView`，不需要引入扩展包。

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

宿主提供可被 JS 调用的 KV 存储，并按照插件 ID 隔离。Core 与 JSUI 使用同一个插件命名空间。

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

讨论阶段的 manifest 示例：

```json
{
  "schemaVersion": 1,
  "id": "site.example1",
  "name": "站点1",
  "version": "1.0.0",
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
  "permissions": ["network", "storage"]
}
```

字段名称和最终 schemaVersion 尚未确定。当前确定的是职责划分：

- `service` 描述程序调用入口和数据协议；
- `ui.routes` 描述 JSUI 页面；
- `flows` 描述宿主可以启动的自定义交互流程；
- route 默认绑定同一个混合插件中的 service；
- 第一版优先支持一个 service，不提前引入跨包或多 service 依赖。

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

### 12.1 统一的混合插件包与 manifest

目前 Core 插件 manifest 与 lemon_js_ui package manifest 是两套平行契约。尚未有一个应用级 manifest 同时描述 service、UI routes、flows、统一权限和兼容版本，也没有对应的统一包加载器与校验器。该能力确定由独立的 `quickjs_extensions` 包承载，而不是修改 `lemon_js` 使其反向依赖 lemon_js_ui。

### 12.2 安装管理和持久化注册表

尚缺少混合包的原子安装、升级、停用、卸载、版本兼容检查，以及已安装插件记录的持久化管理。Core 与 UI 的注册目前不是由统一的 `InstalledQuickjsExtension` 聚合管理。

### 12.3 QuickjsExtensionSession 生命周期与资源边界

尚缺少正式的宿主级 Session 抽象，用来统一绑定插件身份、Core runtime、JSUI routes、KV、权限和 host capabilities，并定义启动、停用、页面销毁、runtime 崩溃、升级和卸载时的生命周期。

### 12.4 Core 与 JSUI 的绑定 service bridge

quickjs_ui 已支持注入 mounts，但尚缺少面向混合插件的受限 bridge：根据当前 Session 自动绑定 Core、区分标准公开能力与 UI 私有能力、阻止跨插件调用，并处理取消、超时和 Core runtime 不可用。

### 12.5 标准数据源 contract 与结果模型

需要正式定义 `content-source/v1` 的方法集合、请求参数、分页、统一数据结构、错误模型以及 `(pluginId, remoteId)` 来源标识。宿主遍历逻辑只能依赖版本化 contract，不能依赖任意 exports。

### 12.6 标准交互结果与 FlowRunner

需要定义 `interactionRequired`、flow 参数、`completed/cancelled/failed` 结果、一次重试上限、页面关闭和超时语义，并实现宿主侧 `FlowRunner` 将 Core 调用与 JSUI route 串联起来。

### 12.7 多来源聚合调度与原生页面状态

需要实现按 contract 枚举多个站点、并发限制、局部成功、来源级加载/认证/错误状态、用户触发认证和认证后局部刷新。不能让一个未登录或故障站点阻塞整个原生聚合页面。

### 12.8 manifest route 信息的完整传递与自动注册

quickjs_ui manifest 已经能够解析 `routes`，但 bundle 加载和宿主入口发现尚未形成完整链路。需要保证 route、名称、metadata 等安装信息在解析后仍可用于注册，并能根据已安装插件自动构建受控 route，而不是全部由 Dart 页面手工声明。

### 12.9 KV 并发和卸载策略的正式契约

现有插件隔离 KV 的方向可以保留，但需要明确 Core 与 JSUI 并发访问、原子更新或串行保证、容量限制、敏感值日志保护，以及升级、卸载、重新安装和“清除插件数据”的行为。

### 12.10 权限、兼容性和故障隔离

manifest 中声明权限不等于授权。需要将声明、用户授权与实际注入 capability 对齐，并定义 Core/JSUI 协议版本不兼容、模块损坏、Core 崩溃、JSUI 启动失败和插件超时时的隔离及恢复行为。

## 13. 后续待讨论问题

以下问题暂不在本文中定案：

- 最终 manifest 字段名、schemaVersion 和向旧 Core/JSUI 包的兼容策略；
- 内存压力下是否需要提供显式的 Core runtime 空闲回收策略；默认是首次使用后常驻；
- 一个混合包是否允许多个 service；
- 是否允许 UI 声明对其他插件 service 的依赖；第一版建议禁止；
- KV 是否需要 compare-and-set/事务，还是由 Session 保证串行；
- 插件升级时正在运行的 Core 调用和 JSUI 页面如何迁移；
- 插件签名、来源信任、远程目录与自动更新是否属于库层还是应用层；
- 标准数据 contract 的具体字段与版本演进规则。
