import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/app.dart';
import 'package:quickjs_example/example_pages.dart';
import 'package:quickjs_example/pages/js_call_dart_plugin_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_bundle_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_network_counter_page.dart';
import 'package:quickjs_example/pages/zip_plugin_page.dart';
import 'package:quickjs_example/quickjs_ui_example_pages.dart';

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
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('quickjs_ui'), findsOneWidget);
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

  testWidgets('registers quickjs_ui example pages', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());
    await tester.tap(find.text('quickjs_ui'));
    await tester.pumpAndSettle();

    for (final page in quickjsUiExamplePages) {
      expect(find.text(page.title), findsOneWidget);
      expect(find.text(page.description), findsOneWidget);
    }
  });

  testWidgets('registers quickjs_ui counter page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiCounterPage()));

    expect(find.text('QuickJS UI Counter'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('registers quickjs_ui bundle counter page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiBundleCounterPage()),
    );

    expect(find.text('QuickJS UI Bundle Counter'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('registers quickjs_ui network counter page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiNetworkCounterPage()),
    );

    expect(find.text('QuickJS UI Network Counter'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
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
      'QuickjsZipPlugin.asset()',
    ]) {
      final finder = find.textContaining(marker);
      await _scrollUntilFound(tester, finder);
      expect(finder, findsWidgets);
    }
  });

  testWidgets('registers zip plugin example page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ZipPluginPage()));

    expect(find.text('Zip Plugin'), findsOneWidget);
    expect(find.textContaining('QuickjsZipPlugin.asset()'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('profile'), findsOneWidget);
    expect(find.text('manifest'), findsOneWidget);
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
