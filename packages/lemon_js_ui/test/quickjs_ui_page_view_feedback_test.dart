import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  testWidgets(
    'PageView delayed echoes after dragging out and back preserve the settled page',
    (tester) async {
      var page = 0;
      final timers = <Timer>[];
      final events = <int>[];
      late StateSetter update;
      final renderer = JsUiRenderer(
        onEvent: (event) {
          final index = event['index']! as int;
          events.add(index);
          timers.add(
            Timer(const Duration(seconds: 1), () => update(() => page = index)),
          );
        },
      );
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return renderer.build(
                  JsUiNode.fromMap({
                    'type': 'PageView',
                    'page': page,
                    'loop': true,
                    'onPageChanged': {'method': 'changed'},
                    'children': [
                      for (var i = 0; i < 3; i++)
                        {'type': 'Text', 'data': '$i'},
                    ],
                  }),
                );
              },
            ),
          ),
        ),
      );
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      final start = controller.page!;
      final gesture = await tester.startGesture(
        tester.getCenter(find.byType(PageView)),
      );
      await gesture.moveBy(const Offset(-500, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.moveBy(const Offset(500, 0));
      await tester.pump(const Duration(milliseconds: 100));
      await gesture.up();
      await tester.pumpAndSettle();
      expect(events, [1, 0]);
      for (var i = 0; i < 30; i++) {
        await tester.pump(const Duration(milliseconds: 50));
        expect(controller.page, start);
      }
      expect(events, [1, 0]);
      for (final timer in timers) {
        timer.cancel();
      }
      await tester.pumpWidget(const SizedBox());
      renderer.dispose();
    },
  );

  testWidgets(
    'PageView command token distinguishes an explicit jump from a pending echo',
    (tester) async {
      var page = 0;
      var token = 0;
      late StateSetter update;
      final renderer = JsUiRenderer(onEvent: (_) {});
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: StatefulBuilder(
              builder: (context, setState) {
                update = setState;
                return renderer.build(
                  JsUiNode.fromMap({
                    'type': 'PageView',
                    'page': page,
                    'pageCommandToken': token,
                    'onPageChanged': {'method': 'changed'},
                    'children': [
                      for (var i = 0; i < 3; i++)
                        {'type': 'Text', 'data': '$i'},
                    ],
                  }),
                );
              },
            ),
          ),
        ),
      );
      final controller = tester
          .widget<PageView>(find.byType(PageView))
          .controller!;
      controller.jumpToPage(1);
      await tester.pumpAndSettle();
      controller.jumpToPage(2);
      await tester.pumpAndSettle();
      update(() => page = 1); // Old echo of page 1.
      await tester.pumpAndSettle();
      expect(controller.page, 2);
      update(() => token++); // Explicit command to the same page 1.
      await tester.pumpAndSettle();
      expect(controller.page, 1);
      await tester.pumpWidget(const SizedBox());
      renderer.dispose();
    },
  );

  for (final count in [2, 3]) {
    for (final delayMs in [0, 2500, 3500, 7000]) {
      testWidgets(
        'PageView $count pages with ${delayMs}ms feedback keeps advancing once',
        (tester) async {
          var page = 0;
          final timers = <Timer>[];
          final events = <int>[];
          late final JsUiRenderer renderer;
          late StateSetter update;
          renderer = JsUiRenderer(
            onEvent: (event) {
              final index = event['index']! as int;
              events.add(index);
              timers.add(
                Timer(
                  Duration(milliseconds: delayMs),
                  () => update(() => page = index),
                ),
              );
            },
          );
          await tester.pumpWidget(
            MaterialApp(
              home: Scaffold(
                body: StatefulBuilder(
                  builder: (context, setState) {
                    update = setState;
                    return renderer.build(
                      JsUiNode.fromMap({
                        'type': 'PageView',
                        'page': page,
                        'loop': true,
                        'autoPlay': true,
                        'autoPlayIntervalMs': 3000,
                        'scrollDurationMs': 300,
                        'onPageChanged': {'method': 'changed'},
                        'children': [
                          for (var i = 0; i < count; i++)
                            {'type': 'Text', 'data': 'page $i'},
                        ],
                      }),
                    );
                  },
                ),
              ),
            ),
          );
          final controller = tester
              .widget<PageView>(find.byType(PageView))
              .controller!;
          final start = controller.page!;
          for (var elapsed = 0; elapsed < 22000; elapsed += 50) {
            await tester.pump(const Duration(milliseconds: 50));
            // Automatic paging must never move backward, even when old echoes arrive.
            expect(
              controller.page,
              greaterThanOrEqualTo(start + (events.length - 1).clamp(0, 100)),
            );
          }
          expect(events, [for (var i = 1; i <= events.length; i++) i % count]);
          expect(events.length, 6);
          expect(controller.page, start + 6);
          for (final timer in timers) {
            timer.cancel();
          }
          await tester.pumpWidget(const SizedBox());
          renderer.dispose();
        },
      );
    }
  }
}
