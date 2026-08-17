import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/src/renderer/quickjs_ui_overlay_layer.dart';

void main() {
  testWidgets('AnchoredOverlay shrink-wraps content height', (tester) async {
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Center',
        'child': <String, Object?>{
          'type': 'AnchoredOverlay',
          'visible': true,
          'placement': 'bottomStart',
          'dismissOnTapOutside': false,
          'anchor': <String, Object?>{
            'type': 'SizedBox',
            'width': 160,
            'height': 40,
            'child': <String, Object?>{'type': 'Text', 'data': 'Height anchor'},
          },
          'overlay': <String, Object?>{
            'type': 'Container',
            'padding': 12,
            'child': <String, Object?>{
              'type': 'Column',
              'children': <Object?>[
                <String, Object?>{'type': 'Text', 'data': 'Short title'},
                <String, Object?>{'type': 'Text', 'data': 'Short detail'},
              ],
            },
          },
        },
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

    final material = find
        .ancestor(of: find.text('Short title'), matching: find.byType(Material))
        .first;
    expect(tester.getSize(material).height, lessThan(120));
  });

  testWidgets('AnchoredOverlay remains attached while its anchor scrolls', (
    tester,
  ) async {
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'ListView',
        'children': <Object?>[
          <String, Object?>{'type': 'SizedBox', 'height': 260},
          <String, Object?>{
            'type': 'AnchoredOverlay',
            'visible': true,
            'placement': 'bottomStart',
            'gap': 6,
            'dismissOnTapOutside': false,
            'anchor': <String, Object?>{
              'type': 'Container',
              'height': 40,
              'child': <String, Object?>{
                'type': 'Text',
                'data': 'Moving anchor',
              },
            },
            'overlay': <String, Object?>{
              'type': 'Container',
              'height': 50,
              'child': <String, Object?>{
                'type': 'Text',
                'data': 'Moving overlay',
              },
            },
          },
          <String, Object?>{'type': 'SizedBox', 'height': 600},
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
    final before =
        tester.getTopLeft(find.text('Moving overlay')).dy -
        tester.getTopLeft(find.text('Moving anchor')).dy;

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -90));
    await tester.pumpAndSettle();

    expect(find.text('Moving overlay'), findsOneWidget);
    final after =
        tester.getTopLeft(find.text('Moving overlay')).dy -
        tester.getTopLeft(find.text('Moving anchor')).dy;
    expect(after, closeTo(before, 0.5));

    await tester.drag(find.byType(Scrollable).first, const Offset(0, -400));
    await tester.pumpAndSettle();
    expect(find.text('Moving overlay'), findsNothing);

    await tester.drag(find.byType(Scrollable).first, const Offset(0, 400));
    await tester.pumpAndSettle();
    expect(find.text('Moving overlay'), findsOneWidget);
  });

  testWidgets(
    'AnchoredOverlay positions above its anchor and dismisses outside',
    (tester) async {
      final events = <Map<String, Object?>>[];
      final renderer = JsUiRenderer(onEvent: events.add);
      addTearDown(renderer.dispose);
      final node = JsUiNode.fromMap(<String, Object?>{
        'type': 'Scaffold',
        'body': <String, Object?>{
          'type': 'Center',
          'child': <String, Object?>{
            'type': 'AnchoredOverlay',
            'visible': true,
            'placement': 'topStart',
            'gap': 8,
            'offset': <String, Object?>{'x': 6, 'y': 8},
            'matchAnchorWidth': true,
            'consumeOutsideTap': true,
            'onDismissed': <String, Object?>{'method': 'anchorDismissed'},
            'anchor': <String, Object?>{
              'type': 'Container',
              'width': 140,
              'height': 40,
              'child': <String, Object?>{'type': 'Text', 'data': 'Anchor'},
            },
            'overlay': <String, Object?>{
              'type': 'Container',
              'height': 60,
              'color': '#ffffff',
              'child': <String, Object?>{'type': 'Text', 'data': 'Popover'},
            },
          },
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

      expect(find.text('Popover'), findsOneWidget);
      expect(
        tester.getBottomLeft(find.text('Popover')).dy,
        lessThan(tester.getTopLeft(find.text('Anchor')).dy),
      );
      final popoverContainer = find
          .ancestor(of: find.text('Popover'), matching: find.byType(Container))
          .first;
      final anchorContainer = find
          .ancestor(of: find.text('Anchor'), matching: find.byType(Container))
          .first;
      expect(tester.getSize(popoverContainer).width, 140);
      expect(
        tester.getBottomLeft(popoverContainer).dy,
        closeTo(tester.getTopLeft(anchorContainer).dy - 16, 0.5),
      );

      await tester.tapAt(const Offset(8, 8));
      await tester.pumpAndSettle();
      expect(events.last['method'], 'anchorDismissed');
    },
  );

  testWidgets('Overlay renders arbitrary aligned content and dismisses', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = JsUiRenderer(onEvent: events.add);
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
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

  testWidgets('Overlay honors a shrink-wrapped Column child', (tester) async {
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Overlay',
        'visible': true,
        'transition': 'none',
        'child': <String, Object?>{
          'type': 'Container',
          'padding': 20,
          'child': <String, Object?>{
            'type': 'Column',
            'mainAxisSize': 'min',
            'children': <Object?>[
              <String, Object?>{'type': 'Text', 'data': 'Compact overlay'},
              <String, Object?>{'type': 'Text', 'data': 'Short body'},
            ],
          },
        },
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

    final container = find
        .ancestor(
          of: find.text('Compact overlay'),
          matching: find.byType(Container),
        )
        .first;
    expect(tester.getSize(container).height, lessThan(160));
  });

  testWidgets('Overlay closes declaratively without firing onDismissed', (
    tester,
  ) async {
    var visible = true;
    final events = <Map<String, Object?>>[];
    final renderer = JsUiRenderer(onEvent: events.add);
    addTearDown(renderer.dispose);

    JsUiNode schema() => JsUiNode.fromMap(<String, Object?>{
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

  testWidgets('renderer without buildContext uses the unified overlay layer', (
    tester,
  ) async {
    var visible = true;
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    JsUiNode schema() => JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'AlertDialog',
        'visible': visible,
        'titleText': 'Unified dialog',
      },
    });

    Widget harness() => MaterialApp(home: renderer.build(schema()));

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Unified dialog'), findsOneWidget);

    visible = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('Unified dialog'), findsNothing);
  });

  testWidgets('removing one modal closes its route instead of the top route', (
    tester,
  ) async {
    var showFirst = true;
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    JsUiNode schema() => JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'Column',
        'children': <Object?>[
          <String, Object?>{
            'type': 'AlertDialog',
            'visible': showFirst,
            'titleText': 'First modal',
          },
          <String, Object?>{
            'type': 'AlertDialog',
            'visible': true,
            'titleText': 'Second modal',
          },
        ],
      },
    });

    Widget harness() => MaterialApp(
      home: Builder(
        builder: (context) => renderer.build(schema(), buildContext: context),
      ),
    );

    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('First modal'), findsOneWidget);
    expect(find.text('Second modal'), findsOneWidget);

    showFirst = false;
    await tester.pumpWidget(harness());
    await tester.pumpAndSettle();
    expect(find.text('First modal'), findsNothing);
    expect(find.text('Second modal'), findsOneWidget);
  });

  testWidgets('unmounting the overlay layer removes its active modal route', (
    tester,
  ) async {
    var mounted = true;
    late StateSetter rebuild;
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
      'type': 'Scaffold',
      'body': <String, Object?>{
        'type': 'AlertDialog',
        'visible': true,
        'titleText': 'Owned modal',
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) {
            rebuild = setState;
            return mounted
                ? renderer.build(node, buildContext: context)
                : const SizedBox.shrink();
          },
        ),
      ),
    );
    await tester.pumpAndSettle();
    expect(find.text('Owned modal'), findsOneWidget);

    rebuild(() => mounted = false);
    await tester.pumpAndSettle();
    expect(find.text('Owned modal'), findsNothing);
  });

  testWidgets('slideDown enters from above and reverses on close', (
    tester,
  ) async {
    final renderer = JsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = JsUiNode.fromMap(<String, Object?>{
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
    late final JsUiRenderer renderer;
    renderer = JsUiRenderer(
      onEvent: (event) {
        if (event['method'] == 'close') {
          rebuild(() => visible = false);
        }
      },
    );
    addTearDown(renderer.dispose);

    JsUiNode schema() => JsUiNode.fromMap(<String, Object?>{
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
    late final JsUiRenderer renderer;
    renderer = JsUiRenderer(
      onEvent: (event) {
        if (event['method'] == 'close') {
          closes += 1;
          rebuild(() => visible = false);
        }
      },
    );
    addTearDown(renderer.dispose);

    JsUiNode schema() => JsUiNode.fromMap(<String, Object?>{
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

  testWidgets('SnackBar sync does not look up a deactivated overlay context', (
    tester,
  ) async {
    late BuildContext staleContext;
    const layerKey = ValueKey<String>('persistent-overlay-layer');

    await tester.pumpWidget(
      MaterialApp(
        home: Builder(
          builder: (context) {
            staleContext = context;
            return const SizedBox.shrink();
          },
        ),
      ),
    );

    Widget host(List<JsUiOverlayIntent> intents) => MaterialApp(
      home: Scaffold(
        body: JsUiOverlayLayer(
          key: layerKey,
          overlayContext: staleContext,
          intents: intents,
          child: const SizedBox.expand(),
        ),
      ),
    );

    await tester.pumpWidget(host(const <JsUiOverlayIntent>[]));
    await tester.pump();
    await tester.pumpWidget(
      host(const <JsUiOverlayIntent>[
        JsUiSnackBarOverlayIntent(
          signature: 'late-snack',
          content: Text('Safe SnackBar'),
          duration: Duration(seconds: 1),
        ),
      ]),
    );
    await tester.pump();

    expect(tester.takeException(), isNull);
    expect(find.text('Safe SnackBar'), findsOneWidget);
  });
}
