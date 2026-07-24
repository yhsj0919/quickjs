import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  test('auto quality degrades and recovers with hysteresis', () {
    final controller = QuickjsUiPerformanceController(
      mode: QuickjsUiPerformanceMode.auto,
      targetFrameBudget: const Duration(milliseconds: 8),
      degradeAfterFrames: 2,
      upgradeAfterFrames: 4,
    );
    addTearDown(controller.dispose);

    void sample(Duration duration) {
      controller.addFrameSample(build: duration, raster: duration);
    }

    sample(const Duration(milliseconds: 10));
    expect(controller.quality, QuickjsUiEffectQuality.high);
    sample(const Duration(milliseconds: 10));
    expect(controller.quality, QuickjsUiEffectQuality.balanced);
    sample(const Duration(milliseconds: 10));
    sample(const Duration(milliseconds: 10));
    expect(controller.quality, QuickjsUiEffectQuality.low);

    for (var index = 0; index < 4; index += 1) {
      sample(const Duration(milliseconds: 4));
    }
    expect(controller.quality, QuickjsUiEffectQuality.balanced);
    for (var index = 0; index < 4; index += 1) {
      sample(const Duration(milliseconds: 4));
    }
    expect(controller.quality, QuickjsUiEffectQuality.high);
  });

  test(
    'display refresh rate configures automatic budget unless overridden',
    () {
      final automatic = QuickjsUiPerformanceController(
        mode: QuickjsUiPerformanceMode.auto,
      );
      automatic.updateDisplayRefreshRate(60);
      expect(automatic.refreshRate, 60);
      expect(automatic.targetFrameBudget.inMicroseconds, closeTo(16667, 1));

      final overridden = QuickjsUiPerformanceController(
        mode: QuickjsUiPerformanceMode.auto,
        targetFrameBudget: const Duration(milliseconds: 10),
      );
      overridden.updateDisplayRefreshRate(120);
      expect(overridden.refreshRate, 120);
      expect(overridden.targetFrameBudget, const Duration(milliseconds: 10));
      automatic.dispose();
      overridden.dispose();
    },
  );

  test('reduced motion temporarily forces off without losing quality', () {
    final controller = QuickjsUiPerformanceController(
      mode: QuickjsUiPerformanceMode.low,
    );
    expect(controller.quality, QuickjsUiEffectQuality.low);
    controller.updateReduceMotion(true);
    expect(controller.quality, QuickjsUiEffectQuality.off);
    expect(controller.snapshot.reduceMotion, isTrue);
    controller.updateReduceMotion(false);
    expect(controller.quality, QuickjsUiEffectQuality.low);
    controller.dispose();
  });

  test('performance snapshot exposes timing percentiles and reason', () {
    final controller = QuickjsUiPerformanceController(
      mode: QuickjsUiPerformanceMode.auto,
      degradeAfterFrames: 1,
      upgradeAfterFrames: 2,
    );
    controller.addFrameSample(
      build: const Duration(milliseconds: 10),
      raster: const Duration(milliseconds: 12),
    );
    final snapshot = controller.snapshot.toMap();
    expect(snapshot['quality'], 'balanced');
    expect(snapshot['buildP50Ms'], 10);
    expect(snapshot['rasterP90Ms'], 12);
    expect(snapshot['lastTransitionReason'], contains('exceeded'));
    controller.dispose();
  });

  testWidgets('low quality removes expensive widget effects locally', (
    tester,
  ) async {
    final performance = QuickjsUiPerformanceController(
      mode: QuickjsUiPerformanceMode.auto,
      degradeAfterFrames: 1,
      upgradeAfterFrames: 2,
    );
    final renderer = QuickjsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'key': 'quality-effect',
      'width': 40,
      'height': 40,
      'blur': 20,
      'backdropBlur': 20,
      'colorFilter': <String, Object?>{
        'color': '#80ff0000',
        'blendMode': 'srcIn',
      },
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    expect(find.byType(BackdropFilter), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);

    performance.addFrameSample(
      build: const Duration(milliseconds: 12),
      raster: const Duration(milliseconds: 12),
    );
    performance.addFrameSample(
      build: const Duration(milliseconds: 12),
      raster: const Duration(milliseconds: 12),
    );
    await tester.pump();
    expect(performance.quality, QuickjsUiEffectQuality.low);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    renderer.dispose();
    performance.dispose();
  });

  testWidgets('off quality resolves animations to a static end state', (
    tester,
  ) async {
    final performance = QuickjsUiPerformanceController(
      mode: QuickjsUiPerformanceMode.off,
    );
    final renderer = QuickjsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'key': 'disabled-effect',
      'opacity': <String, Object?>{'from': 0, 'to': 1, 'durationMs': 500},
      'blur': 20,
      'backdropBlur': 20,
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(find.byType(ImageFiltered), findsNothing);
    expect(find.byType(BackdropFilter), findsNothing);

    await tester.pumpWidget(const SizedBox.shrink());
    renderer.dispose();
    performance.dispose();
  });
}
