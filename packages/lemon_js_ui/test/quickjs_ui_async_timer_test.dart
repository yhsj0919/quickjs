import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/lemon_js_ui_session.dart';

const pageSource = '''
import {Page, Text} from 'quickjs_ui';
export default Page({
  createState() { return {count: 0}; },
  onMount(state, data, props, event, context) {
    setTimeout(() => context.actions.tick().catch(() => {}), 20);
  },
  async tick() {
    return {count: await globalThis.__jsHostMethods['test.delayed']()};
  },
  build(state) { return Text(String(state.count)); },
});
''';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'timer-started async host call updates without another user event',
    () async {
      var calls = 0;
      final controller = JsUiController();
      addTearDown(controller.dispose);
      await controller.loadPlugin(
        JsUiPagePlugin.source(
          id: 'test.async_timer',
          version: '1.0.0',
          source: pageSource,
        ),
        features: [
          JsFeatures(
            name: 'test.delayed',
            methods: [
              JsHostMethod(
                name: 'test.delayed',
                callback: (_, _) async {
                  calls++;
                  await Future<void>.delayed(const Duration(milliseconds: 80));
                  return 1;
                },
              ),
            ],
          ),
        ],
      );
      await controller.lifecycle(JsUiLifecycle.mount);
      await Future<void>.delayed(const Duration(milliseconds: 500));
      expect(controller.error, isNull);
      expect(calls, 1);
      expect((controller.state as Map)['count'], 1);
    },
  );

  test(
    'pending async work schedules a pump, settled idle page stops',
    () async {
      final pending = Completer<int>();
      final session = JsUiSession();
      addTearDown(session.dispose);
      await session.loadPlugin(
        JsUiPagePlugin.source(
          id: 'test.pending_timer',
          version: '1.0.0',
          source: pageSource,
        ),
        features: [
          JsFeatures(
            name: 'test.delayed',
            methods: [
              JsHostMethod(
                name: 'test.delayed',
                callback: (_, _) => pending.future,
              ),
            ],
          ),
        ],
      );
      expect((await session.pumpTimers()).nextDelay, isNull);
      await session.lifecycle(JsUiLifecycle.mount, render: false);
      await Future<void>.delayed(const Duration(milliseconds: 40));
      final waiting = await session.pumpTimers();
      expect(waiting.changed, isFalse);
      expect(waiting.nextDelay, isNotNull);
      pending.complete(1);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      final settled = await session.pumpTimers();
      expect(settled.changed, isTrue);
      expect((session.state as Map)['count'], 1);
      expect(settled.nextDelay, isNull);
      expect((await session.pumpTimers()).changed, isFalse);
    },
  );
}
