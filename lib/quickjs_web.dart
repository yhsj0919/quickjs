// ignore: avoid_web_libraries_in_flutter

import 'package:flutter_web_plugins/flutter_web_plugins.dart';

import 'src/web/quickjs_web_loader.dart';

/// Web plugin registration — preloads the QuickJS web runtime script.
class QuickjsWeb {
  static void registerWith(Registrar registrar) {
    // Best-effort preload; [Quickjs.create] awaits full initialization.
    loadQuickjsWebHost().ignore();
  }
}
