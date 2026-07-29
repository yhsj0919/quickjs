import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/pages/example_index_page.dart';

void main() {
  testWidgets('Lab tab exposes every particle demo', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: ExampleIndexPage()));

    expect(find.text('实验室'), findsOneWidget);
    await tester.tap(find.text('实验室'));
    await tester.pumpAndSettle();

    for (final title in <String>[
      'Particle FX · 星际穿梭',
      'Particle FX · 霓虹星系',
      'Particle FX · 萤火虫花园',
      'Particle FX · 能量爆发',
      'Canvas 控件 · 弧形功率仪表盘',
      'Canvas 特效 · Snappable 灰飞烟灭',
      'Universal FX · 任意控件本地动画',
      'Performance Lab · 自适应效果质量',
    ]) {
      final finder = find.text(title);
      if (finder.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          finder,
          200,
          scrollable: _verticalScrollable(),
        );
      }
      expect(finder, findsOneWidget);
    }
  });
}

Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;
