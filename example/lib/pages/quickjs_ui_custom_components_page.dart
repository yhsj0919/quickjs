import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiCustomComponentsPage extends StatelessWidget {
  const QuickjsUiCustomComponentsPage({super.key});

  static const String path = 'assets/quickjs_ui/custom_components_page.mjs';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Custom Components')),
      body: QuickjsUiView.asset(
        path: path,
        registry: _customComponentsRegistry(),
        initialProps: const <String, Object?>{
          'title': '0.4 custom renderer registry',
        },
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI custom components error: $error'),
        ),
      ),
    );
  }
}

QuickjsUiComponentRegistry _customComponentsRegistry() {
  return QuickjsUiComponentRegistry.defaults()
    ..register('AppBar', (context, node) {
      return Material(
        color: Theme.of(context.buildContext!).colorScheme.primary,
        child: SafeArea(
          bottom: false,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                Text(
                  '${node.props['title'] ?? ''}',
                  style: Theme.of(context.buildContext!).textTheme.titleLarge
                      ?.copyWith(
                        color: Theme.of(
                          context.buildContext!,
                        ).colorScheme.onPrimary,
                      ),
                ),
                if (node.props['subtitle'] case final String subtitle)
                  Text(
                    subtitle,
                    style: Theme.of(context.buildContext!).textTheme.bodySmall
                        ?.copyWith(
                          color: Theme.of(
                            context.buildContext!,
                          ).colorScheme.onPrimary,
                        ),
                  ),
              ],
            ),
          ),
        ),
      );
    })
    ..register('Card', (context, node) {
      final tone = node.props['tone'];
      final scheme = Theme.of(context.buildContext!).colorScheme;
      final color = tone == 'primary'
          ? scheme.primaryContainer
          : scheme.surfaceContainerHighest;
      return Card(
        color: color,
        margin: const EdgeInsets.all(12),
        child: context.child(node) ?? const SizedBox.shrink(),
      );
    });
}
