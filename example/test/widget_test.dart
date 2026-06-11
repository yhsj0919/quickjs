// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/app.dart';
import 'package:quickjs_example/example_pages.dart';

void main() {
  testWidgets('renders example index', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    for (final page in examplePages) {
      final title = find.text(page.title);
      if (title.evaluate().isEmpty) {
        await tester.scrollUntilVisible(
          title,
          120,
          scrollable: find.byType(Scrollable),
        );
      }
      expect(find.text(page.title), findsOneWidget);
      expect(find.text(page.description), findsOneWidget);
    }
  });

  testWidgets('registers resource limit example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('资源限制'), findsOneWidget);
    expect(find.textContaining('memoryLimitBytes'), findsOneWidget);
    expect(find.textContaining('stackLimitBytes'), findsOneWidget);
  });

  testWidgets('registers structured values example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    expect(find.text('结构化返回'), findsOneWidget);
    expect(find.textContaining('evaluateValue'), findsOneWidget);
  });

  testWidgets('registers timer event loop example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Timer 与事件循环');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('setTimeout'), findsOneWidget);
    expect(find.textContaining('setInterval'), findsOneWidget);
  });
}
