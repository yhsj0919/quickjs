import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  testWidgets('built-in Material color tokens resolve across ColorScheme', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    late Map<String, Color> expected;

    await tester.pumpWidget(
      MaterialApp(
        theme: ThemeData(colorSchemeSeed: Colors.indigo),
        home: Builder(
          builder: (context) {
            final scheme = Theme.of(context).colorScheme;
            expected = <String, Color>{
              'primary': scheme.primary,
              'primaryContainer': scheme.primaryContainer,
              'primaryFixed': scheme.primaryFixed,
              'secondaryContainer': scheme.secondaryContainer,
              'secondaryFixedDim': scheme.secondaryFixedDim,
              'tertiaryContainer': scheme.tertiaryContainer,
              'onTertiaryContainer': scheme.onTertiaryContainer,
              'tertiaryFixed': scheme.tertiaryFixed,
              'surface': scheme.surface,
              'surfaceBright': scheme.surfaceBright,
              'surfaceDim': scheme.surfaceDim,
              'surfaceContainerLowest': scheme.surfaceContainerLowest,
              'surfaceContainer': scheme.surfaceContainer,
              'surfaceContainerHighest': scheme.surfaceContainerHighest,
              'onSurfaceVariant': scheme.onSurfaceVariant,
              'errorContainer': scheme.errorContainer,
              'outlineVariant': scheme.outlineVariant,
              'inverseSurface': scheme.inverseSurface,
              'onInverseSurface': scheme.onInverseSurface,
              'inversePrimary': scheme.inversePrimary,
              'surfaceTint': scheme.surfaceTint,
              'shadow': scheme.shadow,
              'scrim': scheme.scrim,
            };
            final node = QuickjsUiNode.fromMap(<String, Object?>{
              'type': 'Stack',
              'children': <Object?>[
                for (final token in expected.keys)
                  <String, Object?>{
                    'type': 'Text',
                    'data': token,
                    'style': <String, Object?>{'color': '\$$token'},
                  },
              ],
            });
            return renderer.build(node, buildContext: context);
          },
        ),
      ),
    );

    Color? textColor(String value) =>
        tester.widget<Text>(find.text(value)).style?.color;

    for (final entry in expected.entries) {
      expect(textColor(entry.key), entry.value, reason: '\$${entry.key}');
    }
  });

  testWidgets('font size tokens are independent from spacing tokens', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Text',
      'data': 'font token',
      'style': <String, Object?>{'fontSize': r'$font.lg'},
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => renderer.build(node, buildContext: context),
        ),
      ),
    );

    expect(tester.widget<Text>(find.text('font token')).style?.fontSize, 20);
    expect(
      QuickjsUiDesignTokens().number(
        r'$spacing.lg',
        QuickjsUiTokenCategory.spacing,
      ),
      16,
    );
    expect(
      QuickjsUiDesignTokens(
        fontSizes: const <String, double>{'caption': 11},
      ).number(r'$font.caption', QuickjsUiTokenCategory.fontSize),
      11,
    );
  });
}
