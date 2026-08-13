# Lemon JS

公开 API 的命名和方向语义以 [API 命名语义](docs/api_naming_conventions.md) 为准。

Lemon JS 是一组面向 Flutter 的 QuickJS 与动态 UI 工具。它支持在原生平台和 Web 中运行
JavaScript、加载隔离插件、注入宿主能力，并使用 JavaScript 描述由 Flutter 原生渲染的
动态页面。

## 包组成

| 包 | 用途 |
| --- | --- |
| [`lemon_js`](packages/lemon_js/README.md) | QuickJS runtime、模块、插件、网络、KV、加密和宿主能力 |
| [`lemon_js_ui`](packages/lemon_js_ui/README.md) | JavaScript 驱动的 Flutter 原生动态 UI |
| [`lemon_js_ui_video_player`](packages/lemon_js_ui_video_player/README.md) | JSUI 原生视频播放器插件 |
| [`lemon_js_extensions`](packages/lemon_js_extensions/README.md) | Core、JSUI 与混合插件的统一安装和管理层 |

## 快速开始

只执行 JavaScript：

```yaml
dependencies:
  lemon_js: ^0.1.1
```

```dart
import 'package:lemon_js/lemon_js.dart';

final runtime = await Quickjs.create();
try {
  print(await runtime.eval('1 + 2')); // 3
} finally {
  await runtime.dispose();
}
```

需要动态 Flutter 页面时加入 `lemon_js_ui`，需要统一插件安装、更新、恢复和按 ID 调用时
加入 `lemon_js_extensions`。各包 README 提供独立的最小用法。

## 运行完整示例

```bash
cd examples/lemon_js_example
flutter pub get
flutter run
```

[示例应用](examples/lemon_js_example/README.md)包含 Core、JSUI、Canvas、动画、视频组件和
混合插件演示。

## 文档

- [插件 manifest](docs/plugin_manifest.md)
- [混合插件设计](docs/hybrid_plugin_design.md)
- [JSUI 组件](docs/quickjs_ui_components.md)
- [JSUI 跨组件能力](docs/quickjs_ui_cross_cutting.md)
- [npm 打包](docs/npm_bundling.md)
- [原生发布构建](docs/native_release_build.md)
- [性能排查](docs/performance_troubleshooting.md)

## 开发验证

Windows 可使用统一脚本：

```powershell
.\tool\verify.cmd -Mode full
.\tool\verify.cmd -Mode ui
```

性能问题请先按照[性能排查流程](docs/performance_troubleshooting.md)建立基线，再修改生产
行为。

## 许可证

项目许可证见 [LICENSE](LICENSE)，第三方组件说明见各包的 `THIRD_PARTY_NOTICES.md`。
