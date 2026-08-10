// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web/quickjs_web_loader.dart';

/// Flutter Web 插件注册入口。
///
/// 这里只做 best-effort 预加载；真正初始化会由 `Quickjs.create()` 等待完成。
class QuickjsWeb {
  static void registerWith(Registrar registrar) {
    // Best-effort preload; [Quickjs.create] awaits full initialization.
    loadQuickjsWebHost().ignore();
  }
}
