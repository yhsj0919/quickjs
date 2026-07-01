import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiProfileFormPage extends StatelessWidget {
  const QuickjsUiProfileFormPage({super.key});

  static const String path = 'assets/quickjs_ui/profile_form_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Profile Form')),
      body: QuickjsUiView.asset(
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
