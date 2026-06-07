# quickjs

Flutter 插件，集成 [QuickJS](https://github.com/quickjs-ng/quickjs)。

| 平台 | 实现 |
|------|------|
| Android / iOS / macOS / Linux / Windows | FFI + 源码编译 |
| Web | [quickjs-wasi](https://www.npmjs.com/package/quickjs-wasi) WASM（`quickjs_web.js` 全局 API） |

## 使用

```dart
import 'package:quickjs/quickjs.dart';

Future<void> main() async {
  final engine = await Quickjs.create();
  try {
    print(engine.quickjsVersion);
    print(await engine.evaluate('1 + 2 * 3')); // 7
    print(await engine.evaluate('"hello"'));
  } finally {
    engine.dispose();
  }
}
```

## 更新 QuickJS（原生）

```powershell
.\tool\update_quickjs.ps1 v0.14.0
```

## 更新 Web WASM 资源

```powershell
.\tool\fetch_web_assets.ps1
```

## Web 调试

若仍失败，在 Chrome 开发者工具 (F12) → Console 查看：

1. `quickjs_web.js` / `quickjs_bridge.mjs` / `quickjs.wasm` 是否 404
2. 是否有 ES module / MIME 相关错误

然后执行：

```bash
cd example
flutter clean
flutter pub get
flutter run -d chrome
```

## 结构

- `third_party/quickjs` — QuickJS 子模块（原生编译）
- `native/` — C FFI 桥接
- `assets/web/` — Web WASM 与 quickjs-wasi 的 ESM 模块（`quickjs_wasi.js`、`wasi-shim.js` 等）
