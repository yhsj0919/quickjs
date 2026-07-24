import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  testWidgets('Canvas renders a batch and forwards gestures', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 200,
      'height': 120,
      'backgroundColor': '#ffffff',
      'onTap': <String, Object?>{'method': 'canvasTapped'},
      'commands': <Object?>[
        <String, Object?>{'op': 'save'},
        <String, Object?>{'op': 'translate', 'x': 100, 'y': 60},
        <String, Object?>{
          'op': 'circle',
          'cx': 0,
          'cy': 0,
          'radius': 40,
          'stroke': '#222222',
          'strokeWidth': 3,
        },
        <String, Object?>{
          'op': 'line',
          'x1': 0,
          'y1': 8,
          'x2': 0,
          'y2': -30,
          'stroke': '#e53935',
          'strokeWidth': 2,
          'strokeCap': 'round',
        },
        <String, Object?>{'op': 'restore'},
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    final canvas = find.byWidgetPredicate(
      (widget) =>
          widget is CustomPaint &&
          widget.painter.runtimeType.toString().contains('CanvasPainter'),
    );
    expect(canvas, findsOneWidget);
    expect(tester.getSize(canvas), const Size(200, 120));
    await tester.tap(canvas);
    expect(events.single['method'], 'canvasTapped');
  });

  testWidgets('Canvas emits lifecycle-safe sampled frame events', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'key': 'animated',
      'width': 80,
      'height': 80,
      'commands': const <Object?>[],
      'frameIntervalMs': 100,
      'onFrame': <String, Object?>{'method': 'advance'},
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: events.add).build(node)),
    );
    await tester.pump(const Duration(milliseconds: 120));

    expect(events, isNotEmpty);
    expect(events.last['method'], 'advance');
    expect(events.last['timestampMs'], isA<int>());
    expect(events.last['elapsedMs'], isA<double>());
    expect(events.last['deltaMs'], isA<double>());
    expect(events.last['frame'], isA<int>());

    final eventCount = events.length;
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    expect(events, hasLength(eventCount));
  });

  testWidgets('Canvas runs numeric animations without JS frame events', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 80,
      'height': 80,
      'staticCommands': <Object?>[
        <String, Object?>{
          'op': 'circle',
          'cx': 40,
          'cy': 40,
          'radius': 35,
          'fill': '#ffffff',
          'stroke': '#222222',
          'strokeWidth': 2,
        },
      ],
      'commands': <Object?>[
        <String, Object?>{'op': 'save'},
        <String, Object?>{'op': 'translate', 'x': 40, 'y': 40},
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
          'y1': 5,
          'x2': 0,
          'y2': -30,
          'stroke': '#ff0000',
        },
        <String, Object?>{'op': 'restore'},
      ],
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: events.add).build(node)),
    );
    for (var frame = 0; frame < 10; frame += 1) {
      await tester.pump(const Duration(microseconds: 8333));
    }

    expect(events, isEmpty);
    expect(tester.takeException(), isNull);
  });

  testWidgets('Canvas reports finite animation end after its final frame', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 40,
      'height': 40,
      'onAnimationEnd': <String, Object?>{'method': 'animationEnded'},
      'commands': <Object?>[
        <String, Object?>{
          'op': 'circle',
          'cx': 20,
          'cy': 20,
          'radius': <String, Object?>{'from': 2, 'to': 18, 'durationMs': 60},
          'fill': '#22d3ee',
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(home: QuickjsUiRenderer(onEvent: events.add).build(node)),
    );
    await tester.pump(const Duration(milliseconds: 30));
    expect(events, isEmpty);
    await tester.pump(const Duration(milliseconds: 40));
    expect(events.single['method'], 'animationEnded');
    await tester.pump(const Duration(milliseconds: 100));
    expect(events, hasLength(1));
  });

  testWidgets('Canvas retains, pauses and reverses a scene by reference', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    final registered = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'key': 'retained-canvas',
      'sceneKey': 'retained-particles',
      'paused': true,
      'commands': <Object?>[
        <String, Object?>{
          'op': 'circle',
          'cx': <String, Object?>{'from': 0, 'to': 40, 'durationMs': 100},
          'cy': 20,
          'radius': 4,
          'fill': '#22d3ee',
        },
      ],
    });
    await tester.pumpWidget(MaterialApp(home: renderer.build(registered)));
    await tester.pump(const Duration(milliseconds: 150));
    expect(events, isEmpty);

    final reference = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'key': 'retained-canvas',
      'sceneKey': 'retained-particles',
      'paused': false,
      'playToken': 1,
      'reverse': true,
      'onAnimationEnd': <String, Object?>{'method': 'reversed'},
    });
    await tester.pumpWidget(MaterialApp(home: renderer.build(reference)));
    await tester.pump(const Duration(milliseconds: 110));
    expect(events.single['method'], 'reversed');

    renderer.dispose();
    expect(() => renderer.build(reference), throwsFormatException);
  });

  testWidgets(
    'Canvas pause preserves progress and playToken starts a new generation',
    (tester) async {
      final events = <Map<String, Object?>>[];
      final renderer = QuickjsUiRenderer(onEvent: events.add);

      QuickjsUiNode node({required bool paused, required int playToken}) =>
          QuickjsUiNode.fromMap(<String, Object?>{
            'type': 'Canvas',
            'key': 'generation-canvas',
            'width': 40,
            'height': 40,
            'paused': paused,
            'playToken': playToken,
            'onAnimationEnd': <String, Object?>{'method': 'ended'},
            'commands': <Object?>[
              <String, Object?>{
                'op': 'circle',
                'cx': 20,
                'cy': 20,
                'radius': <String, Object?>{
                  'from': 2,
                  'to': 18,
                  'durationMs': 100,
                },
                'fill': '#22d3ee',
              },
            ],
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
    },
  );

  testWidgets('Canvas continuous animation neither completes nor reverses', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);

    QuickjsUiNode node({bool reverse = false}) =>
        QuickjsUiNode.fromMap(<String, Object?>{
          'type': 'Canvas',
          'key': 'continuous-canvas',
          'reverse': reverse,
          'onAnimationEnd': <String, Object?>{'method': 'ended'},
          'commands': <Object?>[
            <String, Object?>{
              'op': 'circle',
              'cx': <String, Object?>{
                'from': 0,
                'to': 40,
                'durationMs': 100,
                'repeat': true,
              },
              'cy': 20,
              'radius': 4,
              'fill': '#22d3ee',
            },
          ],
        });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node())));
    await tester.pump(const Duration(milliseconds: 350));
    expect(events, isEmpty);

    await tester.pumpWidget(
      MaterialApp(home: renderer.build(node(reverse: true))),
    );
    expect(tester.takeException(), isA<FormatException>());
    renderer.dispose();
  });

  testWidgets('Canvas removal cancels pending animation completion', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'key': 'removed-canvas',
      'onAnimationEnd': <String, Object?>{'method': 'ended'},
      'commands': <Object?>[
        <String, Object?>{
          'op': 'circle',
          'cx': 20,
          'cy': 20,
          'radius': <String, Object?>{'from': 2, 'to': 18, 'durationMs': 100},
          'fill': '#22d3ee',
        },
      ],
    });

    await tester.pumpWidget(MaterialApp(home: renderer.build(node)));
    await tester.pump(const Duration(milliseconds: 40));
    await tester.pumpWidget(const SizedBox.shrink());
    await tester.pump(const Duration(milliseconds: 200));
    expect(events, isEmpty);
    renderer.dispose();
  });

  test(
    'Canvas retained scene registry evicts oldest and clears on dispose',
    () {
      final renderer = QuickjsUiRenderer(onEvent: (_) {});
      for (var index = 0; index < 33; index += 1) {
        renderer.build(
          QuickjsUiNode.fromMap(<String, Object?>{
            'type': 'Canvas',
            'sceneKey': 'scene-$index',
            'commands': <Object?>[
              <String, Object?>{
                'op': 'circle',
                'cx': index,
                'cy': 1,
                'radius': 1,
                'fill': '#000000',
              },
            ],
          }),
        );
      }

      expect(renderer.canvasSceneRegistry.resolve('scene-0'), isNull);
      expect(renderer.canvasSceneRegistry.resolve('scene-1'), isNotNull);
      expect(renderer.canvasSceneRegistry.resolve('scene-32'), isNotNull);
      renderer.dispose();
      expect(renderer.canvasSceneRegistry.resolve('scene-32'), isNull);
    },
  );

  test(
    'Snapshot registry evicts oldest capture and clears on dispose',
    () async {
      final registry = QuickjsUiSnapshotRegistry(maxSnapshots: 2);
      final images = <ui.Image>[];
      for (var index = 0; index < 3; index += 1) {
        final recorder = ui.PictureRecorder();
        final canvas = ui.Canvas(recorder);
        canvas.drawColor(const Color(0xff000000), BlendMode.src);
        final picture = recorder.endRecording();
        images.add(await picture.toImage(2, 2));
        picture.dispose();
      }

      final first = registry.register(
        boundaryId: 'first',
        image: images[0],
        pixelRatio: 1,
      );
      final second = registry.register(
        boundaryId: 'second',
        image: images[1],
        pixelRatio: 1,
      );
      final third = registry.register(
        boundaryId: 'third',
        image: images[2],
        pixelRatio: 1,
      );

      expect(registry.length, 2);
      expect(registry.resolve(first.id), isNull);
      expect(registry.resolve(second.id), isNotNull);
      expect(registry.resolve(third.id), isNotNull);
      registry.dispose();
      expect(registry.length, 0);
    },
  );

  testWidgets('Canvas exposes local pointer coordinates', (tester) async {
    final events = <Map<String, Object?>>[];
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 100,
      'height': 100,
      'commands': const <Object?>[],
      'onPointerDown': <String, Object?>{'method': 'pointerDown'},
      'onPointerMove': <String, Object?>{'method': 'pointerMove'},
      'onPointerUp': <String, Object?>{'method': 'pointerUp'},
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Align(
          alignment: Alignment.topLeft,
          child: QuickjsUiRenderer(onEvent: events.add).build(node),
        ),
      ),
    );

    final gesture = await tester.startGesture(const Offset(20, 30));
    await gesture.moveTo(const Offset(28, 42));
    await gesture.up();

    expect(events.map((event) => event['method']), <Object?>[
      'pointerDown',
      'pointerMove',
      'pointerUp',
    ]);
    expect(events.first['x'], 20);
    expect(events.first['y'], 30);
    expect(events[1]['deltaX'], 8);
    expect(events[1]['deltaY'], 12);
  });

  testWidgets('SnapshotBoundary captures and Canvas draws its image handle', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = QuickjsUiRenderer(onEvent: events.add);
    final boundary = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'SnapshotBoundary',
      'key': 'capture-card',
      'captureToken': 0,
      'onCaptured': <String, Object?>{'method': 'captured'},
      'child': <String, Object?>{
        'type': 'Container',
        'width': 80,
        'height': 50,
        'decoration': <String, Object?>{'color': '#4f46e5'},
        'child': <String, Object?>{'type': 'Text', 'data': 'captured widget'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(home: Center(child: renderer.build(boundary))),
    );
    await tester.pump();
    await tester.pumpAndSettle();

    expect(events, isNotEmpty);
    expect(events.last['method'], 'captured');
    final snapshotId = events.last['snapshotId'];
    expect(snapshotId, startsWith('snapshot:capture-card:'));
    expect(events.last['width'], 80);
    expect(events.last['height'], 50);
    expect(renderer.snapshotRegistry.length, 1);

    final canvas = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 80,
      'height': 50,
      'commands': <Object?>[
        <String, Object?>{
          'op': 'image',
          'snapshotId': snapshotId,
          'dx': 0,
          'dy': 0,
          'dWidth': 80,
          'dHeight': 50,
        },
      ],
    });
    await tester.pumpWidget(
      MaterialApp(home: Center(child: renderer.build(canvas))),
    );
    await tester.pump();
    expect(tester.takeException(), isNull);

    final particleCanvas = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'width': 80,
      'height': 50,
      'resources': <String, Object?>{
        'source': snapshotId,
        'target': snapshotId,
      },
      'commands': <Object?>[
        <String, Object?>{
          'op': 'snapshotParticleGrid',
          'sourceSlot': 'source',
          'targetSlot': 'target',
          'x': 0,
          'y': 0,
          'width': 80,
          'height': 50,
          'columns': 8,
          'rows': 5,
          'bucketCount': 4,
          'staggerMs': 4,
          'travelMs': 60,
          'fadeMs': 40,
        },
      ],
      'onAnimationEnd': <String, Object?>{'method': 'particlesEnded'},
    });
    await tester.pumpWidget(
      MaterialApp(home: Center(child: renderer.build(particleCanvas))),
    );
    await tester.pump(const Duration(milliseconds: 16));
    expect(tester.takeException(), isNull);
    await tester.pump(const Duration(milliseconds: 60));
    expect(events.last['method'], 'particlesEnded');

    await tester.pumpWidget(const SizedBox.shrink());
    renderer.dispose();
    expect(renderer.snapshotRegistry.length, 0);
  });

  test('Canvas validates save/restore before paint', () {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'commands': <Object?>[
        <String, Object?>{'op': 'restore'},
      ],
    });
    expect(() => renderer.build(node), throwsFormatException);
  });

  test('Canvas validates native snapshot particle grid bounds', () {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Canvas',
      'commands': <Object?>[
        <String, Object?>{
          'op': 'snapshotParticleGrid',
          'sourceSlot': 'source',
          'targetSlot': 'target',
          'width': 80,
          'height': 50,
          'columns': 4097,
          'rows': 1,
          'bucketCount': 4,
          'staggerMs': 4,
          'travelMs': 60,
          'fadeMs': 40,
        },
      ],
    });

    expect(() => renderer.build(node), throwsFormatException);
  });
}
