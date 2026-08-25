# lemon_js_ui_video_player

`lemon_js_ui_video_player` 是 `lemon_js_ui` 的官方视频组件插件。它同时注册：

- Flutter 原生 `VideoPlayer` 渲染组件；
- JS 模块 `quickjs_ui/video_player`。

插件基于 Flutter 官方 `video_player` 接口，不绑定具体平台实现。宿主如需 FVP 等兼容
后端，应在应用层自行引入和初始化。

## 安装

```yaml
dependencies:
  lemon_js_ui_video_player: ^0.2.1
```

各平台应按 `video_player` 文档选择并配置实现。仓库 example 演示了将 FVP 作为桌面平台
兼容后端接入，并仅在 example 中保留特定 Android 设备所需的后端版本回退；这些选择
都不是本插件公共依赖的一部分。

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

## 可选的平台兼容后端

如果宿主选择 FVP，请在宿主应用中直接声明 `fvp` 依赖，并在创建 `JsUiView` 或
`JsUiController` 前注册：

```dart
import 'package:fvp/fvp.dart' as fvp;

fvp.registerWith(
  options: const <String, Object>{
    'platforms': <String>['windows', 'macos', 'linux'],
  },
);
```

Linux 使用 FVP/MDK 时，宿主还需提供 `libpulse.so.0`。具体配置见
[宿主平台配置](https://github.com/yhsj0919/quickjs/blob/master/docs/host_platform_setup.md)。

## 完整示例

- [Flutter 页面](https://github.com/yhsj0919/quickjs/blob/master/examples/lemon_js_example/lib/pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart)
- [独立 JS 页面](https://github.com/yhsj0919/quickjs/blob/master/examples/lemon_js_example/assets/quickjs_ui/video_player_plugin_page.mjs)
- [lemon_js_ui 使用指南](https://github.com/yhsj0919/quickjs/blob/master/packages/lemon_js_ui/doc/usage.md)

完整示例位于 GitHub 仓库；pub 包 README 中的代码用于最小接入。
