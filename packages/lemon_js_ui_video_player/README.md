# lemon_js_ui_video_player

`lemon_js_ui_video_player` 为 `lemon_js_ui` 提供原生 `VideoPlayer` 组件，JS
页面可通过 `quickjs_ui/video_player` 模块声明播放器节点。

## 安装

```yaml
dependencies:
  lemon_js_ui_video_player: ^0.1.0
```

插件内部负责依赖 `video_player`，并在 Windows、macOS 和 Linux 上自动注册
FVP 后端。宿主通常不需要直接依赖或初始化这两个底层包。

```dart
final plugins = <QuickjsUiPlugin>[
  QuickjsUiVideoPlayerPlugin.plugin,
];
```

只有需要定制桌面端 FVP 参数时，才需要在创建 UI Session 前调用：

```dart
QuickjsUiVideoPlayerPlugin.registerDesktopBackend(
  options: const <String, Object>{
    'platforms': <String>['windows', 'macos', 'linux'],
  },
);
```

更多页面协议和代码提示配置见
[lemon_js_ui 使用指南](https://github.com/yhsj0919/quickjs/blob/main/packages/lemon_js_ui/docs/usage.md)。
