import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:fvp/fvp.dart' as fvp;

import 'app.dart';
import 'example_quickjs_ui_runtime.dart';
import 'web_startup_signal.dart';

/// example 应用入口。
Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  _registerExampleVideoBackend();
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
  WidgetsBinding.instance.addPostFrameCallback((_) {
    markWebStartupReady();
  });
}

void _registerExampleVideoBackend() {
  if (kIsWeb ||
      (defaultTargetPlatform != TargetPlatform.windows &&
          defaultTargetPlatform != TargetPlatform.macOS &&
          defaultTargetPlatform != TargetPlatform.linux)) {
    return;
  }
  fvp.registerWith(
    options: const <String, Object>{
      'platforms': <String>['windows', 'macos', 'linux'],
      'video.decoders': <String>['BRAW:gpu', 'auto'],
    },
  );
}
