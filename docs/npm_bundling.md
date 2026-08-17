# npm 依赖打包

QuickJS 运行时不会解析 `node_modules`、`package.json` 的 exports，也不实现完整的
Node 模块算法。请在打包 Flutter 应用前先捆绑 npm 依赖，使运行时接收到不含未解析
npm 标识的普通 JavaScript 源码。

## 推荐边界

- 在运行时之外使用 esbuild、Rollup 或其他应用构建工具。
- 每个公开插件或能力入口优先生成一个自包含 ESM 文件。
- 默认以 `platform=browser` 检查兼容性。依赖 Node 内置模块的包应在构建期失败，
  除非应用显式提供 polyfill 或将依赖标记为 external。
- 只有通过 `JsOptions.modules` 注册了相同模块标识时，才能把 npm 依赖
  标记为 external。
- 文件系统、网络、数据库和平台 API 应留在发布包之外，通过宿主 method 或 features
  按需暴露。

## 内置 esbuild 示例

可运行示例位于 `examples/lemon_js_example/npm_bundle`，它将 CommonJS npm 包
`fast-deep-equal` 封装为一个小型 ESM API。

```powershell
cd examples/lemon_js_example/npm_bundle
npm ci
npm run build
```

构建命令等价于：

```powershell
esbuild src/index.js `
  --bundle `
  --format=esm `
  --platform=browser `
  --target=es2020 `
  --outfile=../assets/js/npm_bundle.mjs
```

`--bundle` 在构建期跟踪 npm 导入；`--format=esm` 为
`JsModule` 保留入口导出；`--platform=browser` 防止意外依赖
Node 运行时全局对象和内置模块。

## 注册生成的资源

在 Flutter 应用的 `pubspec.yaml` 中声明生成文件：

```yaml
flutter:
  assets:
    - assets/js/npm_bundle.mjs
```

创建运行时前加载源码，并使用应用自有的模块标识注册：

```dart
final source = await rootBundle.loadString('assets/js/npm_bundle.mjs');
final engine = await JsEngine.create(
  modules: <JsModule>[
      JsModule(
        name: 'example/npm-bundle',
        source: source,
      ),
    ],
);

await engine.runModule('''
import { compareValues } from 'example/npm-bundle';
globalThis.bundleResult = compareValues(
  { answer: 42 },
  { answer: 42 },
);
''', name: 'app/use-npm-bundle.mjs');
```

模块标识属于应用，无需与 npm 包名一致；建议增加命名空间以避免冲突。

## IIFE 方案

需要主动安装全局对象的脚本可使用 `--format=iife --global-name=YourNamespace`
构建，并通过 `JsEngine.eval()` 执行。可复用库应优先使用 ESM，因为其导出显式且不会
污染 `globalThis`。

## 不支持或风险较高的包

npm 安装成功不代表与 QuickJS 兼容。需要检查依赖以下能力的发布包：

- `fs`、`net`、`tls`、`child_process` 等 Node 内置模块或原生扩展；
- 打包器无法静态解析的动态 `require()`；
- 所选宿主 features 未提供的浏览器 DOM API；
- `eval`、动态生成代码、WebAssembly 或体积很大的启动载荷；
- 预期运行时存在的环境变量或包文件。

第三方发布包应视为不可信应用代码：设置运行时内存与超时限制，只暴露必要宿主能力，
替换已经加载的模块时重建运行时。

## 参考资料

- [esbuild bundling](https://esbuild.github.io/api/#bundle)
- [esbuild output formats](https://esbuild.github.io/api/#format)
- [esbuild platform behavior](https://esbuild.github.io/api/#platform)
