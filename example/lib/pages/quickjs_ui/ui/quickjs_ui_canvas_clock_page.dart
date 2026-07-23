import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiCanvasClockPage extends StatelessWidget {
  const QuickjsUiCanvasClockPage({super.key});

  static const String path = 'assets/quickjs_ui/canvas_clock_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Canvas Clock')),
      body: QuickjsUiView.asset(
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
