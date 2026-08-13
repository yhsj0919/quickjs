# lemon_js 公开 API

公开 API 的方向动词、创建内容分类和废弃名称统一遵循
[API 命名语义](api_naming_conventions.md)。项目尚未稳定发布，重命名不保留旧别名。

## 创建与生命周期

- `Quickjs.create({options, moduleLoader, scripts, modules, providers, features, plugins, onConsole})`：创建单一独立引擎。
- `JsRuntime.create({JsOptions options})`：创建可容纳多个隔离 context 的 runtime。
- `JsRuntime.createContext({moduleLoader, scripts, modules, providers, features, plugins, onConsole})`：创建 `JsContext`。
- `restart()`：中止当前任务并重建底层 runtime。
- `dispose()`：永久释放引擎、runtime、context 或句柄。

`JsOptions`：

- `memoryLimitBytes`
- `stackLimitBytes`
- `maxPendingTasks`

创建入口的环境参数：

- `moduleLoader`
- `scripts`
- `modules`
- `providers`
- `features`
- `plugins`
- `onConsole`

## 执行与调用

- `eval(code, {timeout, name, globals})`：执行普通表达式或脚本并返回 Dart 值。
- `evalRaw(code, {timeout, name, globals})`：执行普通表达式或脚本并返回底层 bridge 字符串。
- `run(code, {timeout, name, globals})`：执行 async function body，可直接使用 `return` 和 `await`。
- `runRaw(code, {timeout, name, globals})`：执行 async function body 并返回底层 bridge 字符串。
- `call(method, args, {timeout})`：调用 `globalThis` 上的函数并返回 Dart 值。
- `callRaw(method, args, {timeout})`：调用全局函数并返回底层 bridge 字符串。
- `evalModule(source, {name, timeout})`：执行 ES module。
- `evalCommonJs(source, {name, timeout})`：执行 CommonJS 包装。
- `callModule(module, method, args, {timeout, name})`：调用模块导出函数。
- `bindFunction(code, {timeout, name})`：取得 `JsFunctionHandle`。
- `pumpTimers()`：执行到期的 timer/job 并返回下次调度时间。

`JsFunctionHandle` 提供：

- `call` / `callRaw`：普通函数调用。
- `run` / `runRaw`：等待函数返回的 Promise。
- `cancel()`：取消该句柄正在执行的任务。
- `dispose()`：释放句柄。

## Dart 与 JavaScript 桥接

Dart → JavaScript：

- `injectFunction(name, JsCallback callback)`
- `injectStream(name, stream)`
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
- `JsProvider`：Dart/Flutter 实现的底层宿主函数。
- `JsFeatures`：由全局别名、脚本、模块和 provider 组成的完整功能包。
- `loadFeatures(features, {conflictPolicy})`：在运行期间加载功能包。
- `JsFeaturesConflictPolicy.reject/replace`：冲突处理策略。

基础功能：

- `JsFeatures.web()`
- `JsFeatures.essential()`
- `JsFeatures.node()`
- `FetchFeatures`
- `AxiosFeatures`
- `WebSocketFeatures`
- `WebCryptoFeatures`
- `StorageFeatures`

辅助类型：

- `JsGlobals`
- `JsModuleLoader`
- `JsHttpSession`
- `JsKvStore`
- `MemoryJsKvStore`
- `SharedPreferencesJsKvStore`

## 插件

数据与加载：

- `JsPluginManifest`
- `JsPluginModule`
- `JsPlugin`
- `JsPluginFeatures`
- `JsPluginBundle`
- `JsZipPlugin`

运行方法：

- `loadPlugin`
- `validatePlugin`
- `initPlugin`
- `callPlugin`
- `invokePlugin`
- `disposePlugin`

客户端与工具：

- `JsPluginHost`
- `JsPluginClient`
- `JsToolRegistry`

`callPlugin` 与 `invokePlugin` 仍需单独审查是否合并；在结论确定前不得新增第三个同义入口。

## 错误与调试

- 根错误：`JsException`，通过 `kind: JsErrorKind` 分类。
- JS 抛错：`JsThrownException`。
- 框架错误：`JsValueConversionException`、`JsTimeoutException`、`JsCancelledException`、`JsQueueFullException`、`JsRuntimeClosedException`、`JsRuntimeCrashException`、`JsOutOfMemoryException`、`JsStackOverflowException`。
- 调试：`JsInspectorSnapshot`、`JsProviderDebugInfo`、`JsPluginDebugInfo`。
- Source map：`JsSourceMap`、`JsSourceLocation`。
- JS `undefined`：`JsUndefined.value`。
