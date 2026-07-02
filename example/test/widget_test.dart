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
import 'package:quickjs_example/pages/quickjs_ui_host_capabilities_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_navigation_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_network_counter_page.dart';
import 'package:quickjs_example/pages/quickjs_ui_permission_page.dart';
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

  testWidgets('registers quickjs_ui host capabilities page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiHostCapabilitiesPage()),
    );

    expect(find.text('QuickJS UI 宿主能力'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('调用 toast'));
    expect(find.text('调用 toast'), findsOneWidget);
    expect(find.text('调用 navigationIntent'), findsOneWidget);
    expect(find.text('调用 dialog'), findsOneWidget);
    expect(find.text('调用 snackbar'), findsOneWidget);
    expect(find.text('调用 bottom sheet'), findsOneWidget);
    expect(find.text('调用 add(20, 22)'), findsOneWidget);
    await _pumpUntilFound(tester, find.textContaining('已挂载 API'));
    expect(find.textContaining('toast'), findsWidgets);
    expect(find.textContaining('navigationIntent'), findsWidgets);
    await _pumpUntilFound(tester, find.textContaining('生命周期：mount'));
    expect(find.textContaining('生命周期：mount'), findsOneWidget);
    expect(find.text('检查 network 默认关闭'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui permission policy page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiPermissionPage()));

    expect(find.text('QuickJS UI 权限策略'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('结果：不限制策略 已加载'));
    expect(find.text('权限测试 JS 页面'), findsWidgets);
    expect(find.text('结果：不限制策略 已加载'), findsOneWidget);

    await tester.ensureVisible(find.text('限制策略：允许'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('结果：限制策略：允许 已加载'));
    expect(find.text('结果：限制策略：允许 已加载'), findsOneWidget);

    await tester.ensureVisible(find.text('限制策略：拒绝'));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.textContaining('权限拦截：QuickjsUiPermissionException'),
    );
    expect(
      find.textContaining('权限拦截：QuickjsUiPermissionException'),
      findsOneWidget,
    );
  });

  testWidgets('runs quickjs_ui native and JSUI navigation page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: QuickjsUiNavigationPage()));

    expect(find.text('QuickJS UI 页面互通'), findsOneWidget);
    expect(find.text('打开 JSUI 详情页'), findsOneWidget);

    await tester.tap(find.text('打开 JSUI 详情页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 详情页'));

    expect(find.text('JSUI 详情页'), findsOneWidget);
    expect(find.text('itemId: 42'), findsWidgets);
    expect(find.text('打开原生设置页'), findsOneWidget);
    expect(find.text('打开未注册页面'), findsOneWidget);

    await tester.tap(find.text('打开未注册页面'));
    await tester.pump();
    await _pumpUntilFound(tester, find.textContaining('missing route rejected'));

    expect(find.textContaining('quickjs-ui.navigation.missing'), findsOneWidget);

    await tester.tap(find.text('打开原生设置页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('原生设置页'));

    expect(find.text('此页由 JSUI navigationIntent 打开。'), findsOneWidget);
    expect(find.textContaining('itemId: 42'), findsWidgets);

    await tester.tap(find.text('保存并返回结果'));
    await tester.pump();
    await _pumpUntilFound(tester, find.textContaining('"saved":true'));

    expect(find.textContaining('"saved":true'), findsOneWidget);
    expect(find.textContaining('"source":"jsui-detail"'), findsOneWidget);

    await tester.tap(find.text('返回原生列表页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.textContaining('from'));

    expect(find.text('QuickJS UI 页面互通'), findsOneWidget);
    expect(find.textContaining('from: jsui-detail'), findsOneWidget);
    expect(find.textContaining('itemId: 42'), findsWidgets);
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
