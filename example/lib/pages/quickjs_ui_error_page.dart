import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiErrorPage extends StatelessWidget {
  const QuickjsUiErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Error Overlay')),
      body: const QuickjsUiErrorOverlay(
        error: FormatException(
          'Unknown quickjs_ui node type: DemoMissing',
          'controls_page.mjs',
          128,
        ),
        details: QuickjsUiErrorDetails(
          source: 'asset',
          resourceKey: 'assets/quickjs_ui/controls_page.mjs',
          schemaPath: 'root.children[2]',
          routeName: 'quickjs_ui_error_demo',
          action: 'render',
        ),
      ),
    );
  }
}
