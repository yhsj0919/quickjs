# QuickJS 完整使用指南

本文介绍 `package:quickjs` 的主要能力：创建运行时、执行 JS、结构化值转换、模块加载、CommonJS、Dart 方法注入、对象和类绑定、host mount、fetch、Web Crypto、Node/Web 兼容、插件、调试、异常和生命周期。

示例默认使用：

```dart
import 'dart:async';
import 'dart:typed_data';

import 'package:quickjs/quickjs.dart';
```

## 1. 创建和释放运行时

最小用法：

```dart
final quickjs = await Quickjs.create();

try {
  final result = await quickjs.eval('1 + 2 * 3');
  print(result); // 7
} finally {
  await quickjs.dispose();
}
```

`Quickjs` 是一个独立运行时。页面退出、业务结束或不再使用时应调用 `dispose()`。

Flutter 页面中常见写法：

```dart
class MyPageState extends State<MyPage> {
  Quickjs? _quickjs;

  @override
  void initState() {
    super.initState();
    unawaited(_init());
  }

  Future<void> _init() async {
    _quickjs = await Quickjs.create();
  }

  @override
  void dispose() {
    unawaited(_quickjs?.dispose());
    super.dispose();
  }
}
```

## 2. 运行时配置

通过 `QuickjsRuntimeOptions` 配置运行时：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    memoryLimitBytes: 64 * 1024 * 1024,
    stackLimitBytes: 1024 * 1024,
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.web(),
    ],
  ),
  onConsole: (event) {
    print('[${event.level.name}] ${event.text}');
  },
);
```

常用字段：

- `memoryLimitBytes`：限制单个 runtime 内存。
- `stackLimitBytes`：限制 native 调用栈。
- `moduleLoader`：ES module 依赖加载器。
- `hostCapabilities`：基础 host 能力。
- `environmentPatches`：启动时注入的 JS 脚本。
- `modules`：预注册 ES module / CommonJS module。
- `providers`：Dart/Flutter 方法提供者。
- `mounts`：批量能力包，例如 Web、Node、fetch、crypto、plugin。

## 默认内置能力

即使不安装任何 mount，runtime 也会默认安装少量基础能力：

- `console.log` / `console.warn` / `console.error`
- `TextEncoder`
- `TextDecoder`

`TextEncoder` / `TextDecoder` 目前提供 UTF-8 编解码能力，适合配合 `crypto.subtle.digest()`、二进制协议、Buffer 类工具使用。

```dart
final text = await quickjs.evalAsync('''
const bytes = new TextEncoder().encode('hello');
return new TextDecoder().decode(bytes);
''');
```

## 3. 执行同步 JS

`eval()` 执行普通 JS，返回字符串结果：

```dart
final value = await quickjs.eval('1 + 2');
print(value); // 3
```

可以传入 `name`，用于错误堆栈和调试：

```dart
await quickjs.eval(
  'throw new Error("boom")',
  name: 'app:main.js',
);
```

可以传入 `timeout`，防止长时间同步执行：

```dart
await quickjs.eval(
  'while (true) {}',
  timeout: const Duration(milliseconds: 100),
);
```

## 4. 执行异步 JS

`evalAsync()` 会把代码包在 `async () => { ... }` 中执行，所以需要用 `return` 返回值：

```dart
final result = await quickjs.evalAsync('''
const value = await Promise.resolve(42);
return value;
''');

print(result); // 42
```

`evalAsync()` 适合调用 Promise、timer、fetch、Dart provider 等异步能力。

## 5. 返回 Dart 结构化值

`eval()` 和 `evalAsync()` 返回字符串。需要 Dart 原生值时，用 `evaluateValue()`：

```dart
final value = await quickjs.evaluateValue('''
({
  name: 'QuickJS',
  count: 3,
  ok: true,
  tags: ['js', 'dart'],
})
''');

print(value); // {name: QuickJS, count: 3, ok: true, tags: [js, dart]}
```

支持的常用类型：

- `null`
- `bool`
- `num`
- `String`
- `BigInt`
- `List`
- plain object -> `Map<String, Object?>`
- `ArrayBuffer`
- `Uint8Array` -> `Uint8List`
- `undefined` -> `JsUndefined.value`

示例：

```dart
final bytes = await quickjs.evaluateValue('new Uint8Array([1, 2, 255])');
print(bytes is Uint8List); // true
```

不支持直接转换的值会抛出 `JsValueConversionException`，例如 function、symbol、循环引用对象。

## 6. 临时注入 globals

执行某次 JS 时，可以临时把 Dart 值注入 `globalThis`：

```dart
final result = await quickjs.evaluateValue(
  'count + price',
  globals: <String, Object?>{
    'count': 40,
    'price': 2,
  },
);

print(result); // 42
```

这些 globals 只在本次执行期间存在，执行结束后会恢复原状态。

## 7. 接收 console 日志

创建 runtime 时传入 `onConsole`：

```dart
final quickjs = await Quickjs.create(
  onConsole: (event) {
    print('${event.timestamp} ${event.level.name}: ${event.text}');
  },
);

await quickjs.eval('console.log("hello", 123)');
```

支持：

- `console.log`
- `console.warn`
- `console.error`

## 8. 注入简单 Dart 方法

最简单的方式是创建 runtime 时使用 `QuickjsHostProvider.global()`：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    providers: <QuickjsHostProvider>[
      QuickjsHostProvider.global(
        name: 'getDataAsync',
        callback: (args, context) async {
          return 'data from Dart';
        },
      ),
      QuickjsHostProvider.global(
        name: 'dartMethod',
        callback: (args, context) {
          return 'method result';
        },
      ),
    ],
  ),
);
```

JS 调用：

```dart
final result = await quickjs.evaluateValue('''
const data = await getDataAsync();
const value = await dartMethod('hello');
({ data, value });
''');
```

注意：provider 在 JS 侧总是返回 Promise，所以建议始终使用 `await`。

## 9. 运行后绑定 Dart 方法

也可以在 runtime 创建后用 `bind()` 绑定全局函数：

```dart
await quickjs.bind('addFromDart', (args) {
  return (args[0] as num) + (args[1] as num);
});

final result = await quickjs.evalAsync('''
return await addFromDart(20, 22);
''');

print(result); // 42
```

`bind()` 适合少量临时绑定。更推荐在创建 runtime 时使用 `providers`，这样 runtime 重建时配置可以恢复。

## 10. Provider 高级写法

`QuickjsHostProvider.global()` 是语法糖：

```dart
QuickjsHostProvider.global(
  name: 'alert',
  callback: (args, _) {
    print(args.join(' '));
    return null;
  },
)
```

这里的 `name` 是 JS 侧全局函数名，内部 provider id 会自动生成。

需要自定义内部 provider 名时，用 `QuickjsHostProvider.dart()`：

```dart
QuickjsHostProvider.dart(
  name: 'example.getDataAsync',
  globalName: 'getDataAsync',
  callback: (args, _) async {
    return 'data from Dart';
  },
)
```

字段含义：

- `name`：内部 provider 名，用于映射、冲突检测、调试。
- `globalName`：可选，声明要自动注入的 JS 全局函数名。
- `debugName`：可选，调试显示名。
- `implementation`：标记实现来源，支持 `dart`、`platform`、`web`。
- `callback`：Dart 侧实现。

如果不传 `globalName`，provider 只注册到内部表，不会自动出现在 `globalThis`。

## 11. 使用 Host Script 注入 JS

`QuickjsHostScript` 用于启动时注入 JS 脚本，比如 polyfill、全局对象、兼容层。

```dart
final quickjs = await Quickjs.create(
  options: const QuickjsRuntimeOptions(
    environmentPatches: <QuickjsHostScript>[
      QuickjsHostScript.js(
        name: 'app:env.js',
        globals: <String>['appVersion'],
        source: 'globalThis.appVersion = "1.0.0";',
      ),
    ],
  ),
);
```

`globals` 用于声明脚本会安装哪些全局变量。运行时会用它做重复全局名检测。

## 12. 从 assets 加载 Host Script

不想手动 `rootBundle.loadString()` 时，使用 `QuickjsHostScript.asset()`：

```dart
final axiosScript = await QuickjsHostScript.asset(
  name: 'app:axios.js',
  assetKey: 'assets/js/axios.js',
  globals: const <String>['axios'],
);

final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    environmentPatches: <QuickjsHostScript>[
      axiosScript,
    ],
  ),
);
```

## 13. Provider 映射语法糖

如果你已经有多个 provider，并想集中声明全局函数映射，可以使用 `QuickjsHostScript.providerGlobals()`：

```dart
QuickjsHostScript.providerGlobals(
  name: 'app:globals.js',
  globals: const <String, String>{
    'getDataAsync': 'example.getDataAsync',
    'dartMethod': 'example.dartMethod',
  },
)
```

它会生成类似下面的 JS：

```js
globalThis.getDataAsync = (...args) =>
  globalThis.__quickjsHostProviders['example.getDataAsync'](...args);
```

简单函数推荐 `QuickjsHostProvider.global()`；需要集中管理映射或构建复杂 API 时再使用 `providerGlobals()`。

## 14. Host Mount 能力包

`QuickjsHostMount` 可以理解为“给 runtime 安装一整套 JS 运行环境能力”的包。它不是单纯执行一段 JS，也不是单纯注册一个 Dart 方法，而是把多个相关配置作为一个整体安装进去。

一个 mount 可以包含四类内容：

- `capabilities`：基础 host 能力，例如 `window` / `self` 这类别名。
- `environmentPatches`：启动时执行的 JS 补丁，例如安装 `fetch`、`crypto`、`Buffer`、`location`。
- `modules`：预注册模块，例如 `node:buffer`、`node:crypto`、插件 ES module。
- `providers`：Dart/Flutter 实现的方法，例如 fetch 请求、crypto digest、应用自定义 API。

换句话说，mount 是“能力边界”的组织单位。比如 `QuickjsFetchMount` 同时需要：

- 注入 JS 侧 `fetch` / `Headers` / `Response` 类。
- 注册 Dart 侧真正发 HTTP 请求的 provider。
- 保存允许访问的 origin、超时、大小限制等配置。

这些东西拆开写很容易漏，所以用一个 mount 表示“安装 fetch 能力”。

### Mount 和 JS 注入的区别

`QuickjsHostScript.js` 只是“启动时执行一段 JS”。它适合做很薄的环境补丁：

```dart
QuickjsHostScript.js(
  name: 'app:env.js',
  globals: const <String>['appVersion'],
  source: 'globalThis.appVersion = "1.0.0";',
)
```

这类脚本通常只负责：

- 写一个全局变量。
- 安装一个小 polyfill。
- 把已有 provider 包装成某个 JS API。
- 加载 axios 这类纯 JS 库。

但 JS 注入本身不适合表达“完整能力”。例如 fetch 能力不只是这段 JS：

```js
globalThis.fetch = ...
```

它还需要 Dart 侧 HTTP provider、origin 白名单、请求/响应大小限制、超时、重定向规则、`Headers` / `Request` / `Response` / `AbortController` 等配套对象。只用 `QuickjsHostScript.js` 会把这些配置拆散到多个地方，后续很难判断“这个 runtime 到底安装了什么能力”。

所以单独做 mount 的原因是：

- **组合能力**：把 JS patch、Dart provider、模块、capability 放在一个对象里。
- **明确边界**：`QuickjsFetchMount` 就代表 fetch 能力，`QuickjsWebCryptoMount` 就代表 crypto 能力。
- **集中配置**：网络白名单、超时、环境变量、crypto 开关都跟能力本身放在一起。
- **可复用**：同一个 mount 可以在多个 runtime 或页面中复用。
- **可检查**：运行时可以统一做 mount name、global、provider、module 冲突检测。
- **可调试**：`debugInspect()` 可以看到当前 runtime 安装了哪些 mount 和 provider。
- **可重建**：runtime `stop()` 或 `mount()` 重建后，mount 描述的能力可以自动恢复。

简单判断：

- 只注入一段独立 JS：用 `QuickjsHostScript.js`。
- 只暴露一个 Dart 全局函数：用 `QuickjsHostProvider.global`。
- 一组 JS API 需要配套 Dart 实现、模块或配置：做成 `QuickjsHostMount`。
- 想把能力作为产品级开关安装/卸载/复用：做成 `QuickjsHostMount`。

创建 runtime 时安装：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.web(),
      QuickjsHostMount.essential(globalBuffer: true),
      QuickjsFetchMount(
        allowedOrigins: <String>{'https://example.com'},
      ),
    ],
  ),
);
```

也可以自己定义 mount：

```dart
final appMount = QuickjsHostMount(
  name: 'app-api',
  environmentPatches: const <QuickjsHostScript>[
    QuickjsHostScript.js(
      name: 'app:env.js',
      globals: <String>['appName'],
      source: 'globalThis.appName = "Demo";',
    ),
  ],
  providers: <QuickjsHostProvider>[
    QuickjsHostProvider.global(
      name: 'ping',
      callback: (_, __) => 'pong',
    ),
  ],
  modules: const <QuickjsHostModule>[
    QuickjsHostModule.esModule(
      specifier: 'app/config',
      source: 'export const version = "1.0.0";',
    ),
  ],
);
```

安装：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[appMount],
  ),
);
```

JS 中可以使用 mount 提供的能力：

```js
console.log(appName);
console.log(await ping());
const { version } = await import('app/config');
```

运行时也可以安装 mount：

```dart
await quickjs.mount(appMount);
```

但要注意：运行时 `mount()` 会重建 runtime。重建后会重新安装 options 里的 mounts、providers、scripts、modules，以及运行时 mount；但 JS 执行期间临时写入的全局状态不会保留。因此：

- 核心环境能力建议在 `Quickjs.create()` 时通过 `options.mounts` 安装。
- 运行时 `mount()` 更适合“用户打开某个功能后再加载能力”的场景。
- 长期存在的能力不要依赖手动 `eval()` 注入，应该放进 mount 或 options。

mount 还负责冲突检测。重复的 mount name、重复 global、重复 provider name、重复 module specifier 都会报错。这样可以尽早发现两个能力包互相覆盖的问题。

## 15. Web 兼容环境

`QuickjsHostMount.web()` 提供轻量 Web-like 环境：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.web(
        locationHref: 'https://example.com/app',
        userAgent: 'MyApp QuickJS',
      ),
    ],
  ),
);
```

它提供：

- `window`
- `self`
- `location`
- `navigator`
- `URL`
- `localStorage`
- `sessionStorage`

它不包含完整 DOM、CSSOM、WebView、真实浏览器渲染环境。

如果脚本只缺某个很小的 Web API，可以在 `QuickjsHostMount.web()` 的基础上自己补一段 JS。比如给 `navigator` 补 `language` 和 `languages`：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.web(
        locationHref: 'https://example.com/app',
        userAgent: 'MyApp QuickJS',
      ),
    ],
    environmentPatches: const <QuickjsHostScript>[
      QuickjsHostScript.js(
        name: 'app:navigator-language.js',
        source: '''
Object.defineProperty(globalThis.navigator, 'language', {
  value: 'zh-CN',
  configurable: true,
  enumerable: true,
});
Object.defineProperty(globalThis.navigator, 'languages', {
  value: ['zh-CN', 'en-US'],
  configurable: true,
  enumerable: true,
});
''',
      ),
    ],
  ),
);
```

JS：

```js
console.log(navigator.language); // zh-CN
console.log(navigator.languages[0]); // zh-CN
```

这种做法适合补很薄的、纯 JS 能表达的兼容字段。如果要补的是一整套能力，例如网络请求、加密、文件访问、原生存储，就不要只靠 `QuickjsHostScript.js` 堆脚本，应该封装成独立 `QuickjsHostMount`，把 JS API、Dart provider、权限和配置放在一起。

如果要替换 `web()` 已经提供的能力，优先使用 mount 自带的开关关掉内置实现，再安装自己的实现。比如 `localStorage` / `sessionStorage` 已经由 `QuickjsHostMount.web()` 提供，想换成自己的实现时，可以这样做：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.web(
        storage: false,
      ),
    ],
    environmentPatches: const <QuickjsHostScript>[
      QuickjsHostScript.js(
        name: 'app:storage.js',
        globals: <String>['localStorage'],
        source: '''
const data = new Map();
globalThis.localStorage = {
  get length() { return data.size; },
  key(index) { return Array.from(data.keys())[index] ?? null; },
  getItem(key) {
    key = String(key);
    return data.has(key) ? data.get(key) : null;
  },
  setItem(key, value) {
    data.set(String(key), String(value));
  },
  removeItem(key) {
    data.delete(String(key));
  },
  clear() {
    data.clear();
  },
};
''',
      ),
    ],
  ),
);
```

不要在已经声明 `localStorage` 的情况下再声明同名 `globals`，运行时会把重复 global 当成配置冲突并报错。这是故意的：它可以避免两个能力包都以为自己拥有同一个全局 API。

如果只是临时实验，也可以在 runtime 创建后用 `eval()` 手动覆盖：

```dart
await quickjs.eval('globalThis.localStorage = myStorage;');
```

但这种覆盖不推荐作为正式能力使用，因为 `stop()`、`mount()` 或 runtime 重建后不会自动恢复。正式方案应该放进 `QuickjsRuntimeOptions`，或者封装成自己的 `QuickjsHostMount`。

## 16. Essential / Buffer

`QuickjsHostMount.essential()` 提供低风险常用能力，目前主要是 `buffer` / `node:buffer`。

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.essential(globalBuffer: true),
    ],
  ),
);
```

JS：

```js
const bytes = Buffer.from('hello');
```

## 17. Node 兼容环境

`QuickjsHostMount.node()` 提供小型 Node-like 模块环境：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsHostMount.node(
        globalBuffer: true,
        globalProcess: true,
        env: <String, String>{'NODE_ENV': 'production'},
        platform: 'quickjs',
        cwd: '/',
      ),
    ],
  ),
);
```

包含的模块：

- `buffer` / `node:buffer`
- `crypto` / `node:crypto`
- `path` / `node:path`
- `process` / `node:process`
- `timers` / `node:timers`

这是兼容子集，不是完整 Node.js。它不提供 `fs`、真实 npm resolver 或完整系统 API。

## 18. Fetch / XMLHttpRequest

需要网络请求时安装 `QuickjsFetchMount`：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsFetchMount(
        allowedOrigins: <String>{'https://example.com'},
        timeout: const Duration(seconds: 15),
        maxRequestBytes: 1024 * 1024,
        maxResponseBytes: 10 * 1024 * 1024,
        maxRedirects: 5,
      ),
    ],
  ),
);
```

JS：

```dart
final result = await quickjs.evalAsync('''
const response = await fetch('https://example.com/');
return await response.text();
''');
```

`allowedOrigins` 是可选白名单。不传或传空集合时，QuickJS 不限制 HTTP(S) origin；传入非空集合时，只允许访问这些 origin，重定向目标也会检查同一份白名单。

默认不限制：

```dart
QuickjsFetchMount()
```

限制到指定 origin：

```dart
QuickjsFetchMount(
  allowedOrigins: <String>{'https://example.com'},
)
```

在 Flutter Web 上，`allowedOrigins` 只表示 QuickJS 允许脚本请求这些 origin，不等于绕过浏览器 CORS。Web 端请求仍然走浏览器网络栈，目标服务必须返回正确的 CORS 响应头，否则浏览器仍会拦截。

也就是说：

- native 端：没有浏览器 CORS；如果配置了 `allowedOrigins`，仍受白名单限制。
- Web 端：始终受浏览器 CORS 限制；如果配置了 `allowedOrigins`，还会额外受白名单限制。
- `allowedOrigins` 不是跨域代理，也不是 CORS 绕过开关。

`QuickjsFetchMount` 安装：

- `fetch`
- `Headers`
- `Request`
- `Response`
- `AbortController`
- `AbortSignal`
- `XMLHttpRequest`

## 19. Axios

如果你的 JS 依赖 axios，需要先加载 axios 脚本，并且安装 `QuickjsFetchMount`：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsFetchMount(
        allowedOrigins: <String>{'https://example.com'},
      ),
    ],
    environmentPatches: <QuickjsHostScript>[
      await QuickjsHostScript.asset(
        name: 'app:axios.js',
        assetKey: 'assets/js/axios.js',
        globals: const <String>['axios'],
      ),
    ],
  ),
);
```

JS：

```js
const response = await axios.get('https://example.com/');
```

## 20. Web Crypto

`QuickjsWebCryptoMount` 提供可选 Web Crypto 兼容能力：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsWebCryptoMount(
        randomUUID: true,
        getRandomValues: true,
        subtleDigest: true,
        subtleHmac: true,
      ),
    ],
  ),
);
```

支持：

- `crypto.randomUUID()`
- `crypto.getRandomValues(...)`
- `crypto.subtle.digest(...)`
- HMAC 相关能力

`randomUUID()` 和 `getRandomValues()` 优先使用平台或 Web 原生随机源。默认不使用 `Math.random()` 作为安全随机回退。

Digest 示例：

```dart
final hex = await quickjs.evalAsync('''
const bytes = new TextEncoder().encode('hello');
const digest = await crypto.subtle.digest('SHA-256', bytes);
return Array.from(new Uint8Array(digest))
  .map((b) => b.toString(16).padStart(2, '0'))
  .join('');
''');
```

## 21. ES Module

直接执行 ES module：

```dart
await quickjs.evalModule(
  '''
export const answer = 42;
globalThis.answer = answer;
''',
  name: 'app/main.mjs',
);
```

读取结果：

```dart
final answer = await quickjs.eval('globalThis.answer');
```

## 22. Module Loader

如果模块有静态 import，可以通过 `moduleLoader` 加载依赖：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    moduleLoader: (moduleName) {
      return <String, String>{
        'app/helper.mjs': 'export const suffix = " from helper";',
      }[moduleName];
    },
  ),
);

await quickjs.evalModule(
  '''
import { suffix } from './helper.mjs';
globalThis.message = 'hello' + suffix;
''',
  name: 'app/main.mjs',
);
```

相对路径会根据当前模块名规范化后传给 loader。

## 23. 预注册 Host Module

可以在 options 中注册 ES module：

```dart
final quickjs = await Quickjs.create(
  options: const QuickjsRuntimeOptions(
    modules: <QuickjsHostModule>[
      QuickjsHostModule.esModule(
        specifier: 'app/config',
        source: 'export const version = "1.0.0";',
      ),
    ],
  ),
);

await quickjs.evalModule(
  '''
import { version } from 'app/config';
globalThis.version = version;
''',
  name: 'app/main.mjs',
);
```

## 24. CommonJS

执行 CommonJS：

```dart
final result = await quickjs.evalCommonJs(
  '''
const value = 20 + 22;
module.exports = value;
''',
  name: 'app/common.cjs',
);

print(result); // 42
```

注册 CommonJS host module：

```dart
final quickjs = await Quickjs.create(
  options: const QuickjsRuntimeOptions(
    modules: <QuickjsHostModule>[
      QuickjsHostModule.commonJs(
        specifier: 'app/math',
        source: 'exports.add = (a, b) => a + b;',
      ),
    ],
  ),
);
```

JS：

```js
const math = require('app/math');
math.add(1, 2);
```

## 25. Flutter asset module loader

如果要从 Flutter assets 加载模块，可以使用包内提供的 asset module loader。

典型思路：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    moduleLoader: quickjsAssetModuleLoader(
      prefix: 'assets/js/',
    ),
  ),
);
```

然后在 `pubspec.yaml` 中声明对应资源。模块名和 asset 路径的映射以 `quickjsAssetModuleLoader` 的参数为准。

## 26. 函数句柄

如果要多次调用同一个 JS 函数，可以用 `evaluateHandle()`：

```dart
final handle = await quickjs.evaluateHandle('''
(name) => 'hello ' + name
''');

try {
  final result = await handle.call(<Object?>['QuickJS']);
  print(result);
} finally {
  await handle.dispose();
}
```

如果函数返回 Promise，用 `callAsync()`：

```dart
final handle = await quickjs.evaluateHandle('''
async (name) => 'hello ' + name
''');

final result = await handle.callAsync(<Object?>['QuickJS']);
```

不用时释放 handle，避免长期持有 JS 函数引用。

## 27. 绑定 Dart 对象

`bindObject()` 可以把一个 Dart 对象代理成 JS 全局对象：

```dart
var count = 0;

final handle = await quickjs.bindObject(
  'counter',
  QuickjsObjectProxy(
    properties: const <String, Object?>{
      'name': 'main-counter',
    },
    accessors: <String, QuickjsObjectAccessor>{
      'count': QuickjsObjectAccessor(
        get: () => count,
        set: (value) {
          count = (value as num).toInt();
        },
      ),
    },
    methods: <String, QuickjsCallback>{
      'inc': (args) {
        count += args.isEmpty ? 1 : (args.first as num).toInt();
        return count;
      },
    },
  ),
);

try {
  final result = await quickjs.evalAsync('''
await counter.inc(2);
counter.count = 10;
return await counter.inc();
''');
  print(result); // 11
} finally {
  await handle.dispose();
}
```

对象方法和 getter 都通过 Promise bridge 调用；JS 侧建议使用 `await`。

## 28. 绑定 Dart 类

`bindClass()` 可以把 Dart 类暴露成 JS 构造器。

```dart
final handle = await quickjs.bindClass<_User>(
  'User',
  QuickjsClass<_User>(
    constructor: (args) {
      return _User('${args.first}');
    },
    accessors: <String, QuickjsInstanceAccessor<_User>>{
      'name': QuickjsInstanceAccessor<_User>(
        get: (user) => user.name,
      ),
    },
    methods: <String, QuickjsInstanceMethod<_User>>{
      'hello': (user, args) => 'hello ${user.name}',
    },
  ),
);
```

JS：

```dart
final result = await quickjs.evalAsync('''
const user = new User('QuickJS');
return await user.hello();
''');
```

Dart 类示例：

```dart
final class _User {
  _User(this.name);
  final String name;
}
```

## 29. JS 向 Dart 推送流数据

`bindSink()` 会在 JS 侧创建 `{ emit, close, error }`，Dart 侧得到 `Stream<Object?>`：

```dart
final stream = await quickjs.bindSink('progress');
final sub = stream.listen((value) {
  print('progress: $value');
});

await quickjs.evalAsync('''
for (let i = 1; i <= 3; i++) {
  await progress.emit(i);
}
progress.close();
''');

await sub.cancel();
```

`await sink.emit(value)` 会等待 Dart 侧确认，适合需要 backpressure 的场景。

## 30. 插件是什么

QuickJS 插件本质上是一组 ES module，加上一份 manifest。

manifest 描述：

- `id`：插件命名空间，例如 `assetApi`。
- `version`：插件版本。
- `entry`：入口模块，例如 `assetApi/main`。
- `exports`：允许 Dart 调用的函数名。
- `init`：可选初始化生命周期导出名。
- `dispose`：可选释放生命周期导出名。
- `permissions`：应用自定义权限标签。
- `metadata`：应用自定义元数据。

只有声明在 `exports` 里的函数才会作为插件 API 被 Dart 调用。

## 31. 创建单文件插件

```dart
final plugin = QuickjsPlugin.singleFile(
  id: 'demoApi',
  version: '1.0.0',
  exports: const <String>['hello', 'sum'],
  source: '''
export function hello(name) {
  return 'hello ' + name;
}

export function sum(a, b) {
  return a + b;
}
''',
);
```

## 32. 从 assets 创建插件

`pubspec.yaml`：

```yaml
flutter:
  assets:
    - assets/js/demo_plugin.mjs
```

Dart：

```dart
final plugin = await QuickjsPlugin.singleFileAsset(
  id: 'demoApi',
  version: '1.0.0',
  assetKey: 'assets/js/demo_plugin.mjs',
  exports: const <String>['hello', 'sum'],
);
```

JS：

```js
export function hello(name) {
  return `hello ${name}`;
}

export function sum(a, b) {
  return a + b;
}
```

## 33. 创建多文件插件

```dart
final plugin = await QuickjsPlugin.asset(
  manifest: const QuickjsPluginManifest(
    id: 'mathApi',
    version: '1.0.0',
    entry: 'mathApi/main',
    exports: <String>['addText'],
  ),
  modules: const <String, String>{
    'mathApi/main': 'assets/js/math/main.mjs',
    'mathApi/helper': 'assets/js/math/helper.mjs',
  },
);
```

`main.mjs`：

```js
import { suffix } from './helper';

export function addText(value) {
  return value + suffix;
}
```

`helper.mjs`：

```js
export const suffix = ' from helper';
```

模块名必须使用插件 `id` 作为命名空间，例如 `mathApi/main`、`mathApi/helper`。

## 34. 推荐插件模板

`manifest.json`：

```json
{
  "id": "templateApi",
  "version": "1.0.0",
  "entry": "templateApi/main",
  "exports": ["hello"],
  "permissions": ["storage"],
  "metadata": {
    "displayName": "Template API"
  }
}
```

`main.js`：

```js
import { formatName } from './modules/helper.js';

let prefix = 'hello';

export function init(context) {
  if (context && typeof context.prefix === 'string') {
    prefix = context.prefix;
  }
}

export function hello(name) {
  return `${prefix} ${formatName(name)}`;
}

export function dispose() {
  prefix = 'hello';
}
```

`modules/helper.js`：

```js
export function formatName(value) {
  return String(value).trim();
}
```

quickjs 不强制插件只能使用目录或 zip。应用层可以手动把 manifest JSON 转换成
`QuickjsPluginManifest`，再把模块文件映射为 `QuickjsPluginModule`；如果插件已经打成 zip，
也可以直接用 `QuickjsZipPlugin` 解包成 `QuickjsPlugin`。`exports` 声明 Dart 侧可调用的业务函数，
`init` / `dispose` 是可选生命周期导出，未声明时会跳过。

zip 插件包示例：

```text
manifest.json
main.js
modules/helper.js
```

`manifest.json`：

```json
{
  "id": "zipApi",
  "version": "1.0.0",
  "entry": "zipApi/main",
  "exports": ["hello"]
}
```

Dart：

```dart
final plugin = await QuickjsZipPlugin.asset(
  assetKey: 'assets/plugins/zip_api.zip',
);
```

如果 zip 内部路径和模块 specifier 不是默认映射关系，可以在 manifest 里显式声明 `files`：

```json
{
  "id": "zipApi",
  "version": "1.0.0",
  "entry": "zipApi/main",
  "exports": ["hello"],
  "files": {
    "zipApi/main": "src/main.mjs",
    "zipApi/lib/helper.mjs": "src/helper.mjs"
  }
}
```

## 35. 安装插件

创建 runtime 时安装：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      plugin.asMount(),
    ],
  ),
);
```

运行时安装：

```dart
await quickjs.mount(plugin.asMount());
```

建议优先在创建 runtime 时安装插件，运行时安装会触发 runtime 重建。

## 36. 调用插件

如果只有一个插件导出了某个方法：

```dart
final result = await quickjs.invokePlugin(
  'hello',
  const <Object?>['QuickJS'],
);
```

如果多个插件导出了同名方法，需要指定 `pluginId`：

```dart
final result = await quickjs.invokePlugin(
  'hello',
  const <Object?>['QuickJS'],
  pluginId: 'demoApi',
);
```

也可以指定插件对象：

```dart
final result = await quickjs.callPlugin(
  plugin,
  'hello',
  const <Object?>['QuickJS'],
);
```

提前验证插件导出：

```dart
await quickjs.validatePlugin(plugin);
```

常用语法糖：

```dart
final client = QuickjsPluginClient(quickjs, plugin);

await client.validate();
await client.init({'locale': 'zh-CN'});
final result = await client.call('hello', ['QuickJS']);
await client.dispose();
```

从 manifest asset 和模块 asset map 创建插件包：

```dart
final plugin = await QuickjsPluginBundle.asset(
  manifestAsset: 'assets/plugins/demo/manifest.json',
  modules: const <String, String>{
    'demo/main': 'assets/plugins/demo/main.js',
    'demo/helper': 'assets/plugins/demo/modules/helper.js',
  },
);
```

把多个插件注册成工具集：

```dart
final tools = QuickjsToolRegistry(quickjs)
  ..register(translatorPlugin)
  ..register(summaryPlugin);

final text = await tools.call('translator.translate', ['hello']);
```

Stream helper 只是命名语法糖，不新增 runtime API：

```dart
final progress = await QuickjsStreamBridge.bindJsSink(quickjs, 'progress');

await QuickjsStreamBridge.bindDartStream(quickjs, 'hostCount', (_) {
  return Stream.periodic(const Duration(seconds: 1), (i) => i + 1).take(3);
});
```

## 37. 插件调用 Dart 方法

Dart：

```dart
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      plugin.asMount(),
    ],
    providers: <QuickjsHostProvider>[
      QuickjsHostProvider.global(
        name: 'getDataAsync',
        callback: (args, _) async {
          return 'data from Dart';
        },
      ),
      QuickjsHostProvider.global(
        name: 'dartMethod',
        callback: (args, _) {
          return 'method result from Dart';
        },
      ),
    ],
  ),
);
```

插件 JS：

```js
export async function test() {
  const data = await getDataAsync();
  const value = await dartMethod('hello');
  return { data, value };
}
```

## 38. 插件 + axios 完整示例

Dart：

```dart
final plugin = await QuickjsPlugin.singleFileAsset(
  id: 'assetApi',
  version: '1.0.0',
  assetKey: 'assets/js/js_call_dart_plugin.mjs',
  exports: const <String>['test2', 'axiosGet'],
);

final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[
      QuickjsFetchMount(
        allowedOrigins: <String>{'https://example.com'},
      ),
      plugin.asMount(),
    ],
    providers: <QuickjsHostProvider>[
      QuickjsHostProvider.global(
        name: 'alert',
        callback: (args, _) {
          print('alert: ${args.join(' ')}');
          return null;
        },
      ),
      QuickjsHostProvider.global(
        name: 'getDataAsync',
        callback: (args, _) async {
          return 'data from Dart';
        },
      ),
      QuickjsHostProvider.global(
        name: 'dartMethod',
        callback: (args, _) {
          return 'method result from Dart';
        },
      ),
    ],
    environmentPatches: <QuickjsHostScript>[
      await QuickjsHostScript.asset(
        name: 'app:axios.js',
        assetKey: 'assets/js/axios.js',
        globals: const <String>['axios'],
      ),
    ],
  ),
);

final result = await quickjs.invokePlugin(
  'test2',
  const <Object?>['hello from Dart'],
  pluginId: 'assetApi',
);
```

JS：

```js
export async function test2(input) {
  await alert('plugin received:', input);
  const data = await getDataAsync();
  const methodResult = await dartMethod(input);
  return { input, data, methodResult };
}

export async function axiosGet(url) {
  const response = await axios.get(url);
  return {
    status: response.status,
    preview: String(response.data).slice(0, 200),
  };
}
```

## 39. 调试快照

`debugInspect()` 可以查看 runtime 当前状态：

```dart
final snapshot = await quickjs.debugInspect(includeGlobals: true);

print(snapshot.state);
print(snapshot.registeredProviders);
print(snapshot.registeredMounts);
print(snapshot.pluginDetails);
print(snapshot.moduleNames);
print(snapshot.globals);
```

常用字段：

- `state`
- `quickjsVersion`
- `running`
- `pendingEvaluations`
- `registeredCallbacks`
- `registeredProviders`
- `providerDetails`
- `registeredMounts`
- `pluginDetails`
- `moduleNames`
- `sourceMapNames`
- `memoryLimitBytes`
- `stackLimitBytes`
- `globals`

## 40. Source Map

如果 JS 是由 TypeScript、Babel、打包器生成的，可以注册 source map：

```dart
quickjs.registerSourceMap(
  'app:bundle.js',
  QuickjsSourceMap.fromJson(sourceMapJson),
);
```

执行时 `name` 要和注册名一致：

```dart
await quickjs.eval(
  generatedCode,
  name: 'app:bundle.js',
);
```

发生 `JsException` 时，会尽量附加匹配的 `sourceMap`、`fileName`、`line`、`column` 信息。

移除：

```dart
quickjs.unregisterSourceMap('app:bundle.js');
quickjs.clearSourceMaps();
```

## 41. 异常处理

常见异常：

- `JsException`：JS 主动 throw 或执行异常。
- `JsValueConversionException`：值无法转换。
- `JsTimeoutException`：执行超时。
- `JsCancelledException`：runtime 被 stop 或重建导致取消。
- `JsRuntimeClosedException`：runtime 已关闭。
- `JsRuntimeCrashException`：底层 worker 崩溃。
- `JsOutOfMemoryException`：超出内存限制。
- `JsStackOverflowException`：栈溢出。

示例：

```dart
try {
  await quickjs.eval('throw new Error("boom")', name: 'app:error.js');
} on JsException catch (error) {
  print(error.name);
  print(error.message);
  print(error.stack);
} on QuickjsException catch (error) {
  print(error.message);
}
```

## 42. 停止和重建

`stop()` 会停止当前 runtime。后续运行会在内部重建：

```dart
await quickjs.stop();
```

适合用户主动取消、页面进入后台、长任务中断等场景。

`mount()` 运行时安装能力也会重建 runtime。重建后：

- options 中的 mounts/providers/scripts/modules 会重新安装。
- 运行期间临时写入的 JS global 状态不会保留。
- Dart 侧旧的 function/object/class handle 不应继续使用。

## 43. 生命周期建议

建议：

- 页面退出时 `dispose()`。
- 长时间停留页面可以在运行前检查 runtime 年龄，必要时重建。
- 插件、fetch、crypto、provider 等能力尽量在创建 runtime 时声明。
- 大对象、函数句柄、对象代理、类绑定不用时释放对应 handle。
- 不要把不可信 JS 放在拥有过多 host 能力的 runtime 中执行。

页面长时间停留时可以这样处理：

```dart
static const runtimeMaxAge = Duration(minutes: 30);

DateTime? createdAt;
Quickjs? quickjs;

Future<Quickjs> runtimeForRun() async {
  final current = quickjs;
  final time = createdAt;
  if (current != null &&
      time != null &&
      DateTime.now().difference(time) < runtimeMaxAge) {
    return current;
  }

  await quickjs?.dispose();
  quickjs = await Quickjs.create();
  createdAt = DateTime.now();
  return quickjs!;
}
```

## 44. 推荐组合

只执行简单 JS：

```dart
final quickjs = await Quickjs.create();
final result = await quickjs.evaluateValue('1 + 2');
```

需要 Web-like 全局对象：

```dart
QuickjsHostMount.web();
```

需要 Buffer / Node 子集：

```dart
QuickjsHostMount.essential(globalBuffer: true);
QuickjsHostMount.node(globalBuffer: true, globalProcess: true);
```

需要网络：

```dart
QuickjsFetchMount(
  allowedOrigins: <String>{'https://example.com'},
);
```

需要 crypto：

```dart
QuickjsWebCryptoMount(
  randomUUID: true,
  getRandomValues: true,
  subtleDigest: true,
  subtleHmac: true,
);
```

需要 Dart 方法注入：

```dart
QuickjsHostProvider.global(
  name: 'methodName',
  callback: (args, _) async => 'result',
);
```

需要插件：

```dart
final plugin = await QuickjsPlugin.singleFileAsset(...);
final quickjs = await Quickjs.create(
  options: QuickjsRuntimeOptions(
    mounts: <QuickjsHostMount>[plugin.asMount()],
  ),
);
final result = await quickjs.invokePlugin('methodName', args);
```
