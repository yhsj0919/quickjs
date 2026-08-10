import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  testWidgets('Canvas cached scene 120Hz frame cost', (tester) async {
    final staticCommands = <Object?>[
      for (var index = 0; index < 1000; index += 1)
        <String, Object?>{
          'op': 'line',
          'x1': (index % 100) * 3,
          'y1': (index ~/ 100) * 3,
          'x2': (index % 100) * 3 + 2,
          'y2': (index ~/ 100) * 3 + 2,
          'stroke': '#64748b',
          'strokeWidth': 1,
        },
    ];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 320,
      'height': 320,
      'staticCommands': staticCommands,
      'commands': <Object?>[
        <String, Object?>{'op': 'save'},
        <String, Object?>{'op': 'translate', 'x': 160, 'y': 160},
        <String, Object?>{
          'op': 'rotate',
          'radians': <String, Object?>{
            'from': 0,
            'to': 6.283185307,
            'durationMs': 1000,
            'repeat': true,
          },
        },
        <String, Object?>{
          'op': 'line',
          'x1': 0,
          'y1': 20,
          'x2': 0,
          'y2': -140,
          'stroke': '#e53935',
          'strokeWidth': 2,
        },
        <String, Object?>{'op': 'restore'},
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );
    await tester.pump();

    const frames = 240;
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print('Canvas 120Hz benchmark: ${averageMs.toStringAsFixed(3)} ms/frame');
    expect(averageMs, lessThan(8.333));
  });

  testWidgets('Canvas 1000 locally animated primitives at 120Hz', (
    tester,
  ) async {
    final commands = <Object?>[
      for (var index = 0; index < 1000; index += 1)
        <String, Object?>{
          'op': 'circle',
          'cx': <String, Object?>{
            'from': -4,
            'to': 324,
            'durationMs': 900 + index % 700,
            'phaseMs': index * 7,
            'repeat': true,
          },
          'cy': (index % 100) * 3.2,
          'radius': 1.5,
          'fill': '#2563eb',
        },
    ];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 320,
      'height': 320,
      'commands': commands,
    });
    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );
    await tester.pump();

    const frames = 240;
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'Canvas 1000 animations benchmark: '
      '${averageMs.toStringAsFixed(3)} ms/frame',
    );
    expect(averageMs, lessThan(8.333));
  });
}
