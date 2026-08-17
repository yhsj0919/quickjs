import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 专门验证分页追加和系统下拉刷新的无限列表测试页。
class JsUiInfiniteListPage extends StatelessWidget {
  const JsUiInfiniteListPage({super.key});

  static const String path = 'assets/quickjs_ui/infinite_list_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('列表性能 · 无限加载')),
      body: JsUiView.asset(
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
