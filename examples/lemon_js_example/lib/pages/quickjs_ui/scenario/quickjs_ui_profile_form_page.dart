import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 资料表单 Demo：受控输入、focus/blur、submit 与预览的实际表单场景。
class JsUiProfileFormPage extends StatelessWidget {
  const JsUiProfileFormPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/profile_form_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('个人资料表单')),
      body: JsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI profile form error: $error'),
        ),
      ),
    );
  }
}
