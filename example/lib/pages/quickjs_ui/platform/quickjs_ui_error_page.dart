import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 错误浮层 Demo：展示 schema、resource、route 与 action 错误的定位信息。
class QuickjsUiErrorPage extends StatelessWidget {
  const QuickjsUiErrorPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('错误诊断浮层')),
      body: const QuickjsUiErrorOverlay(
        error: QuickjsUiError(
          kind: QuickjsUiErrorKind.schema,
          message: 'Unknown quickjs_ui node type: DemoMissing',
          cause: FormatException(
            'Unknown quickjs_ui node type: DemoMissing',
            'controls_page.mjs',
            128,
          ),
          operation: 'render',
          source: 'asset',
          resource: 'assets/quickjs_ui/controls_page.mjs',
          schemaPath: 'root.children[2]',
          route: 'quickjs_ui_error_demo',
          action: 'render',
        ),
      ),
    );
  }
}
