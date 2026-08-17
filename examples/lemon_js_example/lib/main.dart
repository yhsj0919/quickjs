import 'package:flutter/material.dart';

import 'app.dart';
import 'example_quickjs_ui_runtime.dart';

/// example 应用入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await initExampleJsUiRuntime();
  runApp(const ExampleApp());
}
