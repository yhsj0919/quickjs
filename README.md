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
- [x] 重复 `dispose()`、closed 后 `stop()`、stop 过程中入队 eval 等状态边界已有测试。
- [x] `QuickjsRuntimeState` 与 `engine.state` 已公开，可观测 ready、running、
  stopping、closed、failed 等生命周期状态。
- [x] `QuickjsRuntimeOptions` 已支持单 runtime 资源限制：`memoryLimitBytes`
  超限会映射为 `JsOutOfMemoryException`；native `stackLimitBytes` 超限会映射为
  `JsStackOverflowException`。
- [x] 多 runtime 的基础 global 状态已隔离。
- [x] dispose 一个 runtime 不影响另一个 runtime 继续 eval。
- [x] 已有基础异常类型：`JsException`、`JsTimeoutException`、
  `JsCancelledException`、`JsRuntimeClosedException`、`JsRuntimeCrashException`。
- [x] native worker crash 后 pending Future 会完成为 `JsRuntimeCrashException`，
  后续请求返回 closed error。
- [x] native / web 基础一致性测试已覆盖 eval、throw、FIFO、runtime 隔离、
  timeout、stop、dispose、web worker terminate 后的 peer runtime 恢复。
- [x] example 已覆盖 basic eval、async API、runtime worker、队列与重入、
  runtime 隔离、异常模型、资源限制等页面。

### 部分完成

- [~] `timeout`：native 使用 QuickJS interrupt handler；web 在无法中断同步
  WASM 时通过 terminate worker / 重建 runtime 兜底。Web peer runtime 会在下一次
  eval 时恢复可用，但 globals 会随 Worker 重建而丢失。
- [~] `stop()`：已能取消当前 eval 与队列 eval，并在后台重建 runtime；公开
  `cancel(requestId)` 尚未实现。
- [~] runtime 状态机：内部已使用显式状态枚举管理队列、stop、dispose、closed、
  crash，并公开 `engine.state`；`creating` 阶段的实际可观测创建流程仍待补。
- [~] 错误模型：timeout、cancel、closed、基础 JS throw、native worker crash
  映射已有覆盖；结构化 JS exception 元数据、OOM 错误仍待完善。
- [~] runtime 隔离：globals 与 dispose 隔离已有测试；callbacks、timers、
  modules、handles、资源限制边界仍待实现。

### 未开始

- [ ] 结构化 JS-to-Dart / Dart-to-JS 值转换。
- [ ] 结构化 JS exception 元数据：stack、name、file、line、column。
- [ ] Dart callback、Promise job pump、timer。
- [ ] ES module、asset loader、最小 CommonJS 兼容层。
- [ ] function/object handle 与 Dart object proxy。
- [ ] Web stack limit 配置。
- [ ] console、sourcemap、inspector。
- [ ] `fetch`、`crypto`、`Buffer` 等 host capability / 生态兼容能力。

## 验证

当前基础验证命令：

```powershell
flutter analyze
flutter test
flutter test test\quickjs_consistency_test.dart -d chrome
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
