import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/pages/example_index_page.dart';

void main() {
  testWidgets('Particle FX tab exposes every particle demo at the end', (
    tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: ExampleIndexPage()));

    expect(find.text('Particle FX'), findsOneWidget);
    await tester.tap(find.text('Particle FX'));
    await tester.pumpAndSettle();

    expect(find.text('QuickJS UI Canvas 模拟时钟'), findsOneWidget);
    expect(find.text('Particle FX · 星际穿梭'), findsOneWidget);
    expect(find.text('Particle FX · 霓虹星系'), findsOneWidget);
    expect(find.text('Particle FX · 萤火虫花园'), findsOneWidget);
    expect(find.text('Particle FX · 能量爆发'), findsOneWidget);
    expect(find.text('Canvas 控件 · 弧形功率仪表盘'), findsOneWidget);
    expect(find.text('Canvas 特效 · Snappable 灰飞烟灭'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Universal FX · 任意控件本地动画'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Universal FX · 任意控件本地动画'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Control System · 状态与结构插槽'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Control System · 状态与结构插槽'), findsOneWidget);
    await tester.scrollUntilVisible(
      find.text('Performance Lab · 自适应效果质量'),
      200,
      scrollable: find.byType(Scrollable).last,
    );
    expect(find.text('Performance Lab · 自适应效果质量'), findsOneWidget);
  });
}
