# Lemon JS 示例应用

这是仓库中的完整 Flutter 示例，用于验证和演示：

- `lemon_js` 的执行、模块、插件、回调、网络和宿主能力；
- `lemon_js_ui` 的原生控件、表单、列表、Canvas、动画和调试工具；
- `lemon_js_ui_video_player` 的 Flutter 注册与独立 JS 页面；
- `quickjs_extensions` 的 Core、JSUI 和混合插件流程。

## 运行

```bash
flutter pub get
flutter run
```

指定设备：

```bash
flutter devices
flutter run -d <device-id>
```

## 常用构建

```bash
flutter build apk --debug
flutter build windows --debug
flutter build web --release
```

示例中的 `video_player_android: 2.7.1` override 用于规避部分 Android 开发板的视频绿屏
问题，请勿在没有对应设备回归的情况下删除或升级。

## 主要示例文件

- [JSUI 页面](assets/quickjs_ui)
- [视频播放器 JS 页面](assets/quickjs_ui/video_player_plugin_page.mjs)
- [视频播放器 Flutter 页面](lib/pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart)
- [混合插件](assets/extensions/hybrid_demo)

包的最小接入方式请分别查看仓库根目录下 `packages/*/README.md`。
