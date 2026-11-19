import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  testWidgets('loop scroll payload is JSON safe and ignores nested lists', (
    tester,
  ) async {
    final events = <Map<String, Object?>>[];
    final renderer = JsUiRenderer(onEvent: events.add);
    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(
          JsUiNode.fromMap({
            'type': 'PageView',
            'loop': true,
            'onScroll': {'method': 'scroll'},
            'children': [
              for (var i = 0; i < 3; i++)
                {
                  'type': 'SingleChildScrollView',
                  'children': [
                    {'type': 'SizedBox', 'height': 2000},
                  ],
                },
            ],
          }),
        ),
      ),
    );
    final controller = tester
        .widget<PageView>(find.byType(PageView))
        .controller!;
    expect(controller.position.maxScrollExtent, double.infinity);
    controller.jumpToPage(controller.page!.round() + 1);
    await tester.pumpAndSettle();
    expect(events, isNotEmpty);
    for (final event in events) {
      expect(() => jsonEncode(event), returnsNormally);
      expect(event['maxScrollExtent'], isNull);
    }
    events.clear();
    final nested = find.descendant(
      of: find.byType(SingleChildScrollView).first,
      matching: find.byType(Scrollable),
    );
    tester.state<ScrollableState>(nested).position.jumpTo(50);
    await tester.pumpAndSettle();
    expect(events, isEmpty);
    await tester.pumpWidget(const SizedBox());
    renderer.dispose();
  });
}
