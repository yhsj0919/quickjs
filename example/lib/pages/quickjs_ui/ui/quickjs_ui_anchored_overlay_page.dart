import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiAnchoredOverlayPage extends StatelessWidget {
  const QuickjsUiAnchoredOverlayPage({super.key});

  static const String path = 'assets/quickjs_ui/anchored_overlay_demo_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('UI 基础能力 Demo')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('UI foundation demo error: $error'),
        ),
      ),
    );
  }
}
