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
    print(await engine.eval('1 + 2 * 3')); // 7
    print(await engine.eval('"hello"'));
  } finally {
    await engine.dispose();
  }
}
```

## 当前状态

项目已经完成最小 runtime 闭环：创建 QuickJS runtime、执行 JavaScript、释放
runtime，并覆盖 native FFI 与 Web WASM。

### 已完成

- [x] 公开 API 已异步化：`Quickjs.create()`、`eval()`、`evaluate()`、
  `stop()`、`dispose()` 均返回 Future。
- [x] native 执行迁移到 Dart isolate worker，QuickJS runtime 指针不进入
  Flutter UI isolate。
- [x] Web 执行迁移到 Web Worker，浏览器 UI thread 不直接调用 WASM QuickJS。
- [x] 同一个 `Quickjs` 实例内的 eval 请求按 FIFO 队列串行执行。
- [x] 长耗时 JavaScript 不阻塞 Dart isolate / Flutter UI。
- [x] `dispose()` 会拒绝新请求、取消队列任务，并等待运行中的任务收尾后释放
  runtime。
- [x] 多 runtime 的基础 global 状态已隔离。
- [x] dispose 一个 runtime 不影响另一个 runtime 继续 eval。
- [x] 已有基础异常类型：`JsException`、`JsTimeoutException`、
  `JsCancelledException`、`JsRuntimeClosedException`、`JsRuntimeCrashException`。
- [x] example 已覆盖 basic eval、async API、runtime worker、队列与重入、
  runtime 隔离、异常模型等页面。

### 部分完成

- [~] `timeout`：native 使用 QuickJS interrupt handler；web 在无法中断同步
  WASM 时通过 terminate worker / 重建 runtime 兜底。
- [~] `stop()`：已能取消当前 eval 与队列 eval，并在后台重建 runtime；公开
  `cancel(requestId)` 尚未实现。
- [~] runtime 状态机：队列、stop、dispose、closed 语义已有覆盖；完整
  `creating -> ready -> running -> stopping -> closed / failed` 状态模型待补。
- [~] 错误模型：timeout、cancel、closed、基础 JS throw 映射已有覆盖；结构化
  JS exception 元数据、worker crash 覆盖、OOM 错误仍待完善。
- [~] runtime 隔离：globals 与 dispose 隔离已有测试；callbacks、timers、
  modules、handles、资源限制边界仍待实现。

### 未开始

- [ ] 结构化 JS-to-Dart / Dart-to-JS 值转换。
- [ ] 结构化 JS exception 元数据：stack、name、file、line、column。
- [ ] Dart callback、Promise job pump、timer。
- [ ] ES module、asset loader、最小 CommonJS 兼容层。
- [ ] function/object handle 与 Dart object proxy。
- [ ] memory limit 与 stack limit 配置。
- [ ] console、sourcemap、inspector。
- [ ] `fetch`、`crypto`、`Buffer` 等 host capability / 生态兼容能力。

## 验证

当前基础验证命令：

```powershell
flutter analyze
flutter test
cd example
flutter test
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
.\tool\fetch_web_assets.ps1
```

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
- `lib/src/quickjs.dart`：`Quickjs` 实现与请求队列。
- `lib/src/native/`：native FFI backend 与 Dart isolate worker。
- `lib/src/web/`：Flutter Web backend 与 JS interop loader。
- `native/`：C FFI bridge。
- `assets/web/`：Web Worker、WASM bridge 与 quickjs-wasi 资源。
- `third_party/quickjs`：QuickJS 源码。
- `example/`：手动 smoke test app 与 example 页面。
