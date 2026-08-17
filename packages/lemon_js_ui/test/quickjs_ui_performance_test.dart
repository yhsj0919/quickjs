import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  test('auto quality degrades and recovers with hysteresis', () {
    final controller = JsUiPerformanceController(
      mode: JsUiPerformanceMode.auto,
      targetFrameBudget: const Duration(milliseconds: 8),
      degradeAfterFrames: 2,
      upgradeAfterFrames: 4,
    );
    addTearDown(controller.dispose);

    void sample(Duration duration) {
      controller.addFrameSample(build: duration, raster: duration);
    }

    sample(const Duration(milliseconds: 10));
    expect(controller.quality, JsUiEffectQuality.high);
    sample(const Duration(milliseconds: 10));
    expect(controller.quality, JsUiEffectQuality.balanced);
    sample(const Duration(milliseconds: 10));
    sample(const Duration(milliseconds: 10));
    expect(controller.quality, JsUiEffectQuality.low);

    for (var index = 0; index < 4; index += 1) {
      sample(const Duration(milliseconds: 4));
    }
    expect(controller.quality, JsUiEffectQuality.balanced);
    for (var index = 0; index < 4; index += 1) {
      sample(const Duration(milliseconds: 4));
    }
    expect(controller.quality, JsUiEffectQuality.high);
  });

  test(
    'display refresh rate configures automatic budget unless overridden',
    () {
      final automatic = JsUiPerformanceController(
        mode: JsUiPerformanceMode.auto,
      );
      automatic.updateDisplayRefreshRate(60);
      expect(automatic.refreshRate, 60);
      expect(automatic.targetFrameBudget.inMicroseconds, closeTo(16667, 1));

      final overridden = JsUiPerformanceController(
        mode: JsUiPerformanceMode.auto,
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
    final controller = JsUiPerformanceController(mode: JsUiPerformanceMode.low);
    expect(controller.quality, JsUiEffectQuality.low);
    controller.updateReduceMotion(true);
    expect(controller.quality, JsUiEffectQuality.off);
    expect(controller.snapshot.reduceMotion, isTrue);
    controller.updateReduceMotion(false);
    expect(controller.quality, JsUiEffectQuality.low);
    controller.dispose();
  });

  test('performance snapshot exposes timing percentiles and reason', () {
    final controller = JsUiPerformanceController(
      mode: JsUiPerformanceMode.auto,
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

  test('performance session exports fixed-mode samples as JSON', () {
    final controller = JsUiPerformanceController(
      mode: JsUiPerformanceMode.high,
      targetFrameBudget: const Duration(milliseconds: 8),
    );
    controller.updateDisplayRefreshRate(120);
    controller.updateDisplayMetrics(
      logicalSize: const Size(1080, 2400),
      devicePixelRatio: 3,
    );
    controller.startSession(
      warmUp: Duration.zero,
      scene: const <String, Object?>{'primitiveCount': 10000},
      metadata: const <String, Object?>{'revision': 'test'},
    );
    controller.addFrameSample(
      build: const Duration(milliseconds: 4),
      raster: const Duration(milliseconds: 7),
    );
    controller.addFrameSample(
      build: const Duration(milliseconds: 9),
      raster: const Duration(milliseconds: 17),
    );

    final report = controller.stopSession();
    final json = report.toJson(pretty: false);
    expect(report.frameCount, 2);
    expect(report.slowFrameCount, 1);
    expect(report.severeFrameCount, 1);
    expect(report.buildP50Ms, anyOf(4, 9));
    expect(report.buildMaxMs, 9);
    expect(report.rasterMaxMs, 17);
    expect(report.qualityDurationsMs, contains('high'));
    expect(report.environment['refreshRate'], 120);
    expect(report.environment['logicalWidth'], 1080);
    expect(report.environment['devicePixelRatio'], 3);
    expect(report.environment['revision'], 'test');
    expect(report.scene['primitiveCount'], 10000);
    expect(json, contains('"schemaVersion":1'));
    expect(json, contains('"frameCount":2'));
    controller.dispose();
  });

  test('performance session records automatic quality degradation', () {
    final controller = JsUiPerformanceController(
      mode: JsUiPerformanceMode.auto,
      targetFrameBudget: const Duration(milliseconds: 8),
      degradeAfterFrames: 1,
      upgradeAfterFrames: 2,
    );
    controller.startSession(warmUp: Duration.zero);
    controller.addFrameSample(
      build: const Duration(milliseconds: 12),
      raster: const Duration(milliseconds: 12),
    );

    final report = controller.stopSession();
    expect(report.degradeCount, 1);
    expect(report.qualityTimeline.map((event) => event.quality), <String>[
      'high',
      'balanced',
    ]);
    expect(report.qualityTimeline.last.reason, contains('exceeded'));
    controller.dispose();
  });

  testWidgets('low quality removes expensive widget effects locally', (
    tester,
  ) async {
    final performance = JsUiPerformanceController(
      mode: JsUiPerformanceMode.auto,
      degradeAfterFrames: 1,
      upgradeAfterFrames: 2,
    );
    final renderer = JsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    final node = JsUiNode.fromMap(<String, Object?>{
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
    expect(performance.quality, JsUiEffectQuality.low);
    expect(find.byType(BackdropFilter), findsNothing);
    expect(find.byType(ColorFiltered), findsNothing);
    expect(find.byType(ImageFiltered), findsOneWidget);
    final metrics = performance.snapshot.toMap();
    expect(metrics['blurEffectCount'], 1);
    expect(metrics['clampedBlurEffectCount'], 1);
    expect(metrics['disabledBackdropBlurCount'], 1);
    expect(metrics['disabledColorFilterCount'], 1);

    await tester.pumpWidget(const SizedBox.shrink());
    renderer.dispose();
    performance.dispose();
  });

  testWidgets('Canvas metrics include schema resources paint and rejection', (
    tester,
  ) async {
    final performance = JsUiPerformanceController(
      mode: JsUiPerformanceMode.low,
    );
    final renderer = JsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    final node = JsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'sceneKey': 'metrics-scene',
      'commands': <Object?>[
        <String, Object?>{
          'op': 'path',
          'segments': <Object?>[
            <String, Object?>{'op': 'moveTo', 'x': 0, 'y': 0},
            <String, Object?>{'op': 'lineTo', 'x': 10, 'y': 10},
          ],
          'stroke': '#000000',
        },
        <String, Object?>{
          'op': 'snapshotParticleGrid',
          'sourceSlot': 'source',
          'targetSlot': 'target',
          'width': 80,
          'height': 50,
          'columns': 24,
          'rows': 18,
          'bucketCount': 4,
          'staggerMs': 4,
          'travelMs': 60,
          'fadeMs': 40,
        },
      ],
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    await tester.pump();
    var metrics = performance.snapshot.toMap();
    expect(metrics['canvasCount'], 1);
    expect(metrics['canvasCommandCount'], 2);
    expect(metrics['canvasPathSegmentCount'], 2);
    expect(metrics['requestedParticleFragments'], 432);
    expect(metrics['effectiveParticleFragments'], 256);
    expect(metrics['retainedSceneCount'], 1);
    expect(metrics['canvasRepaintCount'], greaterThan(0));
    expect(metrics['canvasPaintP90Ms'], isA<double>());

    final invalid = JsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'commands': <Object?>[
        <String, Object?>{'op': 'restore'},
      ],
    });
    expect(() => renderer.build(invalid), throwsFormatException);
    metrics = performance.snapshot.toMap();
    expect(metrics['rejectedCanvasCommandCount'], 1);
    expect(metrics['lastCanvasRejection'], contains('restore'));

    await tester.pumpWidget(const SizedBox.shrink());
    renderer.dispose();
    performance.dispose();
  });

  testWidgets('off quality resolves animations to a static end state', (
    tester,
  ) async {
    final performance = JsUiPerformanceController(
      mode: JsUiPerformanceMode.off,
    );
    final renderer = JsUiRenderer(
      onEvent: (_) {},
      performanceController: performance,
    );
    final node = JsUiNode.fromMap(<String, Object?>{
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
