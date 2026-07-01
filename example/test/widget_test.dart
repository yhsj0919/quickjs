import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/app.dart';
import 'package:quickjs_example/example_pages.dart';
import 'package:quickjs_example/pages/js_call_dart_plugin_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_bundle_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_controls_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_diff_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_error_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_network_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_profile_form_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_schema_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_todo_page.dart';
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
    scrollable: find.byType(Scrollable).last,
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
      final title = find.text(page.title);
      await _scrollUntilFound(tester, title);
      expect(title, findsOneWidget);
      expect(find.text(page.description), findsOneWidget);
    }
  });

  testWidgets('registers quickjs_ui counter page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiCounterPage()));

    expect(find.text('QuickJS UI Counter'), findsOneWidget);
    expect(find.byTooltip('Refresh render'), findsOneWidget);
    expect(find.byTooltip('Restart page'), findsOneWidget);
    expect(find.byTooltip('Reload source'), findsOneWidget);
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
    expect(find.text('Refresh'), findsOneWidget);
    expect(find.text('Reload source'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui controls page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiControlsPage()));

    expect(find.text('QuickJS UI Controls'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('ThemeData tokens from JS'));
    expect(find.text('ThemeData tokens from JS'), findsOneWidget);
    await _scrollUntilFound(tester, find.text('Third-party image resource'));
    expect(find.text('Third-party image resource'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui todo page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiTodoPage()));

    expect(find.text('QuickJS UI Todo List'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Add todo'));
    expect(find.textContaining('QuickJS UI todo error'), findsNothing);
    expect(find.text('Add todo'), findsOneWidget);
    await _scrollUntilFound(tester, find.text('Review quickjs_ui 0.2 roadmap'));
    expect(find.text('Review quickjs_ui 0.2 roadmap'), findsOneWidget);
    expect(find.text('Try ThemeData tokens from JS'), findsOneWidget);
    expect(find.text('Add todo'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui profile form page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiProfileFormPage()),
    );

    expect(find.text('QuickJS UI Profile Form'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Save profile'));
    expect(find.textContaining('QuickJS UI profile form error'), findsNothing);
    expect(find.text('Ada Lovelace'), findsWidgets);
    expect(find.text('ada@example.com'), findsWidgets);
    expect(find.text('Save profile'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'invalid-email');
    await _pumpUntilFound(tester, find.text('Enter a valid email address'));
    await tester.tap(find.text('Save profile'));
    await _pumpUntilFound(
      tester,
      find.text('Fix validation errors before saving'),
    );
    expect(find.text('Enter a valid email address'), findsOneWidget);
    expect(find.text('Fix validation errors before saving'), findsOneWidget);

    await tester.enterText(find.byType(TextField).at(1), 'ada@quickjs.dev');
    await _pumpUntilFound(tester, find.text('Ada Lovelace · ada@quickjs.dev'));
    await tester.tap(find.text('Save profile'));
    await _pumpUntilFound(tester, find.text('Saved profile for Ada Lovelace'));
    expect(find.text('Enter a valid email address'), findsNothing);
    expect(find.text('Saved profile for Ada Lovelace'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui diff refresh page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiDiffPage()));

    expect(find.text('QuickJS UI 局部刷新'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Refresh changed node'));
    expect(find.textContaining('QuickJS UI diff error'), findsNothing);
    expect(find.text('Stable builds: 1'), findsOneWidget);
    expect(find.text('Changed builds: 1'), findsOneWidget);

    await tester.tap(find.text('Refresh changed node'));
    await _pumpUntilFound(tester, find.text('Changed keyed node from JS #1'));

    expect(find.text('Stable builds: 1'), findsOneWidget);
    expect(find.text('Changed builds: 2'), findsOneWidget);
    expect(find.text('Changed keyed node from JS #1'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui JSON schema page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiSchemaPage()));

    expect(find.text('QuickJS UI JSON Schema'), findsOneWidget);
    await _pumpUntilFound(tester, find.textContaining('quickjs_ui UI schema'));
    expect(find.textContaining('12 node variants'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Pure JSON UI schema'));
    expect(find.text('Pure JSON UI schema'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui error overlay page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiErrorPage()));

    expect(find.text('QuickJS UI Error Overlay'), findsOneWidget);
    expect(
      find.textContaining('schema path: root.children[2]'),
      findsOneWidget,
    );
    expect(
      find.textContaining('resource: assets/quickjs_ui/controls_page.mjs'),
      findsOneWidget,
    );
    expect(find.textContaining('action: render'), findsOneWidget);
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
