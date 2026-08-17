import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  _benchmarkQuality(JsUiPerformanceMode.high, budgetMs: 16.667);
  _benchmarkQuality(JsUiPerformanceMode.low, budgetMs: 8.333);
}

void _benchmarkQuality(JsUiPerformanceMode mode, {required double budgetMs}) {
  testWidgets('40 expensive effects in ${mode.name} quality', (tester) async {
    final performance = JsUiPerformanceController(mode: mode);
    final renderer = JsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    addTearDown(() {
      renderer.dispose();
      performance.dispose();
    });

    await tester.pumpWidget(
      MaterialApp(
        home: SingleChildScrollView(child: renderer.build(_effectGrid())),
      ),
    );
    await tester.pump();

    const frames = 120;
    final stopwatch = Stopwatch()..start();
    for (var frame = 0; frame < frames; frame += 1) {
      await tester.pump(const Duration(microseconds: 8333));
    }
    stopwatch.stop();
    final averageMs = stopwatch.elapsedMicroseconds / 1000 / frames;
    // ignore: avoid_print
    print(
      'Adaptive ${mode.name} quality: ${averageMs.toStringAsFixed(3)} ms/frame',
    );
    expect(averageMs, lessThan(budgetMs));
  });
}

JsUiNode _effectGrid() => JsUiNode.fromMap(<String, Object?>{
  'type': 'Wrap',
  'children': <Object?>[
    for (var index = 0; index < 40; index += 1)
      <String, Object?>{
        'type': 'Container',
        'key': 'effect-$index',
        'width': 48,
        'height': 48,
        'decoration': <String, Object?>{'color': '#4f46e5'},
        'opacity': <String, Object?>{
          'from': 0.5,
          'to': 1,
          'durationMs': 800 + index * 7,
          'repeat': true,
          'autoreverse': true,
        },
        'blur': 8,
        'backdropBlur': 6,
        'colorFilter': <String, Object?>{
          'color': '#20ffffff',
          'blendMode': 'srcIn',
        },
      },
  ],
});
