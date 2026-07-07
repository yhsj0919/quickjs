import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 滚动与过渡 Demo：`scrollTo`、drag/swipe 事件、SingleChildScrollView 与 keyed 列表过渡。
class QuickjsUiScrollTransitionPage extends StatelessWidget {
  const QuickjsUiScrollTransitionPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
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
