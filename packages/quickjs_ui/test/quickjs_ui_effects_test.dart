import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  testWidgets('effects follow VSync unless JS supplies a frame interval', (
    tester,
  ) async {
    QuickjsUiNode animatedNode({int? interval}) =>
        QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Container',
          'width': 40,
          'height': 40,
          'opacity': <String, Object?>{'from': 0, 'to': 1, 'durationMs': 1000},
          'animationFrameIntervalMs': ?interval,
        });

    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiRenderer(
          onEvent: (_) {},
        ).build(animatedNode(interval: 100)),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final firstLimitedFrame = tester
        .widget<Opacity>(find.byType(Opacity))
        .opacity;
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      firstLimitedFrame,
    );
    await tester.pump(const Duration(milliseconds: 80));
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      greaterThan(firstLimitedFrame),
    );

    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
    await tester.pumpWidget(
      MaterialApp(
        home: QuickjsUiRenderer(onEvent: (_) {}).build(animatedNode()),
      ),
    );
    await tester.pump(const Duration(milliseconds: 20));
    final firstVsyncFrame = tester
        .widget<Opacity>(find.byType(Opacity))
        .opacity;
    await tester.pump(const Duration(milliseconds: 20));
    expect(
      tester.widget<Opacity>(find.byType(Opacity)).opacity,
      greaterThan(firstVsyncFrame),
    );
  });

  testWidgets('universal effects wrap any registered node', (tester) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Text',
      'data': 'effects',
      'opacity': 0.7,
      'transform': <String, Object?>{
        'translate': <String, Object?>{'x': 8, 'y': -4},
        'scale': 1.1,
        'rotate': 0.1,
      },
      'clipRadius': 12,
      'blur': 2,
      'colorFilter': <String, Object?>{
        'color': '#80ff0000',
        'blendMode': 'srcIn',
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );

    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
    expect(
      tester
          .widgetList<ClipRect>(find.byType(ClipRect))
          .any((clip) => clip.child is ImageFiltered),
      isTrue,
    );
    expect(
      tester
          .widgetList<RepaintBoundary>(find.byType(RepaintBoundary))
          .any(
            (boundary) =>
                boundary.child is ClipRect &&
                (boundary.child! as ClipRect).child is ColorFiltered,
          ),
      isTrue,
    );
  });

  testWidgets('blur and backdrop blur stay inside their paint bounds', (
    tester,
  ) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'width': 80,
      'height': 40,
      'blur': 8,
      'backdropBlur': 8,
      'child': <String, Object?>{'type': 'Text', 'data': 'bounded blur'},
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
    );

    expect(
      tester
          .widgetList<ClipRect>(find.byType(ClipRect))
          .any((clip) => clip.child is ImageFiltered),
      isTrue,
    );
    expect(
      tester
          .widgetList<ClipRect>(find.byType(ClipRect))
          .any((clip) => clip.child is BackdropFilter),
      isTrue,
    );
  });

  testWidgets('universal effects animate locally and report final frame', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'key': 'animated-effects',
      'width': 80,
      'height': 80,
      'decoration': <String, Object?>{'color': '#4f46e5'},
      'opacity': <String, Object?>{'from': 0, 'to': 1, 'durationMs': 60},
      'transform': <String, Object?>{
        'translate': <String, Object?>{
          'x': <String, Object?>{
            'from': -40,
            'to': 0,
            'durationMs': 60,
            'curve': 'easeOut',
          },
        },
        'scale': <String, Object?>{'from': 0.8, 'to': 1, 'durationMs': 60},
      },
      'blur': <String, Object?>{'from': 8, 'to': 0, 'durationMs': 60},
      'onAnimationEnd': <String, Object?>{'method': 'effectsEnded'},
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(events.single['method'], 'effectsEnded');
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    await tester.pump(const Duration(milliseconds: 30));
    expect(tester.widget<Opacity>(find.byType(Opacity)).opacity, 1);
    expect(events, hasLength(1));
  });

  testWidgets('universal effects preserve pause and restart by playToken', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);

    QuickjsUiNode node({required bool paused, required int playToken}) =>
        QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Container',
          'key': 'effect-generation',
          'paused': paused,
          'playToken': playToken,
          'opacity': <String, Object?>{'from': 0, 'to': 1, 'durationMs': 100},
          'onAnimationEnd': <String, Object?>{'method': 'ended'},
        });

    await tester.pumpWidget(
      MaterialApp(home: renderer.build(node(paused: false, playToken: 0))),
    );
    await tester.pump(const Duration(milliseconds: 60));
    await tester.pumpWidget(
      MaterialApp(home: renderer.build(node(paused: true, playToken: 0))),
    );
    await tester.pump(const Duration(milliseconds: 200));
    expect(events, isEmpty);

    await tester.pumpWidget(
      MaterialApp(home: renderer.build(node(paused: false, playToken: 0))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(events, hasLength(1));

    await tester.pumpWidget(
      MaterialApp(home: renderer.build(node(paused: false, playToken: 1))),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 110));
    expect(events, hasLength(2));
    renderer.dispose();
  });

  testWidgets('removing a universal effect cancels pending completion', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Container',
      'key': 'removed-effect',
      'opacity': <String, Object?>{'from': 0, 'to': 1, 'durationMs': 100},
      'onAnimationEnd': <String, Object?>{'method': 'ended'},
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    expect(events, isEmpty);
    renderer.dispose();
  });
}
