import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 待办列表 Demo：ListView、TextField、事件、受控输入与 ThemeData token 的实际列表场景。
class QuickjsUiTodoPage extends StatelessWidget {
  const QuickjsUiTodoPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/todo_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Todo List')),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI todo error: $error'),
        ),
      ),
    );
  }
}
