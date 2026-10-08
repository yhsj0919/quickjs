import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

JsPlugin page() => JsUiPagePlugin.source(
  id: 'api-contract',
  version: '1.0.0',
  source: '''
import { Page, Text } from 'quickjs_ui';
export default Page({
  createState() { return {value: 0}; },
  build(state) { return Text(String(state.value)); }
});
''',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'a cancelled old-page event cannot report an error after unload',
    () async {
      final controller = JsUiController();
      addTearDown(controller.close);
      await controller.loadPlugin(page());
      final event = controller.dispatch({'method': 'missing'});
      final cleanup = controller.unload();
      await Future.wait([event, cleanup]);
      expect(controller.error, isNull);
      await controller.loadPlugin(page());
      expect(controller.error, isNull);
    },
  );

  test('unloaded controller is empty without a placeholder session', () async {
    final controller = JsUiController();
    addTearDown(controller.close);
    await controller.loadPlugin(page());
    await controller.unload();
    await controller.unload();
    expect(controller.engine, isNull);
    expect(controller.props, isEmpty);
    expect(controller.features, isEmpty);
    expect(controller.node, isNull);
    expect(controller.exportPageSnapshot(), isNotNull);
    await controller.loadPlugin(page());
    expect(controller.error, isNull);
    expect(controller.node, isNotNull);
  });

  test('obsolete asynchronous source cannot replace a newer page', () async {
    final controller = JsUiController();
    addTearDown(controller.close);
    final oldSource = Completer<JsPlugin>();
    final oldLoad = controller.load(
      ({bool forceRefresh = false}) => oldSource.future,
    );
    await controller.loadPlugin(page(), initialProps: {'request': 'new'});
    oldSource.complete(page());
    await oldLoad;
    expect(controller.error, isNull);
    expect(controller.props['request'], 'new');
    expect(controller.isLoading, isFalse);
  });

  test(
    'attached engine unload serializes immediate replacement loads',
    () async {
      final engine = await JsEngine.create();
      final controller = JsUiController(engine: engine);
      addTearDown(() async {
        await controller.close();
        await engine.dispose();
      });
      await controller.loadPlugin(page());
      final cleanup = controller.unload();
      final load = controller.loadPlugin(page());
      await Future.wait([cleanup, load]);
      expect(controller.error, isNull);
      expect(controller.node, isNotNull);
      expect(controller.engine, same(engine));
    },
  );

  test('close waits for an in-progress unload', () async {
    final engine = await JsEngine.create();
    final controller = JsUiController(engine: engine);
    addTearDown(engine.dispose);
    await controller.loadPlugin(page());
    await Future.wait([controller.unload(), controller.close()]);
    final replacement = JsUiController(engine: engine);
    await replacement.close();
  });

  test('unload revokes the page and allows a fresh load', () async {
    final controller = JsUiController();
    addTearDown(controller.close);
    await controller.loadPlugin(page());
    await controller.setState({'value': 7});
    await controller.unload();
    expect(controller.node, isNull);
    expect(controller.plugin, isNull);
    expect(controller.features, isEmpty);
    await controller.loadPlugin(page());
    expect(controller.error, isNull);
    expect((controller.state as Map)['value'], 0);
  });

  testWidgets(
    'replacing a view controller loads the same source into the new controller',
    (tester) async {
      final first = JsUiController();
      final second = JsUiController();
      addTearDown(first.close);
      addTearDown(second.close);
      final plugin = page();
      Future<void> show(JsUiController controller) async {
        await tester.pumpWidget(
          MaterialApp(home: JsUiView.plugin(plugin, controller: controller)),
        );
        for (var i = 0; i < 50 && controller.node == null; i++) {
          await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)),
          );
          await tester.pump();
        }
        expect(controller.error, isNull);
        expect(controller.node, isNotNull);
      }

      await show(first);
      await show(second);
      await tester.pumpWidget(const SizedBox());
      await tester.runAsync(() async {
        await first.close();
        await second.close();
      });
    },
  );
  test('registration rejects conflicts and replacement is explicit', () {
    final registry = JsUiComponentRegistry.defaults();
    expect(
      () => registry.register('Text', (_, _) => const SizedBox()),
      throwsStateError,
    );
    registry.replace('Text', (_, _) => const SizedBox());
    expect(
      () => registry.replace('Missing', (_, _) => const SizedBox()),
      throwsStateError,
    );
  });

  test(
    'prebuilt plugin reload preserves state while restart resets it',
    () async {
      final controller = JsUiController(
        devOptions: const JsUiDevOptions(preserveStateOnReload: true),
      );
      addTearDown(controller.close);
      await controller.loadPlugin(page());
      expect(controller.error, isNull);
      await controller.setState({'value': 7});
      expect(controller.error, isNull);
      expect((controller.state as Map)['value'], 7);
      await controller.reload(forceRefresh: true);
      expect(controller.error, isNull);
      expect((controller.state as Map)['value'], 7);
      await controller.restart();
      expect((controller.state as Map)['value'], 0);
    },
  );
}
