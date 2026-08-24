import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pages/example_index_page.dart';

/// example 应用根组件。
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key, this.startupError, this.startupStackTrace});

  final Object? startupError;
  final StackTrace? startupStackTrace;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'quickjs 示例',
      theme: buildExampleTheme(defaultTargetPlatform),
      home: startupError == null
          ? const ExampleIndexPage()
          : _StartupErrorPage(
              error: startupError!,
              stackTrace: startupStackTrace,
            ),
    );
  }
}

class _StartupErrorPage extends StatelessWidget {
  const _StartupErrorPage({required this.error, this.stackTrace});

  final Object error;
  final StackTrace? stackTrace;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS 初始化失败')),
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsets.all(24),
          children: <Widget>[
            const Text('应用已启动，但原生 QuickJS 运行时不可用。请检查启动日志中的动态库或符号加载错误。'),
            const SizedBox(height: 16),
            SelectableText(error.toString()),
            if (stackTrace != null) ...<Widget>[
              const SizedBox(height: 16),
              ExpansionTile(
                title: const Text('堆栈信息'),
                children: <Widget>[
                  Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(stackTrace.toString()),
                  ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

ThemeData buildExampleTheme(TargetPlatform platform) {
  final fontFamily = switch (platform) {
    TargetPlatform.windows => 'Microsoft YaHei UI',
    _ => null,
  };
  return ThemeData(
    useMaterial3: true,
    colorSchemeSeed: Colors.blue,
    platform: platform,
    fontFamily: fontFamily,
  );
}
