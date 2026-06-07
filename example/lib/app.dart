import 'package:flutter/material.dart';

import 'pages/example_index_page.dart';

class ExampleApp extends StatelessWidget {
  const ExampleApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'quickjs 示例',
      theme: ThemeData(useMaterial3: true, colorSchemeSeed: Colors.blue),
      home: const ExampleIndexPage(),
    );
  }
}
