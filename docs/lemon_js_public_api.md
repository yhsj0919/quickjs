# lemon_js 公开 API

公开 API 的方向动词、创建内容分类和废弃名称统一遵循
[API 命名语义](api_naming_conventions.md)。项目尚未稳定发布，重命名不保留旧别名。

## 创建与生命周期

- `JsEngine.create({options, moduleLoader, scripts, modules, methods, features, plugins, onConsole})`：创建单一独立引擎。
- `JsRuntime.create({JsOptions options})`：创建可容纳多个隔离 context 的 runtime。
- `JsRuntime.createContext({moduleLoader, scripts, modules, methods, features, plugins, onConsole})`：创建 `JsContext`。
- `restart()`：中止当前任务并重建底层 runtime。
- `dispose()`：永久释放引擎、runtime、context 或句柄。

`JsOptions`：

- `memoryLimitBytes`
- `stackLimitBytes`
- `maxPendingTasks`

创建入口的环境参数：

- `moduleLoader`：ES 模块懒加载器；仅在 `import` 的模块未预先注册时按需获取源码，返回 `null` 表示模块不存在。
- `scripts`：创建或重建引擎时依次执行的全局环境脚本；使用 `JsScript` 提供内联源码，或使用 `JsScript.asset` 从 `path` 加载源码。
- `modules`
- `methods`：创建时注入并在重建后恢复的 Dart 宿主方法，元素类型为 `JsHostMethod`。
- `features`
- `plugins`
- `onConsole`：接收 `console.log`、`console.warn` 和 `console.error` 事件；支持同步或异步回调，未设置时不向 Dart 转发。

## 执行与调用

执行接口的 `name` 表示源码名称，用于错误堆栈、诊断信息和 source map 匹配；
模块接口中的 `name` 还作为根模块名称和相对导入解析基准。

执行接口的 `timeout` 从任务入队开始计算，包含排队和实际执行时间；异步接口还包含
等待 Promise 的时间。模块执行当前不把入队前的懒加载、源码读取和依赖图构建计入该时限。

- `eval(code, {timeout, name, tempGlobals})`：执行普通表达式或脚本并返回 Dart 值。
- `evalRaw(code, {timeout, name, tempGlobals})`：执行普通表达式或脚本并返回底层 bridge 字符串。
- `run(code, {timeout, name, tempGlobals})`：执行 async function body，可直接使用 `return` 和 `await`。
- `runRaw(code, {timeout, name, tempGlobals})`：执行 async function body 并返回底层 bridge 字符串。
- `call(method, args, {timeout})`：调用 `globalThis[method]` 并返回 Dart 值；`method` 是单个属性名，不解析嵌套路径。
- `callRaw(method, args, {timeout})`：调用 `globalThis[method]` 并返回底层 bridge 字符串；参数使用结构化值编码。
- `runModule(source, {name, timeout})`：执行 ES module。
- `runCommonJs(source, {name, timeout})`：执行 CommonJS 包装。
- `callModule(module, method, args, {timeout})`：调用已注册模块的导出函数；诊断名称根据模块名和方法名自动生成。
- `bindFunction(code, {timeout, name})`：取得 `JsFunctionHandle`。
- `pumpTimers()`：推进一次 JavaScript 事件循环，执行到期的 timer 和 Promise job，并返回距离下一个 timer 到期的时间；`null` 表示当前没有待调度的 timer。普通 `run`、`call` 请求无需手动调用，主要供 UI、服务容器等长期运行宿主在没有 JavaScript 请求时持续驱动定时任务。

`JsFunctionHandle` 提供：

- `call` / `callRaw`：普通函数调用。
- `run` / `runRaw`：等待函数返回的 Promise。
- `dispose()`：释放句柄。

## Dart 与 JavaScript 桥接

Dart → JavaScript：

- `injectFunction(name, JsCallback callback)`：临时注入返回 Promise 的 Dart 函数；同名注入替换并释放旧回调，`restart()` 后不恢复。
- `injectStream(name, stream)`：注入供 JavaScript 异步迭代的 Dart stream；不创建独立句柄，随当前 runtime/context 释放。
- `injectObject(name, JsObject<T> object)`
- `injectClass(name, JsClass<T> definition)`

JavaScript → Dart：

- `bindFunction(code, {timeout, name})`
- `bindStream(name)`

相关类型：

- `JsCallback`
- `JsValue`
- `JsAccessor<T>`
- `JsMethod<T>`
- `JsMembers<T>`
- `JsObject<T>`
- `JsClass<T>`
- `JsFunctionHandle`
- `JsObjectHandle`
- `JsClassHandle`

## 脚本、模块与基础功能

- `JsScript`：创建时执行的启动脚本。
- `JsModule`：ES Module 或 CommonJS 模块。
- `JsHostMethod`：Dart/Flutter 实现的底层宿主函数。
- `JsFeatures`：由全局别名、脚本、模块和宿主方法组成的完整功能包。
- `loadFeatures(features, {conflictPolicy})`：在运行期间加载功能包。
- `JsFeaturesConflictPolicy.reject/replace`：冲突处理策略。

基础功能：

- `WebFeatures()`
- `EssentialFeatures()`
- `NodeFeatures()`
- `FetchFeatures`
- `AxiosFeatures`
- `WebSocketFeatures`：当前仅原生平台支持，Flutter Web 构造时会抛出 `UnsupportedError`。
- `WebCryptoFeatures`
- `StorageFeatures`

辅助类型：

- `JsGlobals`
- `JsModuleLoader`
- `JsHttpSession`
- `JsKvStore`
- `JsMemoryKvStore`
- `JsSharedPreferencesKvStore`

## 插件

数据与加载：

- `JsPluginManifest`
- `JsPluginModule`
- `JsPlugin`
- `JsPlugin.manifestAsset(path:, modules:)`：从 manifest JSON asset 和模块 asset 映射创建插件。
- `JsPlugin.fromManifest(source:, modules:)`：从 manifest JSON 字符串和内联模块源码创建插件。
- `JsZipPlugin`

运行方法：

- `loadPlugin`
- `validatePlugin`
- `initPlugin`
- `callPlugin`
- `callPluginExport`
- `disposePlugin`

客户端与工具：

- `JsPluginHost`
- `JsPluginClient`
- `JsPluginRegistry`：注册插件并通过独立的 plugin ID 和方法名调用导出方法。

`callPluginExport(plugin, method, args)` 显式调用指定插件对象；`callPlugin(method, args, {pluginId})`
从当前已加载插件中按导出名和可选插件 ID 查找后调用。两者解析方式不同，均保留；不得新增第三个同义入口。

## 错误与调试

- 根错误：`JsException`，通过 `kind: JsErrorKind` 分类。
- JS 抛错：`JsThrownException`。
- 框架错误：`JsValueConversionException`、`JsTimeoutException`、`JsCancelledException`、`JsQueueFullException`、`JsRuntimeClosedException`、`JsRuntimeCrashException`、`JsOutOfMemoryException`、`JsStackOverflowException`。
- 调试：`JsInspectorSnapshot`、`JsHostMethodDebugInfo`、`JsPluginDebugInfo`。
- Source map：`JsSourceMap`、`JsSourceLocation`。
- JS `undefined`：`JsUndefined.value`。
