import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiScrollTransitionPage extends StatelessWidget {
  const QuickjsUiScrollTransitionPage({super.key});

  static const String path = 'assets/quickjs_ui/scroll_transition_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 0.4.2')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI 0.4.2 error: $error'),
        ),
      ),
    );
  }
}
