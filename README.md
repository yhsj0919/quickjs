# quickjs

Flutter 插件，集成 [QuickJS](https://github.com/quickjs-ng/quickjs)，覆盖
native FFI 与 Flutter Web WASM。

| 平台 | 实现 |
| --- | --- |
| Android / iOS / macOS / Linux / Windows | FFI + QuickJS 源码编译 |
| Web | `quickjs-wasi` WASM + Web Worker bridge |

## 使用

```dart
import 'package:quickjs/quickjs.dart';

Future<void> main() async {
  final engine = await Quickjs.create();
  try {
    print(engine.quickjsVersion);
    print(engine.state); // QuickjsRuntimeState.ready
    print(await engine.eval('1 + 2 * 3')); // 7
    print(await engine.eval('"hello"'));
  } finally {
    await engine.dispose();
  }
}
```

### 结构化返回

`eval()` 和 `evaluate()` 继续返回字符串，保持兼容。需要 Dart 值时使用
`evaluateValue()`；当前已覆盖 `number`、`boolean`、`string`、`null`、
`undefined`、`bigint`、array、plain object、`ArrayBuffer` 和 `Uint8Array`。
循环引用、symbol、function 等不可直接转换的值会抛出
`JsValueConversionException`，避免 `JSON.stringify` 静默丢失数据。

```dart
print(await engine.evaluateValue('1 + 2')); // 3
print(await engine.evaluateValue('true')); // true
print(await engine.evaluateValue('null')); // null
print(await engine.evaluateValue('undefined')); // JsUndefined.value
print(await engine.evaluateValue('9007199254740993n')); // BigInt
print(await engine.evaluateValue('new Uint8Array([1, 2, 255])')); // Uint8List
print(await engine.evaluateValue('[1, "two"]')); // [1, two]
print(await engine.evaluateValue('({ ok: true })')); // {ok: true}
print(await engine.evaluateValue(
  'count + price',
  globals: {'count': 40, 'price': 2.5},
)); // 42.5
```

`globals` 支持临时注入 `int`、`double`、`bool`、`String`、`null`、`Uint8List`、
`List`、`Map<String, Object?>` 和 `DateTime`。注入值只在本次执行期间写入
`globalThis`，执行结束后会恢复原有全局状态。

### 异步 callback 与事件循环

`Quickjs.create(onConsole:)` 可以接收 JS `console.log`、`console.warn` 和
`console.error` 事件。不传 `onConsole` 时仍会注入 no-op `console`，依赖 `console`
的脚本不会因为 `console is not defined` 失败，也不会默认写宿主日志。

```dart
final engine = await Quickjs.create(
  onConsole: (event) {
    print('[${event.level.name}] ${event.text}');
  },
);
```

`bind()` 可以把 Dart 函数注入到 JS `globalThis`。JS 侧调用后得到 Promise；
Dart 返回值会 resolve，Dart 抛错会 reject。callback 参数和返回值复用结构化值编解码，
支持 JSON-compatible 值以及 `Uint8List` / `Uint8Array`。

```dart
await engine.bind('addFromDart', (args) {
  return (args[0] as num) + (args[1] as num);
});

print(await engine.evalAsync('''
const value = await addFromDart(20, 22);
return value;
''')); // 42
```

runtime 内置 `setTimeout`、`clearTimeout`、`setInterval`、`clearInterval`，并对齐
native / web 的 Promise job pump。长同步 JS 仍符合 JS 单线程语义：它会阻塞同 runtime
后续 timer、Promise job 和 eval，但不会阻塞 Flutter UI isolate 或浏览器 UI thread。

`bindSink()` 用于 JS 多次向 Dart 推送增量数据；每次 `await sink.emit(value)` 会等待
Dart 侧确认，避免 worker message 队列无界增长。

```dart
final stream = await engine.bindSink('progress');
final sub = stream.listen(print);

await engine.evalAsync('''
for (let i = 1; i <= 3; i++) {
  await progress.emit(i);
}
progress.close();
''');

await sub.cancel();
```

### Module 与 asset

`evalModule()` 支持 ES module parse / evaluate、静态 import 依赖加载、相对路径解析和
runtime 级 module cache。依赖通过 `QuickjsRuntimeOptions.moduleLoader` 按规范化后的
module name 加载；Flutter asset 可用 `quickjsAssetModuleLoader()`。

```dart
final engine = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    moduleLoader: (name) {
      return {
        'math.mjs': 'export const answer = 42;',
      }[name];
    },
  ),
);

await engine.evalModule('''
import { answer } from "./math.mjs";
globalThis.answer = answer;
''', name: 'main.mjs');
print(await engine.eval('globalThis.answer')); // 42
```

### 宿主能力批量挂载

`QuickjsHostMount` 用一个有名称的能力包组合 environment patch、ES module 和
Promise-based host provider。可在创建 runtime 时通过 `QuickjsRuntimeOptions.mounts`
安装，也可在运行时通过 `Quickjs.mount()` 安装；运行时安装会重建 runtime，因此原有
JS global 状态不会保留，已声明的初始化 mounts 会自动恢复。

```dart
final engine = await Quickjs.create(
  options: const QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount(
        name: 'app-base',
        environmentPatches: <QuickjsHostScript>[
          QuickjsHostScript(
            name: 'mount:app-base.js',
            source: 'globalThis.appVersion = "1.0";',
          ),
        ],
      ),
    ],
  ),
);

await engine.mount(
  QuickjsHostMount(
    name: 'app-api',
    providers: <QuickjsHostProvider>[
      QuickjsHostProvider.async(
        name: 'app.double',
        callback: (args, _) => (args.single! as num) * 2,
      ),
    ],
    environmentPatches: const <QuickjsHostScript>[
      QuickjsHostScript(
        name: 'mount:app-api.js',
        source: '''
globalThis.app = {
  double(value) {
    return globalThis.__quickjsHostProviders['app.double'](value);
  },
};
''',
      ),
    ],
  ),
);

print(await engine.evalAsync('return await app.double(21);')); // 42
```

同名 runtime mount 默认会被拒绝；需要替换时显式传入
`QuickjsHostMountConflictPolicy.replace`。`debugInspect()` 的
`registeredMounts`、`registeredProviders` 可用于检查安装结果。

最小 CommonJS 兼容层通过 `evalCommonJs()` / `evaluateCommonJs()` 提供，覆盖
`require()`、`module.exports`、`exports`、相对路径解析和 runtime 级 CommonJS module
cache。插件不内置完整 npm resolver；npm 包建议用 esbuild / Rollup / webpack 预打包。
完整策略和可运行示例见 [`docs/npm_bundling.md`](docs/npm_bundling.md)。

`QuickjsFetchMount` 可显式安装最小 Fetch API。必须声明允许访问的 origin：

```dart
final engine = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: [
      QuickjsFetchMount(
        allowedOrigins: {'https://api.example.com'},
      ),
    ],
  ),
);

final result = await engine.evalAsync('''
const response = await fetch('https://api.example.com/data');
return JSON.stringify(await response.json());
''');
```

Native 底层使用 `HttpClient`，Web 底层使用浏览器原生 `fetch`。Web 请求仍受 CORS
限制。支持 `Request` / `Response` / `Headers` / `AbortController` / `FormData` /
`URLSearchParams` / `Blob` / `XMLHttpRequest`，以及 `redirect: follow | manual | error`
（默认 `follow`，可配置 `maxRedirects`）。请求体支持 string / ArrayBuffer / Uint8Array /
FormData / URLSearchParams；Response 支持 `text()`、`json()`、`arrayBuffer()`、`blob()`、
`bytes()`、`clone()` 等。

### Function handle

`evaluateHandle()` / `evalHandle()` 可以把 JS function 保留在所属 runtime 内，并在 Dart
侧重复调用。Dart 侧只保存 handle id；handle 不能跨 runtime 混用，runtime dispose 后
调用会返回 closed error。

```dart
final add = await engine.evaluateHandle('(a, b) => a + b');
try {
  print(await add.call([1, 2])); // 3
} finally {
  await add.dispose();
}
```

`call()` 保留同步 interrupt 语义，适合可能长时间同步运行的 JS；`callAsync()` 会等待
Promise-returning function，timeout 覆盖 Promise pending 阶段。若函数在返回 Promise
前执行长同步任务，应使用 `call()`。

### Dart object proxy 与 class binding

`bindObject()` 可以把显式描述的 Dart object proxy 暴露给 JS。属性是只读 enumerable
property；getter 在 JS 侧返回 Promise；setter 通过 callback 派发，但 JS assignment
表达式无法 await setter Promise，这是 JS accessor 语义限制。

```dart
final user = await engine.bindObject(
  'user',
  QuickjsObjectProxy(
    properties: {'name': 'Tom'},
    methods: {
      'hello': (args) => 'hello ${args[0]}',
    },
  ),
);

try {
  print(await engine.evalAsync('return await user.hello(user.name);'));
} finally {
  await user.dispose();
}
```

`bindClass<T>()` 可以注册可由 JS `new` 构造的 Dart class。JS constructor 同步返回
instance proxy；Dart constructor 通过 Promise callback bridge 执行，instance getter 和
method 会等待构造完成后再访问 Dart 实例。

```dart
final userClass = await engine.bindClass<User>(
  'User',
  QuickjsClass<User>(
    constructor: (args) => User(args[0] as String),
    accessors: {
      'name': QuickjsInstanceAccessor<User>(
        get: (user) => user.name,
      ),
    },
    methods: {
      'hello': (user, args) => 'hello ${user.name}',
    },
  ),
);

try {
  print(await engine.evalAsync('''
const user = new User("Tom");
return await user.hello();
'''));
} finally {
  await userClass.dispose();
}
```

当前 class binding 不承诺由 JS GC 驱动 Dart instance 回收；支持的清理路径是显式
`QuickjsClassHandle.dispose()`、`Quickjs.dispose()` 或 runtime stop/rebuild。更多生命周期
约束见 `docs/class_binding_lifecycle.md`。

### 资源限制

`QuickjsRuntimeOptions.memoryLimitBytes` 的单位是字节，限制作用于单个
`Quickjs` 实例底层的 runtime。`null` 表示使用 QuickJS 默认限制；执行中超过限制时，
Dart 侧会抛出 `JsOutOfMemoryException`。

`QuickjsRuntimeOptions.stackLimitBytes` 的单位也是字节，例如 `64 * 1024`
表示 64 KiB。native 侧基于 QuickJS `JS_SetMaxStackSize`，递归栈溢出会映射为
`JsStackOverflowException`。Flutter Web 当前底层 `quickjs-wasi` 没有暴露等价
stack limit 选项，因此该参数暂不影响 Web runtime。

```dart
final engine = await Quickjs.create(
  options: const QuickjsRuntimeOptions(
    memoryLimitBytes: 16 * 1024 * 1024, // 16 MiB
    stackLimitBytes: 64 * 1024, // 64 KiB, native only for now
  ),
);

try {
  await engine.eval('new Array(1000000).fill("quickjs").join("")');
} on JsOutOfMemoryException catch (error) {
  print(error.message);
} finally {
  await engine.dispose();
}
```

## 当前状态

项目已经完成执行安全、runtime 隔离、结构化值转换、Promise callback、timer、流式
callback、ES module / CommonJS、function handle、Dart object proxy、第一版 class
binding、调试基础能力和宿主能力挂载。下一阶段按 `ROADMAP.md` 进入 0.10.0 JS 插件入口
与模块包。

### 已完成

- [x] 公开 API 已异步化：`Quickjs.create()`、`eval()`、`evaluate()`、`stop()`、
  `dispose()` 均返回 Future。
- [x] native 执行迁移到 Dart isolate worker；Web 执行迁移到 Web Worker。
- [x] 同一个 `Quickjs` 实例内的 eval 请求按 FIFO 队列串行执行。
- [x] 长耗时 JavaScript 不阻塞 Dart isolate / Flutter UI / 浏览器 UI thread。
- [x] `stop()`、`timeout`、`dispose()` 和 worker crash 都有稳定错误语义与测试覆盖。
- [x] `QuickjsRuntimeState` 与 `engine.state` 已公开，可观测 ready、running、
  stopping、closed、failed 等生命周期状态。
- [x] `QuickjsRuntimeOptions` 已支持单 runtime memory limit；native 支持 stack limit。
- [x] 多 runtime 的基础 global 状态、dispose、callback、timer、module cache、handle
  所有权等边界已按当前功能切片隔离。
- [x] 已有基础异常类型：`JsException`、`JsValueConversionException`、
  `JsTimeoutException`、`JsCancelledException`、`JsRuntimeClosedException`、
  `JsRuntimeCrashException`、`JsOutOfMemoryException`、`JsStackOverflowException`。
- [x] JS exception 已结构化为 `JsException.message/name/stack/fileName/line/column`；
  eval 场景下 location 字段按 native / web 底层能力 nullable 暴露。
- [x] `evaluateValue()` 与 `globals` 已覆盖基础 JS / Dart 值互转。
- [x] Promise-based `bind()`、`evalAsync()`、timer/event-loop、stream callback 已实现。
- [x] `evalModule()`、runtime 级 module loader、Flutter asset loader 和最小 CommonJS
  兼容层已实现。
- [x] `evaluateHandle()`、`QuickjsFunctionHandle.call()` / `callAsync()` / `dispose()` /
  `cancel()` 已实现。
- [x] `bindObject()`、`QuickjsObjectProxy`、`QuickjsObjectAccessor` 与显式 object handle
  dispose 已实现。
- [x] `bindClass<T>()`、`QuickjsClass<T>`、`QuickjsInstanceAccessor<T>` 与显式 class
  handle dispose 已实现；instance finalizer 延后。
- [x] `Quickjs.create(onConsole:)` 已支持 `console.log` / `console.warn` /
  `console.error` 事件；未配置 sink 时默认 no-op。
- [x] `QuickjsRuntimeOptions.mounts` 与 `Quickjs.mount()` 支持批量安装 environment patch、
  module 和 provider，并支持冲突检查、同名 runtime mount 替换与 runtime 重建恢复。
- [x] example 已覆盖 basic eval、async API、runtime worker、queue/reentry、runtime
  isolation、exception model、resource limit、structured values、callback bridge、
  timer/event-loop、stream callback、module、host module、host mount、function handle、
  object proxy、class binding、console、Web host environment 和 Web Crypto。

### 部分完成

- [~] `timeout`：native 使用 QuickJS interrupt handler；web 在无法中断同步 WASM 时通过
  terminate worker / 重建 runtime 兜底。Web timeout / stop 后 JS global 状态会随 Worker
  重建而丢失。
- [~] `stop()`：已能取消当前 eval 与队列 eval，并在后台重建 runtime；公开
  `cancel(requestId)` 尚未实现。
- [~] runtime 状态机：ready / running / stopping / closed / failed 的可观察转换已有测试；
  `creating` 阶段的实际可观测创建流程仍待补。
- [~] stack limit：native 已支持；Web 等价能力等待底层 `quickjs-wasi` 暴露。
- [~] `evalAsync`：native / web 已支持 async 函数体语义；top-level await 待补。

### 后续计划

- [ ] source file name、sourcemap registry、stack remap。
- [ ] debug mode / inspector 原型：globals、modules、memory、pending jobs、
  registered callbacks、手动执行表达式。
- [~] host capability / 生态兼容能力：`fetch` 已通过 `QuickjsFetchMount` 提供；
  `crypto`、`Buffer`、浏览器兼容对象、Node 兼容对象等可选注入仍在推进。
- [x] npm bundle 支持文档、可构建 esbuild 示例和生成资产的 native/Web 自动化测试。

## 验证

日常开发优先运行定向测试。脚本会把完整输出写入 `build/verification-logs`，成功时仅
输出阶段、耗时和结果，失败时输出日志末尾，避免 CI 或编码代理上下文被重复日志占满：

```powershell
.\tool\verify.cmd -TestPath test\quickjs_consistency_test.dart -PlainName "test name"
.\tool\verify.cmd -TestPath test\quickjs_consistency_test.dart -PlainName "test name" -Web
.\tool\verify.cmd -Mode full
```

Windows FFI 相关代码变更后，需要重建 example，确保测试进程加载的是最新
`quickjs.dll`：

```powershell
cd example
flutter build windows --debug
flutter build windows
```

## 更新 QuickJS（原生）

```powershell
.\tool\update_quickjs.ps1 v0.15.1
```

## 更新 Web WASM 资源

```powershell
.\tool\fetch_web_assets.ps1 -Version 3.0.1
```

脚本先下载到临时目录，使用 unpkg metadata 中的 SHA-256 SRI 校验每个文件，
再检查 WASM header 和 `version.js`。全部通过后才替换 `assets/web` 中的依赖资源；
下载、校验或替换失败时保留原有资产。

## Web 调试

如果 Flutter Web 初始化失败，在 Chrome 开发者工具 (F12) 的 Console /
Network 中检查：

1. `quickjs_web.js` / `quickjs_bridge.mjs` / `quickjs.wasm` 是否 404。
2. 是否有 ES module / MIME 相关错误。
3. 是否有 Web Worker 初始化错误。

然后重试：

```bash
cd example
flutter clean
flutter pub get
flutter run -d chrome
```

## 结构

- `lib/quickjs.dart`：公开 package 入口。
- `lib/src/runtime/quickjs.dart`：`Quickjs` 实现、请求队列、callback / handle / proxy 入口。
- `lib/src/runtime/quickjs_runtime_options.dart`：资源限制与 module loader 配置。
- `lib/src/module/quickjs_asset_module_loader.dart`：Flutter `AssetBundle` module loader helper。
- `lib/src/native/`：native FFI backend 与 Dart isolate worker。
- `lib/src/web/`：Flutter Web backend 与 JS interop loader。
- `native/`：C FFI bridge。
- `assets/web/`：Web Worker、WASM bridge 与 quickjs-wasi 资源。
- `third_party/quickjs`：QuickJS 源码。
- `docs/`：补充设计与生命周期文档。
- `example/`：手动 smoke test app 与 example 页面。
