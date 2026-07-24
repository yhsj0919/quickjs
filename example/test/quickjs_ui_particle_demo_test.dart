import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const assets = <String>[
    'assets/quickjs_ui/canvas_clock_page.mjs',
    'assets/quickjs_ui/particle_starfield_page.mjs',
    'assets/quickjs_ui/particle_galaxy_page.mjs',
    'assets/quickjs_ui/particle_fireflies_page.mjs',
    'assets/quickjs_ui/particle_energy_burst_page.mjs',
    'assets/quickjs_ui/arc_gauge_page.mjs',
    'assets/quickjs_ui/snappable_dust_page.mjs',
  ];

  for (final path in assets) {
    test('$path builds a locally animated Canvas scene', () async {
      final source = await rootBundle.loadString(path);
      final engine = await Quickjs.create();
      final session = QuickjsUiSession(engine: engine);
      addTearDown(session.dispose);

      await session.loadPlugin(
        QuickjsUiPagePlugin.singleFile(
          id: path.split('/').last.replaceAll('.mjs', ''),
          version: '1.0.0',
          source: source,
        ),
      );

      final canvas = _findCanvas(session.node!);
      expect(canvas, isNotNull);
      expect(canvas!.props['onFrame'], isNull);
      final staticCommands = canvas.props['staticCommands']! as List<Object?>;
      final commands = canvas.props['commands']! as List<Object?>;
      expect(staticCommands.isNotEmpty || commands.isNotEmpty, isTrue);
      expect(commands.length, lessThanOrEqualTo(10000));
    });
  }

  test('universal effects demo animates a regular Flutter node', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/universal_effects_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);
    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'universal_effects',
        version: '1.0.0',
        source: source,
      ),
    );

    final card = _findNodeByKey(session.node!, 'animated-effect-card');
    expect(card, isNotNull);
    expect(card!.type, 'Container');
    expect(card.props['opacity'], isA<Map<Object?, Object?>>());
    expect(card.props['transform'], isA<Map<Object?, Object?>>());
    expect(card.props['blur'], isA<Map<Object?, Object?>>());
  });

  test('control states demo exposes states and structural slots', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/control_states_slots_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);
    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'control_states_slots',
        version: '1.0.0',
        source: source,
      ),
    );

    final button = _findNode(session.node!, 'ElevatedButton')!;
    expect(button.props['leading'], isA<Map<Object?, Object?>>());
    expect(button.props['trailing'], isA<Map<Object?, Object?>>());
    final states = button.props['stateStyles']! as Map<Object?, Object?>;
    expect(
      states.keys,
      containsAll(<Object?>[
        'normal',
        'hovered',
        'focused',
        'pressed',
        'disabled',
      ]),
    );
    final input = _findNode(session.node!, 'TextField')!;
    expect(input.props['prefix'], isA<Map<Object?, Object?>>());
    expect(input.props['suffix'], isA<Map<Object?, Object?>>());
  });

  test('control motion demo declares local state transitions', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/control_state_transitions_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);
    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'control_state_transitions',
        version: '1.0.0',
        source: source,
      ),
    );

    for (final type in <String>[
      'ElevatedButton',
      'Switch',
      'Slider',
      'TextField',
    ]) {
      final control = _findNode(session.node!, type)!;
      expect(control.props['stateTransition'], isA<Map<Object?, Object?>>());
      expect(control.props['stateStyles'], isA<Map<Object?, Object?>>());
    }
    final button = _findNode(session.node!, 'ElevatedButton')!;
    final states = button.props['stateStyles']! as Map<Object?, Object?>;
    expect(
      (states['pressed']! as Map<Object?, Object?>)['scale'],
      closeTo(0.955, 0.0001),
    );
  });

  test('overlay system demo opens and closes on the first command', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/overlay_system_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);
    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'overlay_system',
        version: '1.0.0',
        source: source,
      ),
    );

    expect(_findNode(session.node!, 'Overlay')!.props['visible'], isFalse);
    await session.dispatch(<String, Object?>{
      'method': 'open',
      'alignment': 'center',
      'transition': 'fadeScale',
    });
    expect(_findNode(session.node!, 'Overlay')!.props['visible'], isTrue);

    await session.dispatch(<String, Object?>{'method': 'close'});
    expect(_findNode(session.node!, 'Overlay')!.props['visible'], isFalse);
  });

  test('Canvas 2D-style API records familiar operations', () async {
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);
    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'canvas_2d_style',
        version: '1.0.0',
        source: '''
import { animate, Canvas, Page } from 'quickjs_ui';

export default Page({
  build() {
    return Canvas({
      width: 100,
      height: 100,
      staticDraw(ctx) {
        ctx.fillStyle = '#112233';
        ctx.fillRect(0, 0, 100, 100);
      },
      draw(ctx) {
        ctx.save();
        ctx.translate(50, 50);
        ctx.rotate(animate(0, Math.PI * 2, {
          durationMs: 1000,
          repeat: true
        }));
        ctx.beginPath();
        ctx.arc(0, 0, 20, 0, Math.PI * 2);
        ctx.fillStyle = '#22d3ee';
        ctx.fill();
        ctx.restore();
      }
    });
  }
});
''',
      ),
    );

    final canvas = session.node!;
    expect(canvas.type, 'Canvas');
    final staticCommands = canvas.props['staticCommands']! as List<Object?>;
    final commands = canvas.props['commands']! as List<Object?>;
    expect((staticCommands.single as Map<Object?, Object?>)['op'], 'rect');
    expect(
      commands.map((command) => (command as Map<Object?, Object?>)['op']),
      <Object?>['save', 'translate', 'rotate', 'path', 'restore'],
    );
    final path = commands[3]! as Map<Object?, Object?>;
    final segments = path['segments']! as List<Object?>;
    expect((segments.single as Map<Object?, Object?>)['op'], 'arc');
  });

  test('arc gauge responds to pointer coordinates', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/arc_gauge_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'arc_gauge',
        version: '1.0.0',
        source: source,
      ),
    );

    final initialCanvas = _findCanvas(session.node!)!;
    expect(initialCanvas.props['onPointerDown'], <String, Object?>{
      'method': 'beginGauge',
    });

    await session.dispatch(<String, Object?>{
      'method': 'beginGauge',
      'x': 180,
      'y': 64,
    });

    final updatedCanvas = _findCanvas(session.node!)!;
    expect(updatedCanvas.props['semanticsLabel'], '功率 50%');
  });

  test('snappable dust toggles between visible and animated states', () async {
    final source = await rootBundle.loadString(
      'assets/quickjs_ui/snappable_dust_page.mjs',
    );
    final engine = await Quickjs.create();
    final session = QuickjsUiSession(engine: engine);
    addTearDown(session.dispose);

    await session.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'snappable_dust',
        version: '1.0.0',
        source: source,
      ),
    );

    expect(_findNode(session.node!, 'SnapshotBoundary'), isNull);
    final initialCanvas = _findCanvas(session.node!)!;
    expect(initialCanvas.props['sceneKey'], isNull);
    expect(initialCanvas.props['commands'], isEmpty);
    expect(initialCanvas.props['staticCommands'], isNotEmpty);

    await session.dispatch(<String, Object?>{'method': 'startTransition'});
    expect(session.state, containsPair('mode', 'preparing'));
    expect(_findNode(session.node!, 'SnapshotBoundary'), isNotNull);

    await session.dispatch(<String, Object?>{
      'method': 'captured',
      'role': 'source',
      'variant': 0,
      'snapshotId': 'snapshot:transition-source:1',
    });
    await session.dispatch(<String, Object?>{
      'method': 'captured',
      'role': 'target',
      'variant': 0,
      'snapshotId': 'snapshot:transition-target:2',
    });

    var canvas = _findCanvas(session.node!)!;
    expect(canvas.props['sceneKey'], 'snapshot-particle-transition');
    final retainedCommands = canvas.props['commands']! as List<Object?>;
    expect(retainedCommands, hasLength(1));
    expect(retainedCommands.single, <String, Object?>{
      'op': 'snapshotParticleGrid',
      'sourceSlot': 'source',
      'targetSlot': 'target',
      'x': 38,
      'y': 120,
      'width': 284,
      'height': 220,
      'columns': 24,
      'rows': 18,
      'bucketCount': 16,
      'staggerMs': 16,
      'travelMs': 920,
      'fadeMs': 760,
    });
    expect(canvas.props['paused'], isFalse);
    expect(canvas.props['resources'], <String, Object?>{
      'source': 'snapshot:transition-source:1',
      'target': 'snapshot:transition-target:2',
    });

    expect(canvas.props['onAnimationEnd'], <String, Object?>{
      'method': 'finishTransition',
      'payload': <String, Object?>{
        'run': (session.state! as Map<Object?, Object?>)['run'],
      },
    });
    var transitionState = session.state! as Map<Object?, Object?>;
    await session.dispatch(<String, Object?>{
      'method': 'finishTransition',
      'run': transitionState['run'],
    });
    expect(session.state, containsPair('mode', 'visible'));
    expect(session.state, containsPair('currentVariant', 0));
    expect(session.state, containsPair('transitionType', 'different'));
    expect(_findNode(session.node!, 'SnapshotBoundary'), isNull);

    await session.dispatch(<String, Object?>{'method': 'startTransition'});
    expect(session.state, containsPair('mode', 'preparing'));
    await session.dispatch(<String, Object?>{
      'method': 'captured',
      'role': 'source',
      'variant': 0,
      'snapshotId': 'snapshot:transition-source:3',
    });
    await session.dispatch(<String, Object?>{
      'method': 'captured',
      'role': 'target',
      'variant': 1,
      'snapshotId': 'snapshot:transition-target:4',
    });
    transitionState = session.state! as Map<Object?, Object?>;
    await session.dispatch(<String, Object?>{
      'method': 'finishTransition',
      'run': transitionState['run'],
    });
    expect(session.state, containsPair('currentVariant', 1));
    expect(_findNode(session.node!, 'SnapshotBoundary'), isNull);
  });
}

QuickjsUiNode? _findCanvas(QuickjsUiNode node) {
  if (node.type == 'Canvas') return node;
  for (final child in node.children) {
    final result = _findCanvas(child);
    if (result != null) return result;
  }
  return null;
}

QuickjsUiNode? _findNode(QuickjsUiNode node, String type) {
  if (node.type == type) return node;
  for (final child in node.children) {
    final result = _findNode(child, type);
    if (result != null) return result;
  }
  return null;
}

QuickjsUiNode? _findNodeByKey(QuickjsUiNode node, String key) {
  if (node.key == key) return node;
  for (final child in node.children) {
    final result = _findNodeByKey(child, key);
    if (result != null) return result;
  }
  return null;
}
