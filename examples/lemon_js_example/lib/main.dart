import 'package:flutter/material.dart';

import 'app.dart';
import 'example_quickjs_ui_runtime.dart';

/// example 应用入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  Object? startupError;
  StackTrace? startupStackTrace;
  try {
    await initExampleJsUiRuntime();
  } catch (error, stackTrace) {
    startupError = error;
    startupStackTrace = stackTrace;
    FlutterError.reportError(
      FlutterErrorDetails(
        exception: error,
        stack: stackTrace,
        library: 'lemon_js_example startup',
        context: ErrorDescription('initializing the shared QuickJS runtime'),
      ),
    );
  }
  runApp(
    ExampleApp(
      startupError: startupError,
      startupStackTrace: startupStackTrace,
    ),
  );
}
