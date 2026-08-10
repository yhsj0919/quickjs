import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'pages/example_index_page.dart';

/// example 应用根组件。
class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'quickjs 示例',
      theme: buildExampleTheme(defaultTargetPlatform),
      home: const ExampleIndexPage(),
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
