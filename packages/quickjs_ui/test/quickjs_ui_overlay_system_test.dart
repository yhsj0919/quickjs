import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  testWidgets('Overlay renders arbitrary aligned content and dismisses', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{'type': 'Text', 'data': 'Page'},
          <String, Object?>{
            'type': 'Overlay',
            'visible': true,
            'alignment': 'bottomCenter',
            'padding': 20,
            'barrierColor': '#66000000',
            'transition': 'slideUp',
            'durationMs': 120,
            'onDismissed': <String, Object?>{'method': 'overlayDismissed'},
            'child': <String, Object?>{
              'type': 'Container',
              'width': 240,
              'height': 80,
              'color': '#112233',
              'child': <String, Object?>{
                'type': 'Text',
                'data': 'Arbitrary overlay content',
              },
            },
          },
        ],
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => renderer.build(node, buildContext: context),
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('Arbitrary overlay content'), findsOneWidget);
    expect(
      find.ancestor(
        of: find.text('Arbitrary overlay content'),
        matching: find.byType(Material),
      ),
      findsWidgets,
    );
    expect(
      tester.getBottomLeft(find.text('Arbitrary overlay content')).dy,
      greaterThan(500),
    );

    await tester.tapAt(const Offset(5, 5));
    await tester.pumpAndSettle();
    expect(find.text('Arbitrary overlay content'), findsNothing);
    expect(events.single['method'], 'overlayDismissed');
  });

  testWidgets('Overlay closes declaratively without firing onDismissed', (
    tester,
  ) async {
    var visible = true;
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    addTearDown(renderer.dispose);

    QuickjsUiNode schema() => QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Overlay',
        'visible': visible,
        'transition': 'none',
        'onDismissed': <String, Object?>{'method': 'dismissed'},
        'child': <String, Object?>{'type': 'Text', 'data': 'Overlay body'},
      },
    });

    Widget harness() => MaterialApp(
      home: Builder(
        builder: (context) => renderer.build(schema(), buildContext: context),
      ),
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Overlay body'), findsOneWidget);

    visible = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Overlay body'), findsNothing);
    expect(events, isEmpty);
  });

  testWidgets('slideDown enters from above and reverses on close', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Overlay',
        'visible': true,
        'alignment': 'topCenter',
        'transition': 'slideDown',
        'durationMs': 200,
        'child': <String, Object?>{'type': 'Text', 'data': 'Top overlay'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) => renderer.build(node, buildContext: context),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    final slideFinder = find.byWidgetPredicate(
      (widget) => widget is SlideTransition && widget.child is FadeTransition,
    );
    double minimumSlideDy() => tester
        .widgetList<SlideTransition>(slideFinder)
        .map((transition) => transition.position.value.dy)
        .reduce((a, b) => a < b ? a : b);
    expect(minimumSlideDy(), lessThan(0));
    await tester.pumpAndSettle();
    expect(minimumSlideDy(), closeTo(0, 0.0001));

    await tester.tapAt(const Offset(5, 500));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(minimumSlideDy(), lessThan(0));
    await tester.pumpAndSettle();
  });

  testWidgets('overlay child action closes the controlled route', (
    tester,
  ) async {
    var visible = true;
    late StateSetter rebuild;
    late final QuickjsUiRenderer renderer;
    renderer = QuickjsUiRenderer(
      onEvent: (event) {
        if (event['method'] == 'close') {
          rebuild(() => visible = false);
        }
      },
    );
    addTearDown(renderer.dispose);

    QuickjsUiNode schema() => QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Overlay',
        'visible': visible,
        'durationMs': 180,
        'child': <String, Object?>{
          'type': 'ElevatedButton',
          'onPressed': <String, Object?>{'method': 'close'},
          'child': <String, Object?>{'type': 'Text', 'data': 'Close overlay'},
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return renderer.build(schema(), buildContext: context);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Close overlay'), findsOneWidget);

    await tester.tap(find.text('Close overlay'));
    await tester.pumpAndSettle();
    expect(visible, isFalse);
    expect(find.text('Close overlay'), findsNothing);
  });

  testWidgets('overlay close button survives a real mouse down frame', (
    tester,
  ) async {
    var visible = true;
    var closes = 0;
    late StateSetter rebuild;
    late final QuickjsUiRenderer renderer;
    renderer = QuickjsUiRenderer(
      onEvent: (event) {
        if (event['method'] == 'close') {
          closes += 1;
          rebuild(() => visible = false);
        }
      },
    );
    addTearDown(renderer.dispose);

    QuickjsUiNode schema() => QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Overlay',
        'visible': visible,
        'transition': 'none',
        'child': <String, Object?>{
          'type': 'ElevatedButton',
          'stateTransition': <String, Object?>{'durationMs': 180},
          'stateStyles': <String, Object?>{
            'normal': <String, Object?>{'scale': 1},
            'pressed': <String, Object?>{'scale': 0.94},
          },
          'onPressed': <String, Object?>{'method': 'close'},
          'child': <String, Object?>{'type': 'Text', 'data': 'Mouse close'},
        },
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return renderer.build(schema(), buildContext: context);
          },
        ),
      ),
    );
    await tester.pumpAndSettle();

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(0, 0));
    await mouse.moveTo(tester.getCenter(find.text('Mouse close')));
    await tester.pump();
    await mouse.down(tester.getCenter(find.text('Mouse close')));
    await tester.pump(const Duration(milliseconds: 50));
    await mouse.up();
    await tester.pumpAndSettle();

    expect(closes, 1);
    expect(visible, isFalse);
  });
}
