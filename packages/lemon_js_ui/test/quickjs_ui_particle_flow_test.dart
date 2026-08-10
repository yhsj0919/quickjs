import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  testWidgets('ParticleFlow paints retained children from one flow layer', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ParticleFlow',
      'width': 200,
      'height': 300,
      'frameIntervalMs': 33,
      'particles': <Object?>[
        <String, Object?>{
          'fromX': 10,
          'toX': 30,
          'fromY': -10,
          'toY': 310,
          'fromOpacity': 0.4,
          'toOpacity': 0.8,
          'fromScale': 0.5,
          'toScale': 1.0,
          'fromRotation': 0,
          'toRotation': 1.57,
          'durationMs': 1000,
        },
        <String, Object?>{
          'fromX': 80,
          'toX': 80,
          'fromY': -20,
          'toY': 320,
          'durationMs': 1500,
          'phaseMs': 300,
        },
      ],
      'children': <Object?>[
        <String, Object?>{
          'type': 'Container',
          'key': 'particle-small',
          'width': 10,
          'height': 10,
          'color': '#FFFFFFFF',
        },
        <String, Object?>{
          'type': 'Container',
          'width': 20,
          'height': 20,
          'color': '#FFFFFFFF',
        },
      ],
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    expect(find.byType(Flow), findsOneWidget);
    expect(tester.widget<Flow>(find.byType(Flow)).children, hasLength(2));
    expect(
      tester.getSize(find.byKey(const ValueKey<String>('particle-small'))),
      const Size(10, 10),
    );
    await tester.pump(const Duration(milliseconds: 100));
    expect(tester.takeException(), isNull);
  });

  testWidgets('ParticleFlow validates particle and child counts', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ParticleFlow',
      'width': 100,
      'height': 100,
      'particles': <Object?>[],
      'children': <Object?>[
        <String, Object?>{'type': 'SizedBox', 'width': 1, 'height': 1},
      ],
    });

    expect(() => renderer.build(node), throwsFormatException);
  });
}
