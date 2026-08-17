import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  group('quickjs_ui 0.4.3 dev tools', () {
    test('exports page snapshot with structured fields', () async {
      final engine = await JsEngine.create();
      final inspector = JsUiInspector();
      final controller = JsUiController(engine: engine, inspector: inspector);
      addTearDown(controller.dispose);

      await controller.loadPlugin(
        JsUiPagePlugin.source(
          id: 'quickjs_ui_dev_snapshot',
          version: '0.4.3',
          source: '''
import { Column, ElevatedButton, Page, Text } from 'quickjs_ui';

export default Page({
  name: 'SnapshotPage',
  metadata: { name: 'SnapshotPage' },
  createState() {
    return { count: 1 };
  },
  build(state, props, page) {
    return Column({
      children: [
        Text('Count: ' + state.count, { key: 'count' }),
        ElevatedButton({
          key: 'btn',
          child: Text('Add'),
          onPressed: page.increment()
        })
      ]
    });
  },
  increment(state) {
    return { ...state, count: state.count + 1 };
  }
});
''',
        ),
        initialProps: const <String, Object?>{'title': 'dev'},
      );

      await controller.dispatch(const <String, Object?>{'method': 'increment'});
      final performance = JsUiPerformanceController(
        mode: JsUiPerformanceMode.low,
      );
      inspector.recordPerformance(performance.snapshot);
      performance.dispose();

      final snapshot = controller.exportPageSnapshot().toMap();
      expect(snapshot['props'], const <String, Object?>{'title': 'dev'});
      expect(snapshot['state'], isA<Map>());
      expect(snapshot['schema'], isA<Map>());
      expect(snapshot['manifest'], isA<Map>());
      expect(snapshot['lastAction'], isA<Map>());
      expect(snapshot['lifecycle'], isA<List>());
      expect((snapshot['lifecycle'] as List).isNotEmpty, isTrue);
      expect(snapshot['resources'], isA<List>());
      expect(
        snapshot['performance'],
        containsPair('quality', JsUiEffectQuality.low.name),
      );
    });

    test('records renderer diff stats for keyed nodes', () async {
      final engine = await JsEngine.create();
      final inspector = JsUiInspector();
      final controller = JsUiController(engine: engine, inspector: inspector);
      addTearDown(controller.dispose);
      final renderer = JsUiRenderer(
        onEvent: controller.dispatch,
        onDiffStats: inspector.recordDiff,
      );

      await controller.loadPlugin(
        JsUiPagePlugin.source(
          id: 'quickjs_ui_dev_diff',
          version: '0.4.3',
          source: '''
import { Text, Page } from 'quickjs_ui';

export default Page({
  createState() {
    return { label: 'stable' };
  },
  build(state) {
    return Text(state.label, { key: 'stable' });
  }
});
''',
        ),
      );

      renderer.build(controller.node!);
      final firstDiff = inspector.lastDiff;
      expect(firstDiff, isNotNull);
      expect(firstDiff!.rebuilt, 1);
      expect(firstDiff.reused, 0);

      await controller.setState(const <String, Object?>{'label': 'changed'});
      renderer.build(controller.node!);

      final secondDiff = inspector.lastDiff!;
      expect(secondDiff.rebuilt, 1);
      expect(secondDiff.reused, 0);

      await controller.refresh();
      renderer.build(controller.node!);

      final thirdDiff = inspector.lastDiff!;
      expect(thirdDiff.reused, 1);
      expect(thirdDiff.rebuilt, 0);
    });

    testWidgets('defers inspector notifications until after build', (
      WidgetTester tester,
    ) async {
      final inspector = JsUiInspector();
      var buildCount = 0;

      await tester.pumpWidget(
        MaterialApp(
          home: ListenableBuilder(
            listenable: inspector,
            builder: (context, _) {
              buildCount += 1;
              if (buildCount == 1) {
                inspector.recordDiff(const JsUiDiffStats(rebuilt: 1));
              }
              return Text('builds: $buildCount');
            },
          ),
        ),
      );

      expect(buildCount, 1);
      await tester.pump();
      expect(buildCount, 2);
      expect(inspector.lastDiff?.rebuilt, 1);
    });

    testWidgets('error overlay includes structured details', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: JsUiErrorOverlay(
              error: JsUiError(
                kind: JsUiErrorKind.schema,
                message: 'Unknown quickjs_ui node type: Missing',
                cause: FormatException('Unknown quickjs_ui node type: Missing'),
                source: 'asset',
                resource: 'assets/quickjs_ui/dev_panel_page.mjs',
                schemaPath: 'root.children[1]',
                route: 'dev_panel',
                action: 'render',
              ),
            ),
          ),
        ),
      );

      expect(find.text('quickjs_ui error'), findsOneWidget);
      expect(find.textContaining('FormatException'), findsOneWidget);
      expect(find.text('source: asset'), findsOneWidget);
      expect(
        find.text('resource: assets/quickjs_ui/dev_panel_page.mjs'),
        findsOneWidget,
      );
      expect(find.text('schema path: root.children[1]'), findsOneWidget);
      expect(find.text('route: dev_panel'), findsOneWidget);
      expect(find.text('action: render'), findsOneWidget);
    });

    test('unified errors preserve cause and add operation context', () {
      final base = JsUiError.wrap(
        const FormatException('bad schema'),
        kind: JsUiErrorKind.schema,
        operation: 'render',
        schemaPath: 'root.children[0]',
      );
      final enriched = JsUiError.wrap(
        base,
        kind: JsUiErrorKind.render,
        action: 'openDetails',
        route: 'details',
      );

      expect(identical(enriched.cause, base.cause), isTrue);
      expect(enriched.kind, JsUiErrorKind.schema);
      expect(enriched.operation, 'render');
      expect(enriched.action, 'openDetails');
      expect(enriched.route, 'details');
      expect(enriched.schemaPath, 'root.children[0]');
    });

    test('records lifecycle timeline in predictable order', () async {
      final engine = await JsEngine.create();
      final inspector = JsUiInspector();
      final controller = JsUiController(engine: engine, inspector: inspector);
      addTearDown(controller.dispose);

      await controller.loadPlugin(
        JsUiPagePlugin.source(
          id: 'quickjs_ui_dev_lifecycle',
          version: '0.4.3',
          source: '''
import { Text, Page } from 'quickjs_ui';

export default Page({
  onMount(state) {
    return { ...state, mounted: true };
  },
  createState() {
    return { mounted: false };
  },
  build(state) {
    return Text(state.mounted ? 'mounted' : 'pending');
  }
});
''',
        ),
      );

      await controller.lifecycle(JsUiLifecycle.mount);
      await controller.routeLifecycle(JsUiLifecycle.show);
      controller.recordAppLifecycle('pause');
      await controller.dispatch(const <String, Object?>{
        'type': 'tap',
        'method': 'noop',
      });

      final phases = inspector.lifecycleTimeline
          .map((event) => '${event.phase}:${event.type}')
          .toList();
      expect(phases, contains('widget:load'));
      expect(phases, contains('widget:mount'));
      expect(phases, contains('route:show'));
      expect(phases, contains('app:pause'));
      expect(phases, contains('action:noop'));
    });
  });
}
