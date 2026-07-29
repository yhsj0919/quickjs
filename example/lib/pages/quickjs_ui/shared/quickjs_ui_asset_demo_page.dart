import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiAssetDemoPage extends StatelessWidget {
  const QuickjsUiAssetDemoPage({
    super.key,
    required this.title,
    required this.path,
    this.errorLabel = 'QuickJS UI demo error',
    this.backgroundColor,
    this.foregroundColor,
  });

  final String title;
  final String path;
  final String errorLabel;
  final Color? backgroundColor;
  final Color? foregroundColor;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final resolvedBackground = backgroundColor ?? theme.scaffoldBackgroundColor;
    final resolvedForeground = foregroundColor ?? theme.colorScheme.onSurface;

    return Scaffold(
      backgroundColor: resolvedBackground,
      appBar: AppBar(
        title: Text(title),
        backgroundColor: resolvedBackground,
        foregroundColor: resolvedForeground,
      ),
      body: QuickjsUiView.asset(
        path: path,
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText(
            '$errorLabel: $error',
            style: TextStyle(color: resolvedForeground),
          ),
        ),
      ),
    );
  }
}

class QuickjsUiDarkAssetDemoPage extends StatelessWidget {
  const QuickjsUiDarkAssetDemoPage({
    super.key,
    required this.title,
    required this.path,
    this.errorLabel = 'QuickJS UI demo error',
  });

  final String title;
  final String path;
  final String errorLabel;

  @override
  Widget build(BuildContext context) => QuickjsUiAssetDemoPage(
    title: title,
    path: path,
    errorLabel: errorLabel,
    backgroundColor: const Color(0xFF020617),
    foregroundColor: Colors.white,
  );
}
