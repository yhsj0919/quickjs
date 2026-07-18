import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 专门验证分页追加和系统下拉刷新的无限列表测试页。
class QuickjsUiInfiniteListPage extends StatelessWidget {
  const QuickjsUiInfiniteListPage({super.key});

  static const String path = 'assets/quickjs_ui/infinite_list_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI · 无限加载')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('无限列表加载失败：$error'),
        ),
      ),
    );
  }
}
