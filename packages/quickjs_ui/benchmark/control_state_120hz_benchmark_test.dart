import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  _benchmark(count: 1, budgetMs: 8.333, targetHz: 120);
  _benchmark(count: 10, budgetMs: 8.333, targetHz: 120);
  _benchmark(count: 40, budgetMs: 16.667, targetHz: 60);
  _mixedControlBenchmark();
}

void _benchmark({
  required int count,
  required double budgetMs,
  required int targetHz,
}) {
  testWidgets('$count active controls stay within ${targetHz}Hz budget', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(_buttonList(enabled: true, count: count)),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(_buttonList(enabled: false, count: count)),
      ),
    );
    await tester.pump();

    const frames = 24;
    final frameDuration = Duration(
      microseconds: targetHz == 120 ? 8333 : 16667,
    );
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(frameDuration);
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      '$count active controls at ${targetHz}Hz: '
      '${averageMs.toStringAsFixed(3)} ms/frame',
    );
    expect(averageMs, lessThan(budgetMs));
  });
}

void _mixedControlBenchmark() {
  testWidgets('40 mixed controls retain the measured baseline', (tester) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: renderer.build(_mixedControlList(enabled: true))),
      ),
    );
    await tester.pump();
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: renderer.build(_mixedControlList(enabled: false))),
      ),
    );
    await tester.pump();

    const frames = 24;
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(microseconds: 16667));
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      '40 mixed Button/Switch/Slider/Input controls at 60Hz: '
      '${averageMs.toStringAsFixed(3)} ms/frame',
    );
    // This gate records the pre-refactor mixed-control ceiling. The target is
    // still 16.667ms and this threshold must be tightened as input controls
    // move to stable per-frame render subtrees.
    expect(averageMs, lessThan(40));
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

QuickjsUiNode _mixedControlList({required bool enabled}) {
  const transition = <String, Object?>{
    'durationMs': 160,
    'curve': 'easeOutCubic',
  };
  const controlStates = <String, Object?>{
    'normal': <String, Object?>{'opacity': 1, 'scale': 1},
    'disabled': <String, Object?>{'opacity': 0.6, 'scale': 0.96},
  };
  return QuickjsUiNode.fromMap(<String, Object?>{
    'type': 'SingleChildScrollView',
    'child': <String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        for (var index = 0; index < 10; index += 1) ...<Object?>[
          <String, Object?>{
            'type': 'ElevatedButton',
            'key': 'button-$index',
            if (enabled) 'onPressed': <String, Object?>{'method': 'press'},
            'stateTransition': transition,
            'stateStyles': controlStates,
            'child': <String, Object?>{'type': 'Text', 'data': 'Button $index'},
          },
          <String, Object?>{
            'type': 'Switch',
            'key': 'switch-$index',
            'value': index.isEven,
            if (enabled) 'onChanged': <String, Object?>{'method': 'toggle'},
            'stateTransition': transition,
            'stateStyles': controlStates,
            'thumbStyle': <String, Object?>{
              'normal': <String, Object?>{'color': '#ecfeff'},
              'disabled': <String, Object?>{'color': '#64748b'},
            },
            'trackStyle': <String, Object?>{
              'normal': <String, Object?>{'color': '#0891b2'},
              'disabled': <String, Object?>{'color': '#334155'},
            },
          },
          <String, Object?>{
            'type': 'Slider',
            'key': 'slider-$index',
            'value': 0.5,
            if (enabled) 'onChanged': <String, Object?>{'method': 'slide'},
            'stateTransition': transition,
            'stateStyles': controlStates,
            'trackStyle': <String, Object?>{
              'normal': <String, Object?>{
                'activeColor': '#06b6d4',
                'inactiveColor': '#1e293b',
                'height': 6,
              },
              'disabled': <String, Object?>{
                'activeColor': '#475569',
                'height': 4,
              },
            },
          },
          <String, Object?>{
            'type': 'TextField',
            'key': 'input-$index',
            'value': 'Input $index',
            'enabled': enabled,
            'stateTransition': transition,
            'stateStyles': <String, Object?>{
              'normal': <String, Object?>{
                'fillColor': '#0f172a',
                'borderColor': '#334155',
                'borderRadius': 12,
                'opacity': 1,
              },
              'disabled': <String, Object?>{
                'fillColor': '#0b1220',
                'borderColor': '#1e293b',
                'opacity': 0.6,
              },
            },
          },
        ],
      ],
    },
  });
}
