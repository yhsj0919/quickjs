import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
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
    expect(find.byType(Transform), findsNWidgets(3));
    expect(find.byType(ClipRRect), findsOneWidget);
    expect(find.byType(ImageFiltered), findsOneWidget);
    expect(find.byType(ColorFiltered), findsOneWidget);
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

  testWidgets('universal effects animate locally and report final frame', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
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

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: events.add).build(node)),
    );
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 30));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(events.single['method'], 'effectsEnded');
    expect(find.byType(Opacity), findsOneWidget);
    expect(find.byType(Transform), findsNWidgets(2));
    expect(find.byType(ImageFiltered), findsOneWidget);
  });
}
