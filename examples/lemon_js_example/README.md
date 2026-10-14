# Lemon JS 示例应用

这是仓库中的完整 Flutter 示例，用于验证和演示：

- `lemon_js` 的执行、模块、插件、回调、网络和宿主能力；
- `lemon_js_ui` 的原生控件、表单、列表、Canvas、动画和调试工具；
- `lemon_js_ui_video_player` 的 Flutter 注册与独立 JS 页面；
- `lemon_js_ui_webview` 的网页桥接与链式 DOM 操作；
- `lemon_js_extensions` 的 Core、JSUI 和混合插件流程。

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

OpenHarmony 必须使用独立的 CPF Flutter SDK，以及 DevEco Studio 2026 Dev 和与其配套的
HarmonyOS/OpenHarmony SDK。不要混用旧版 SDK，否则可能出现 Flutter 嵌入层方法异常或应用
无法打开：

```bash
flutter build hap --release --target-platform=ohos-arm64
flutter build hap --release --target-platform=ohos-x64
```

环境安装、CI 和当前第三方插件支持边界见[宿主平台配置](../../docs/host_platform_setup.md)。

OHOS 版 `shared_preferences` 尚未正式发布到 pub.dev，本 example 已在
`dependency_overrides` 中固定 CPF Flutter 的适配分支。宿主项目必须保留同样的覆盖，否则
登录等持久化操作会报告 `SharedPreferencesAsyncPlatform instance must be set`。

本 example 在桌面端显式引入并注册 FVP；Android 端默认不固定平台实现版本。
部分 Android 开发板出现视频绿屏时，可在宿主的 `dependency_overrides` 中按需启用
`video_player_android: 2.7.1`，example 中该配置已注释。此版本仅作为设备兼容回退参考，
启用前应在目标设备验证；它不属于 `lemon_js_ui_video_player` 的依赖或实现。

## 主要示例文件

- [JSUI 页面](assets/quickjs_ui)
- [视频播放器 JS 页面](assets/quickjs_ui/video_player_plugin_page.mjs)
- [视频播放器 Flutter 页面](lib/pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart)
- [混合插件](assets/extensions/hybrid_demo)
- [WebView 插件 JS 页面](assets/quickjs_ui/webview_plugin_page.mjs)
- [WebView 插件 Flutter 页面](lib/pages/quickjs_ui/getting_started/quickjs_ui_webview_plugin_page.dart)
- [虚拟列表与同步 builder 性能基准](lib/list_runtime_benchmark.dart)：独立 Release 入口，运行方法和测量结果见 [列表基准报告](../../docs/list_runtime_benchmark.md)。
- [列表 item 复用与内存基准](lib/list_retention_benchmark.dart)：独立进程比较往返滚动时的 Widget、State 生命周期和进程 RSS。
- [核心单次与批量函数调用基准](lib/invocation_benchmark.dart)：比较直接调用、批量调用及 JS→Dart 回调的 Release 成本。

包的最小接入方式请分别查看仓库根目录下 `packages/*/README.md`。

## Vue iframe 插件预览

使用 `flutter build web --release --target lib/preview_main.dart --no-web-resources-cdn`
构建专用播放器。Vue 组件和部署说明见 [integrations/vue](../../integrations/vue/README.md)。
该入口通过 iframe 通信加载 MJS，不进入示例菜单。
