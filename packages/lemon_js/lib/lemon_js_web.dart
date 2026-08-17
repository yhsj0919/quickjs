// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web/web_loader.dart';

/// Flutter Web 插件注册入口。
///
/// 这里只做 best-effort 预加载；真正初始化会由 `JsEngine.create()` 等待完成。
class JsWeb {
  /// 注册 Flutter Web 插件并预加载 Lemon JS Web Host。
  static void registerWith(Registrar registrar) {
    // Best-effort preload; [JsEngine.create] awaits full initialization.
    loadJsWebHost().ignore();
  }
}
