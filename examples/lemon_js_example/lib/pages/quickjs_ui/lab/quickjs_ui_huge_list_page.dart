import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 用于验证 ListView.builder 分批预取能力的超长列表测试页。
class JsUiHugeListPage extends StatelessWidget {
  const JsUiHugeListPage({super.key});

  static const String path = 'assets/quickjs_ui/huge_list_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('列表性能 · 100,000 项')),
      body: JsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('超长列表加载失败：$error'),
        ),
      ),
    );
  }
}
