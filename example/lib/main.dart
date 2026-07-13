import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'app.dart';
import 'example_quickjs_ui_runtime.dart';

/// example 应用入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  fvp.registerWith(
    options: const <String, Object>{
      'platforms': <String>['windows', 'macos', 'linux'],
      'video.decoders': ['BRAW:gpu', 'auto'],
      // 'maxWidth': 540,
      // 'maxHeight': 960,
    },
  );
  await initExampleQuickjsUiRuntime();
  runApp(const ExampleApp());
}
