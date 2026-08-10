# Lemon JS 示例应用

该应用集中演示 `lemon_js`、`lemon_js_ui` 和
`lemon_js_ui_video_player` 的主要能力，包括：

- JavaScript 执行、模块、回调和宿主能力注入；
- JS 插件加载、隔离 Context 和结构化数据交互；
- JS 驱动的 Flutter 原生页面与组件；
- 视频播放器等可选 UI 扩展。

## 运行

```bash
flutter pub get
flutter run
```

Windows 调试构建：

```bash
flutter build windows --debug
```

Android 调试包：

```bash
flutter build apk --debug
```

示例中的 `video_player_android: 2.7.1` override 用于规避部分 Android
开发板的视频绿屏问题，请勿在未完成对应设备回归前随意升级。
