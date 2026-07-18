import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 用于验证 ListView 节点按需构建的独立压力测试页。
class QuickjsUiLargeListPage extends StatelessWidget {
  const QuickjsUiLargeListPage({super.key});

  static const String path = 'assets/quickjs_ui/large_list_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI · 2,000 个列表项')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('大列表加载失败：$error'),
        ),
      ),
    );
  }
}
