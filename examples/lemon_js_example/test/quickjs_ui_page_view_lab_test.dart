import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_example/pages/quickjs_ui/lab/quickjs_ui_page_view_lab_page.dart';

void main() {
  testWidgets(
    'PageView lab exposes feedback comparison and playback controls',
    (tester) async {
      await tester.pumpWidget(const MaterialApp(home: JsUiPageViewLabPage()));
      expect(find.byType(PageView), findsOneWidget);
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('实际索引 1 · 受控 page 1'), findsOneWidget);
      await tester.tap(find.text('回写 page'));
      await tester.pump();
      await tester.tap(find.text('启动自动翻页'));
      await tester.pump();
      await tester.pump(const Duration(seconds: 3));
      await tester.pumpAndSettle();
      expect(find.text('实际索引 2 · 受控 page 1'), findsOneWidget);
      await tester.tap(find.text('暂停自动翻页'));
      await tester.pump();
      await tester.tap(find.text('原生 PageView'));
      await tester.pumpAndSettle();
      await tester.tap(find.text('下一页'));
      await tester.pumpAndSettle();
      expect(find.text('实际索引 1 · 受控 page 0'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
      expect(tester.takeException(), isNull);
    },
  );
}
