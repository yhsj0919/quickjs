// This is a basic Flutter widget test.
//
// To perform an interaction with a widget in your test, use the WidgetTester
// utility in the flutter_test package. For example, you can send tap and scroll
// gestures. You can also use WidgetTester to find child widgets in the widget
// tree, read text, and verify that the values of widget properties are correct.

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/app.dart';
import 'package:quickjs_example/example_pages.dart';

void main() {
  testWidgets('renders example index', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    for (final page in examplePages) {
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
}
