# lemon_js

公开 API 的命名和方向语义以 [API 命名语义](../../docs/api_naming_conventions.md) 为准。

`lemon_js` 是面向 Flutter 的 QuickJS JavaScript 运行时。原生平台使用 FFI 和随包编译的
QuickJS，Flutter Web 使用 WASM 与 Web Worker。它提供异步执行、ES Module、插件、宿主
能力注入、结构化值转换、网络、KV、Web Crypto 和运行时隔离。

支持 Android、iOS、macOS、Linux、Windows 和 Web。

## 安装

```yaml
dependencies:
  lemon_js: ^0.1.1
```

```dart
import 'package:lemon_js/lemon_js.dart';
```

## 基本使用

```dart
Future<void> runJavaScript() async {
  final runtime = await Quickjs.create();
  try {
    final result = await runtime.eval('''
      const items = [1, 2, 3];
      ({ total: items.reduce((sum, value) => sum + value, 0) });
    ''');
    print(result); // {total: 6}
  } finally {
    await runtime.dispose();
  }
}
```

`eval()` 返回 Dart 结构化值。需要底层字符串结果时使用 `evalRaw()`。
每个 `Quickjs` 实例拥有独立 runtime；不用时应调用 `dispose()`。

## Dart 与 JavaScript 互调

```dart
final runtime = await Quickjs.create();
await runtime.injectFunction('addFromDart', (arguments) {
  return (arguments[0] as num) + (arguments[1] as num);
});

final result = await runtime.run('''
  return await addFromDart(20, 22);
''');
print(result); // 42
```

`injectFunction()` 暴露的 Dart 函数在 JS 中返回 Promise。参数和结果支持 JSON 值以及
`Uint8List`/`Uint8Array`。

## ES Module

```dart
final runtime = await Quickjs.create(
  moduleLoader: (name) => <String, String>{
      'math.mjs': 'export const answer = 42;',
    }[name],
);

await runtime.evalModule('''
  import { answer } from './math.mjs';
  globalThis.result = answer;
''', name: 'main.mjs');

print(await runtime.eval('globalThis.result')); // 42
```

Flutter asset 模块可使用 `jsAssetModuleLoader()`。npm 依赖建议先通过 esbuild、
Rollup 或 webpack 打包，不提供完整 Node.js resolver。

## 宿主能力

宿主能力通过 `JsFeatures` 注入。常用内置能力包括：

- `FetchFeatures`：Fetch、XHR、FormData、Blob 等网络 API；
- `StorageFeatures`：按 namespace 隔离的异步 KV；
- `WebCryptoFeatures`：随机数、摘要和 HMAC；
- `AxiosFeatures`：向 JS 提供 Axios；
- `JsFeatures.essential()`、`JsFeatures.node()`：常用环境兼容能力。

```dart
final runtime = await Quickjs.create(
  features: <JsFeatures>[
    FetchFeatures(
      allowedOrigins: <String>{'https://api.example.com'},
    ),
    StorageFeatures(namespace: 'site.example'),
  ],
);
```

生产环境建议限制网络 origin。Web 请求仍受浏览器 CORS、Cookie 和安全策略限制。

## JS 插件

```dart
final plugin = JsPlugin.sources(
  manifest: const JsPluginManifest(
    id: 'site.example',
    version: '1.0.0',
    entry: 'site.example/main.mjs',
    exports: <String>['getHome'],
  ),
  modules: const <String, String>{
    'site.example/main.mjs':
        'export function getHome() { return {items: []}; }',
  },
);

final runtime = await Quickjs.create();
final result = await runtime.callPlugin(plugin, 'getHome', const []);
```

插件 ID 同时作为模块命名空间。多文件插件和 ZIP 插件也使用相同的 manifest、导出校验与
调用模型。

## 运行限制与错误

`JsOptions` 可配置内存、原生栈、调用队列和默认超时。框架错误可通过
`JsException.kind` 或具体异常类型区分超时、取消、队列已满、runtime 关闭、崩溃、
内存不足和栈溢出。

长同步 JavaScript 不会阻塞 Flutter UI isolate，但会阻塞同一 QuickJS runtime 的后续
任务。`restart()` 会重建底层 runtime，因此 JS 全局变量和模块临时状态会丢失。

## 示例与文档

- [完整 Flutter 示例](https://github.com/yhsj0919/quickjs/tree/master/examples/lemon_js_example)
- [插件 manifest](https://github.com/yhsj0919/quickjs/blob/master/docs/plugin_manifest.md)
- [npm 打包](https://github.com/yhsj0919/quickjs/blob/master/docs/npm_bundling.md)
- [Class binding 生命周期](https://github.com/yhsj0919/quickjs/blob/master/docs/class_binding_lifecycle.md)
- [性能排查](https://github.com/yhsj0919/quickjs/blob/master/docs/performance_troubleshooting.md)
- [pub 包最小示例](example/main.dart)

完整示例保留在 GitHub 仓库，pub 包 README 只覆盖最小接入和主要能力。
