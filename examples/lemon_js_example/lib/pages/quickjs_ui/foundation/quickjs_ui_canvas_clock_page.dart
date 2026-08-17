import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

class JsUiCanvasClockPage extends StatelessWidget {
  const JsUiCanvasClockPage({super.key});

  static const String path = 'assets/quickjs_ui/canvas_clock_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Canvas 模拟时钟')),
      body: JsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI canvas clock error: $error'),
        ),
      ),
    );
  }
}
