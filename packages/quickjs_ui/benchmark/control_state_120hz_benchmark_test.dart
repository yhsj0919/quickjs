import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  testWidgets('active control transition stays within 120Hz budget', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(home: renderer.build(_buttonList(enabled: true, count: 1))),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(home: renderer.build(_buttonList(enabled: false, count: 1))),
    );
    await tester.pump();

    const frames = 24;
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'Active control transition at 120Hz: '
      '${averageMs.toStringAsFixed(3)} ms/frame',
    );
    expect(averageMs, lessThan(8.333));
  });
}

QuickjsUiNode _buttonList({required bool enabled, required int count}) {
  return QuickjsUiNode.fromMap(<String, Object?>{
    'type': 'SingleChildScrollView',
    'child': <String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        for (var index = 0; index < count; index += 1)
          <String, Object?>{
            'type': 'ElevatedButton',
            'key': 'button-$index',
            if (enabled)
              'onPressed': <String, Object?>{
                'method': 'press',
                'payload': <String, Object?>{'index': index},
              },
            'stateTransition': <String, Object?>{
              'durationMs': 160,
              'curve': 'easeOutCubic',
            },
            'stateStyles': <String, Object?>{
              'normal': <String, Object?>{
                'backgroundColor': '#155e75',
                'foregroundColor': '#ecfeff',
                'borderColor': '#22d3ee',
                'borderWidth': 1,
                'borderRadius': 14,
                'elevation': 6,
                'opacity': 1,
                'scale': 1,
              },
              'disabled': <String, Object?>{
                'backgroundColor': '#1e293b',
                'foregroundColor': '#64748b',
                'borderColor': '#334155',
                'elevation': 0,
                'opacity': 0.6,
                'scale': 0.96,
              },
            },
            'child': <String, Object?>{
              'type': 'Text',
              'data': 'Control $index',
            },
          },
      ],
    },
  });
}
