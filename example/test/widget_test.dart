import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/app.dart';
import 'package:quickjs_example/example_pages.dart';
import 'package:quickjs_example/pages/js_call_dart_plugin_page.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: find.byType(Scrollable),
  );
}

void main() {
  testWidgets('renders example index', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('01'), findsOneWidget);

    for (final page in examplePages) {
      final title = find.text(page.title);
      await _scrollUntilFound(tester, title);
      expect(title, findsOneWidget);
      expect(find.text(page.description), findsOneWidget);
    }

    expect(
      find.text(examplePages.length.toString().padLeft(2, '0')),
      findsOneWidget,
    );
  });

  testWidgets('registers core example pages', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    for (final marker in <String>[
      'memoryLimitBytes',
      'stackLimitBytes',
      'evaluateValue',
      'setTimeout',
      'setInterval',
      'for-await',
      'JS sink',
      'runtime module cache',
      'CommonJS',
      'compareValues()',
      'QuickjsFetchMount',
      'Axios/XHR',
    ]) {
      final finder = find.textContaining(marker);
      await _scrollUntilFound(tester, finder);
      expect(finder, findsWidgets);
    }
  });

  testWidgets('runs js-call-dart plugin example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsCallDartPluginPage()));

    expect(find.textContaining('JsCallDart'), findsOneWidget);
    for (var attempt = 0; attempt < 200; attempt++) {
      final button = tester.widget<FilledButton>(
        find.byType(FilledButton).first,
      );
      if (button.onPressed != null) {
        break;
      }
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 50)),
      );
      await tester.pump();
    }
    expect(
      tester.widget<FilledButton>(find.byType(FilledButton).first).onPressed,
      isNotNull,
    );
    expect(find.textContaining('test2'), findsOneWidget);
    expect(find.textContaining('Axios'), findsOneWidget);

    await tester.tap(find.byType(FilledButton).first);
    final dialog = find.text('JS Alert');
    await _pumpUntilFound(tester, dialog);
    expect(dialog, findsOneWidget);
    await tester.tap(find.text('OK'));
    await tester.pumpAndSettle();
    final result = find.textContaining('=>');
    await _pumpUntilFound(tester, result);
    expect(result, findsWidgets);
  });
}
