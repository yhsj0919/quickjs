# lemon_js_ui_video_player

`lemon_js_ui_video_player` 是 `lemon_js_ui` 的官方视频组件插件。它同时注册：

- Flutter 原生 `VideoPlayer` 渲染组件；
- JS 模块 `quickjs_ui/video_player`；
- Windows、macOS、Linux 使用的 FVP 后端。

宿主只需要注入插件，不需要直接依赖或初始化 `video_player`、`fvp`。

## 安装

```yaml
dependencies:
  lemon_js_ui_video_player: ^0.2.1
```

Linux 宿主必须提供 FVP/MDK 使用的 `libpulse.so.0`。Debian/Ubuntu 开发环境可安装
`libpulse0`，发布安装包时也必须声明相应的运行依赖。Apple 平台还需采用 `lemon_js`
文档所述的原生依赖配置。详见
[宿主平台配置](https://github.com/yhsj0919/quickjs/blob/master/docs/host_platform_setup.md)。

## Flutter 端注册

把插件传给使用它的 `JsUiView`：

```dart
import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_video_player/lemon_js_ui_video_player.dart';

class VideoPage extends StatelessWidget {
  const VideoPage({super.key});

  @override
  Widget build(BuildContext context) {
    return JsUiView.asset(
      path: 'assets/pages/video_page.mjs',
      uiPlugins: <JsUiPlugin>[
        JsUiVideoPlayerPlugin.plugin,
      ],
    );
  }
}
```

并在应用的 `pubspec.yaml` 中声明 JS 页面：

```yaml
flutter:
  assets:
    - assets/pages/video_page.mjs
```

生成编辑器提示时加入插件自带的声明文件：

```bash
dart run lemon_js_ui:codegen \
  --root assets/pages \
  --types path/to/lemon_js_ui_video_player/js/quickjs_ui_video_player.d.ts
```

## JS 页面使用

```js
import { Page } from 'quickjs_ui';
import { VideoPlayer } from 'quickjs_ui/video_player';

export default Page({
  name: 'VideoPage',

  createState() {
    return { playing: true, positionMs: 0 };
  },

  build(state, props, page) {
    return VideoPlayer({
      key: 'main-player',
      source: props.source ??
        'https://media.w3.org/2010/05/sintel/trailer.mp4',
      playing: state.playing,
      loop: true,
      fit: 'contain',
      onReady: page.ready(),
      onProgress: page.progress(),
      onEnded: page.ended(),
      onError: page.failed()
    });
  },

  progress(state, _payload, _props, event) {
    return { positionMs: event.positionMs ?? 0 };
  },

  ready() {},
  ended() { return { playing: false }; },
  failed(state, _payload, _props, event) {
    return { playing: false, error: event.message };
  }
});
```

`source` 必填，支持 HTTP(S) 网络地址、原生平台文件地址或对应的
`JsUiResourceReference` 对象。主要属性包括：

- `playing`、`loop`、`fit`、`backgroundColor` 和 `showLoading`；
- `playbackSpeed`，默认 `1`；
- `seekPositionMs` 配合递增的 `seekToken` 执行定位；
- 递增 `restartToken` 可重新从头播放当前来源；
- `progressThrottleMs` 默认 `250`，控制 `onProgress` 的发送频率。

事件包括 `onReady`、`onProgress`、`onEnded`、`onError`。`onReady` 提供
`durationMs`；`onProgress` 提供 `positionMs`、`durationMs` 和 `isPlaying`；
`onError` 提供 `message`。

## 桌面端自定义

插件默认自动注册 FVP。只有需要修改桌面解码参数时，才在创建 `JsUiView` 或
`JsUiController` 前调用：

```dart
JsUiVideoPlayerPlugin.registerDesktopBackend(
  options: const <String, Object>{
    'platforms': <String>['windows', 'macos', 'linux'],
  },
);
```

## 完整示例

- [Flutter 页面](https://github.com/yhsj0919/quickjs/blob/master/examples/lemon_js_example/lib/pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart)
- [独立 JS 页面](https://github.com/yhsj0919/quickjs/blob/master/examples/lemon_js_example/assets/quickjs_ui/video_player_plugin_page.mjs)
- [lemon_js_ui 使用指南](https://github.com/yhsj0919/quickjs/blob/master/packages/lemon_js_ui/doc/usage.md)

完整示例位于 GitHub 仓库；pub 包 README 中的代码用于最小接入。
