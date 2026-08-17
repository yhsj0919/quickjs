# QuickJS Runtime / Context 架构

## 目标

核心运行时正从“一套 `JSRuntime` + 一个 `JSContext`”迁移为“一个长生命周期
`JSRuntime` 包含多个短生命周期 Context”。动态 UI 页面和插件因此无需重建原生
Worker 及整个 QuickJS 运行时即可加载。

现有 `JsEngine.create()`、`eval()`、`loadFeatures()` 和 `dispose()` 继续作为独立引擎 API，
内部使用默认 Context。

## 所有权

```text
JsRuntime
├─ native worker
├─ JSRuntime
├─ memory and stack limits
├─ interrupt handler
├─ shared Promise job queue
├─ runtime-scoped host capabilities
└─ JsContext registry
   ├─ default context used by JsEngine
   ├─ dynamic page context
   └─ plugin context
```

每个 `JsContext` 独立拥有：

- 自己的 `JSContext` 和全局对象；
- ES 模块实例与 CommonJS 缓存；
- Context 级回调和 method；
- 定时器、流及待处理异步任务；
- 已加载的插件实例；
- 与该 Context 关联的源码/模块名称。

Runtime 负责内存限制、取消基础设施及 QuickJS 待处理任务队列。Context 必须先于其
Runtime 释放。

## 公共 API 目标

```dart
final runtime = await JsRuntime.create();

final context = await runtime.createContext(
  features: [applicationFeatures, pageFeatures],
);

final plugin = await context.loadPlugin(dynamicPlugin);
final result = await plugin.call('mount', [props]);

await context.dispose();
await runtime.dispose();
```

兼容 API 保持不变：

```dart
final engine = await JsEngine.create();
final value = await engine.eval('1 + 2');
await engine.dispose();
```

## 动态 UI 加载

页面发布包不是 Runtime features。资源加载和 Context 创建可以并行，之后在新 Context
中求值模块图：

```text
load asset/network bundle ─┐
                           ├─ load modules into page context
create page context ───────┘
                                    ↓
                              mount state / commit
                                    ↓
                              Flutter first frame
```

这样可消除页面加载期间由 `JsEngine.loadFeatures()` 导致的 Runtime 重建。

## 作用域规则

Runtime 级 features 不可变且由所有 Context 共享；Context features 只加载到单个 Context，
并在其释放时消失。动态页面模块始终属于某个 Context。

可变值不得跨越 Context 边界。Runtime 可以缓存模块源码和可选编译字节码，但模块实例、
全局对象、回调、句柄及待处理 Promise 必须保留在 Context 内。

## 迁移顺序

1. 增加原生 Context 创建、注册及确定性释放。
2. 按 `contextId` 路由原生 Worker 请求。
3. 将定时器、回调、流、异步任务和模块状态迁移到 Context。
4. 增加 Dart `JsRuntime` 与 `JsContext` API。
5. 实现不依赖 `JsEngine.loadFeatures()` 的 Context 内插件加载。
6. 让现有 `JsEngine` 类委托给默认 Context。
7. 将 `quickjs_ui` Session 切换到动态 Context。
8. 增加原生端和 Web 端的隔离、释放及性能测试。

## 实现状态

- 已实现原生 `JsContext` 的创建、注册和确定性释放。
- 原生 Worker 命令可通过数值 `contextId` 创建、求值及释放额外 Context。
- 同级 Context 之间的同步全局求值、ES 模块源码表、模块实例和全局对象互相隔离。
- 已提供 `JsRuntime.create()` 与 `runtime.createContext()` 生命周期 API，支持同步
  和 ES 模块求值。原生 Context 共享同一个 Worker/`JSRuntime`；其他后端目前通过
  隔离 Runtime 的兜底实现保持语义一致。
- 宿主回调、待处理 Promise、定时器及异步求值均按 Context 隔离；所属 Context
  释放后，迟到的 Dart 响应会被丢弃，剩余 interval/timeout 会被释放。
- 宿主回调返回的 Dart 异步流及 JavaScript-to-Dart sink 归 Context 所有；释放 Context
  会取消或关闭其流 Session，不影响同级 Context。
- `createContext()` 的直接参数通过 Context 适配器复用高层安装器来加载 features、method、
  模块及插件；同级 facade 的原生回调 ID 会重新映射，不会重建 Runtime。
- `context.loadFeatures()` 和 `context.loadPlugin()` 直接增量安装到现有 Context，已有全局对象
  及同级 Context 保持不变；兼容接口 `JsEngine.loadFeatures()` 仍会重建独立 Runtime。
- `JsUiRuntime` 现在拥有应用级核心 Runtime，并为每个 `JsUiSession` 租用新
  Context。动态 asset/file/network 发布包仍是页面输入，初始化 Runtime 无需页面清单。
- 生成的 quickjs_ui 页面适配器暴露 `bootstrap(props)`：首次加载在本地校验清单，
  然后通过一次 Worker/QuickJS 调用获取能力、页面生命周期状态并提交初始 Schema，从而减少
  三个调度边界且不改变页面作者的 `Page(...)` API。没有 `bootstrap` 的自定义运行时
  插件继续使用 v1 `capabilities` / `mount` / `commit` 流程。

## 不变量

- 释放一个 Context 不得停止同级 Context。
- 已释放 Context 不得再接收回调、流或 Promise 结果。
- 页面不得观察其他页面的全局对象或模块状态。
- Runtime 释放时必须在 `JS_FreeRuntime` 前释放所有 Context。
- Context 插件加载不得调用会重建 Runtime 的 `loadFeatures()`。
