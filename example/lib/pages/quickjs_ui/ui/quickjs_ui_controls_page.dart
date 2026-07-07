import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 0.2 内置控件 Demo：Image、ListView、TextField、Stack、Padding 等。
class QuickjsUiControlsPage extends StatelessWidget {
  const QuickjsUiControlsPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/controls_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Controls')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI controls error: $error'),
        ),
      ),
    );
  }
}
