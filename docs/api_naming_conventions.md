# lemon_js API 命名语义

本文档是 `lemon_js` 公开 API 的命名约束。新增能力或重构 API 时必须遵守，避免同一数据方向使用多套动词，或把脚本、模块、插件和基础功能混为一类。

## 包级前缀

公开 Dart API 按所属抽象层统一命名：

| 包或边界 | 前缀 | 示例 |
| --- | --- | --- |
| `lemon_js` 核心抽象 | `Js*` | `JsEngine`、`JsFeatures`、`JsPlugin` |
| `lemon_js_ui` UI 抽象 | `JsUi*` | `JsUiView`、`JsUiSession`、`JsUiBundle` |
| `lemon_js_extensions` 扩展系统 | `JsExtension*` | `JsExtensionManager`、`JsExtensionManifest` |
| QuickJS 原生或 Web backend 实现 | `Js*` | `JsBindings`、`JsBackend` |

用户可调用的跨平台抽象不得使用 `Quickjs*`，因为它描述的是 Lemon JS 能力而不是具体执行后端。
只有与 QuickJS ABI、FFI、Web host、backend runtime 或 wire protocol 直接绑定的内部实现可以保留
`Quickjs*`。Flutter 自动发现使用的 Web 插件注册类也使用项目统一名称 `JsWeb`。

Dart 和 JavaScript/TypeScript 中的 UI 标识符统一使用 `JsUi*` / `jsUi*`。包名、文件名、
模块 specifier 和协议标识仍保持 `quickjs_ui`，例如 `import ... from 'quickjs_ui'` 和
`quickjs_ui.runtime.v1`；这些是稳定的包与协议身份，不属于类型前缀。

扩展系统统一使用 `JsExtension*`。不得重新引入 `QuickjsExtension*`、
`QuickjsServiceComponent`、`QuickjsUiComponent` 等旧类型，也不为其提供兼容别名。

## 方向动词

### `inject*`：Dart → JavaScript

把 Dart 提供的值或行为放入 JavaScript 环境：

- `injectFunction`：注入 Dart 回调。
- `injectObject`：注入 Dart 对象代理。
- `injectClass`：注入可由 JavaScript 构造的 Dart 类。
- `injectStream`：注入可由 JavaScript 异步迭代的 Dart stream。

只要内容来源于 Dart、目标是 JavaScript 全局环境，公开方法统一使用 `inject`，不得使用 `bind`。

### `bind*`：JavaScript → Dart

在 Dart 侧取得并持有 JavaScript 中的能力或输出：

- `bindFunction`：把 JavaScript 函数保存为 Dart `JsFunctionHandle`。
- `bindStream`：建立 JavaScript `{emit, close, error}` 输出通道，并在 Dart 侧取得 `Stream`。

`bind` 表示 Dart 与既有 JavaScript 内容建立持续关系，不用于 Dart 内容注入。

### `call*`：按名称或句柄调用

- `call` / `callRaw`：调用 JavaScript 全局函数。
- `callModule`：调用模块导出函数。
- 句柄上的 `call` / `callRaw`：调用已经绑定的 JavaScript 函数。

### `eval*` 与 `run*`：执行源代码

- `eval` / `evalRaw`：执行普通 JavaScript 表达式或脚本，不包装异步函数体。
- `run` / `runRaw`：执行异步函数体，可直接使用 `return` 和 `await`。
- `Raw` 后缀表示返回底层 bridge 字符串；无 `Raw` 后缀表示转换为 Dart 值。

### `load*`：加载可安装内容

- `loadFeatures`：加载一组基础功能；独立 runtime 可能因此重建。
- `loadPlugin`：加载具有清单和生命周期的插件。

`load` 不表示 Dart/JavaScript 的数据方向，而表示把可安装内容加入运行环境。

### `create*`：创建生命周期实体

- `JsEngine.create`：创建单一运行引擎。
- `JsRuntime.create`：创建可容纳多个 context 的 runtime。
- `createContext`：创建隔离 context。

## 创建内容类型

创建 runtime 或 context 时，各字段必须与内容类型一一对应：

| 字段 | 类型 | 语义 |
| --- | --- | --- |
| `scripts` | `JsScript` | 创建时按顺序直接执行的启动脚本 |
| `modules` | `JsModule` | 可通过 `import` 或 `require` 加载的模块 |
| `methods` | `JsHostMethod` | 创建时注入并在重建后恢复的 Dart/Flutter 宿主方法 |
| `features` | `JsFeatures` | 由脚本、模块、宿主方法和低层能力组成的完整功能包 |
| `plugins` | `JsPlugin` | 具有 manifest、入口和生命周期的插件；随 Engine 或 Context 创建时加载 |

补全标准环境的 polyfill 当前仍使用 `JsScript` 表达，并放在 `scripts` 或 `JsFeatures.scripts` 中。以后如果增加 `JsPolyfill`，它必须只表示“补全缺失的标准 API”，不得代替任意启动脚本。

## `JsFeatures` 的边界

`JsFeatures` 表示一组可整体启用、校验、替换和恢复的基础功能，不表示单段代码。它可以包含全局环境能力、启动脚本或 polyfill、模块以及 Dart 宿主方法。

现有预设和独立功能统一使用 `Features`：

- `WebFeatures()`
- `EssentialFeatures()`
- `NodeFeatures()`
- `FetchFeatures`
- `AxiosFeatures`
- `WebSocketFeatures`
- `WebCryptoFeatures`
- `StorageFeatures`

浏览器全局开关直接由 `JsFeatures.browserGlobals` 表达。不得再增加与 `JsFeatures` 并列的 capability 容器。

## 禁止重新引入的旧命名

以下公开名称已经废弃且不保留兼容别名：

```text
Quickjs
MemoryJsKvStore
SharedPreferencesJsKvStore
StoredJsExtension
InMemoryJsExtensionStore
ManagedJsExtensionState
ManagedJsExtension
InstalledJsExtension
evalModule()
evalCommonJs()
JsModule.specifier
JsPluginModule.specifier
assetKey
JsProvider
registeredProviders
providerDetails
JsScript.providerGlobals()
eval/run globals
callModule 的旧 `name` 参数（现为 `module`）
JsMount
mounts
mount()
environmentPatches
JsMountConflictPolicy
registeredMounts
FetchMount
AxiosMount
WebSocketMount
WebCryptoMount
StorageMount
JsPluginMount
JsCapabilities
hostCapabilities
bindObject
bindClass
bindStreamSink
receiveStream
```

## `mount` 的保留范围

`mount` 不再用于描述基础功能、脚本或宿主 API 的加载；这些场景统一使用
`features` / `loadFeatures()`。

JSUI 的 `mount`、`onMount` 仍然保留，因为它们描述的是页面或组件的渲染生命周期，
与运行时功能加载不是同一语义。

对应的新名称是 `JsFeatures`、`features`、`loadFeatures()`、`scripts`、各类 `*Features`、`injectObject`、`injectClass` 和 `bindStream`。

## 新 API 命名检查

新增公开 API 前依次判断：

1. 内容从 Dart 进入 JavaScript：使用 `inject*`。
2. Dart 获取 JavaScript 内容或输出：使用 `bind*`。
3. 调用已有函数：使用 `call*`。
4. 执行源代码：使用 `eval*` 或 `run*`。
5. 安装功能包或插件：使用 `load*`。
6. 创建独立生命周期实体：使用 `create*`。
7. 创建参数名称必须与 `Script`、`Module`、`Method`、`Features`、`Plugin` 类型对应。
