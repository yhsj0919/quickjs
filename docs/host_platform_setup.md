# 宿主平台配置

本文记录应用接入 Lemon JS 后必须由宿主工程完成的额外配置。CI 中为了构建或启动示例而
安装的系统依赖，如果最终用户环境同样需要，也必须在应用的安装包中声明，不能只配置开发机。

## iOS 与 macOS

Flutter 当前以 Swift Package Manager 为主要 Apple 依赖管理方式。`lemon_js` 已提供共享
Darwin Swift package，其中包含 Swift 插件壳和完整的 QuickJS/FFI C target；宿主应用不需
为它禁用 SwiftPM。插件仍保留 CocoaPods 清单，用于尚未迁移的旧 Flutter 宿主。

应用 `pubspec.yaml` 应设置版本：

```yaml
version: 1.0.0+1
```

`version` 中 `+` 前的部分会写入 Apple 平台的 `CFBundleShortVersionString`，后面的构建号会
写入 `CFBundleVersion`。发布到 App Store 前两者都必须存在。

使用当前 Flutter SDK 时直接执行：

```bash
flutter clean
flutter pub get
flutter build ios --no-codesign
flutter build macos
```

使用 CocoaPods 兼容模式的旧宿主应保留 Podfile。Podfile 和 Xcode 工程的最低系统版本应
保持一致，且不得低于当前 Flutter SDK 要求。仓库示例基于 Flutter 3.47，使用：

```ruby
# ios/Podfile
platform :ios, '15.0'

# macos/Podfile
platform :osx, '12.0'
```

升级 Flutter 后如果工具提示提高 deployment target，应同时更新 Podfile 与 Xcode 工程，
并将修改提交到版本控制。

## Linux

`lemon_js` 本身随插件编译 QuickJS，不要求宿主单独安装 QuickJS。使用
`lemon_js_ui_video_player` 时，桌面视频后端 FVP/MDK 需要 PulseAudio 运行库
`libpulse.so.0`。Debian/Ubuntu 开发与 CI 环境可安装：

```bash
sudo apt-get install libpulse0
```

发布 deb/rpm 等系统包时，应把提供 `libpulse.so.0` 的发行版软件包列为运行依赖。发布
AppImage、压缩包或自定义安装器时，应在目标发行版上验证该动态库存在，或按所用打包格式
提供兼容的运行库。只在构建机安装 `libpulse0` 不能保证最终用户机器可以启动应用。

Linux 图形应用还需要 Flutter Linux 桌面本身要求的 GTK 运行环境；`xvfb`、`xauth`、
`x11-utils` 和 ImageMagick 仅用于本仓库 CI 的无界面启动与截图，不是应用运行依赖。

## Android、Windows 与 Web

当前没有 Lemon JS 特有的宿主配置。Android SDK/NDK、Windows 桌面工具链和 Web 浏览器
要求遵循所使用 Flutter SDK 的官方要求即可。示例中的 `video_player_android` 版本覆盖是为
特定 Android 开发板的视频绿屏兼容性保留，不是 `lemon_js` 的通用要求；普通宿主不应直接
复制该覆盖。

## 发布前检查

- 在每个目标平台执行 Release 构建；
- 在真实或虚拟环境中至少启动一次产物；
- 检查启动日志中没有 FFI 符号缺失或动态库缺失；
- 确认 Apple 应用版本、构建号和 deployment target；
- 确认 Linux 安装包声明视频后端所需的系统运行库。
