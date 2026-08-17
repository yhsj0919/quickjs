import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_example/app.dart';
import 'package:lemon_js_example/example_page_spec.dart';
import 'package:lemon_js_example/example_pages.dart';
import 'package:lemon_js_example/pages/core/js_call_dart_plugin_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/foundation/quickjs_ui_controls_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/foundation/quickjs_ui_scroll_transition_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/getting_started/quickjs_ui_bundle_counter_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/getting_started/quickjs_ui_counter_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/getting_started/quickjs_ui_schema_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_custom_components_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_dev_panel_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_diff_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_error_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_host_capabilities_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_navigation_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_network_inspector_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/platform/quickjs_ui_permission_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/scenario/quickjs_ui_profile_form_page.dart';
import 'package:lemon_js_example/pages/quickjs_ui/scenario/quickjs_ui_todo_page.dart';
import 'package:lemon_js_example/pages/core/zip_plugin_page.dart';
import 'package:lemon_js_example/quickjs_ui_example_pages.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

Future<void> _disposeTestWidget(WidgetTester tester) async {
  await tester.pump(const Duration(milliseconds: 1));
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(milliseconds: 1));
}

Future<void> _scrollUntilFound(WidgetTester tester, Finder finder) async {
  if (finder.evaluate().isNotEmpty) {
    return;
  }
  await tester.scrollUntilVisible(
    finder,
    120,
    scrollable: _verticalScrollable(),
  );
}

Finder _verticalScrollable() => find
    .byWidgetPredicate(
      (widget) =>
          widget is Scrollable && widget.axisDirection == AxisDirection.down,
    )
    .first;

void main() {
  test('example theme uses the Windows Chinese system UI font', () {
    expect(
      buildExampleTheme(
        TargetPlatform.windows,
      ).textTheme.bodyMedium?.fontFamily,
      'Microsoft YaHei UI',
    );
    expect(
      buildExampleTheme(
        TargetPlatform.android,
      ).textTheme.bodyMedium?.fontFamily,
      isNot('Microsoft YaHei UI'),
    );
  });

  testWidgets('renders example index', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('Core'), findsOneWidget);
    expect(find.text('入门加载'), findsOneWidget);
    expect(find.text('UI 基础'), findsOneWidget);
    expect(find.text('宿主工程'), findsOneWidget);
    expect(find.text('场景'), findsOneWidget);
    expect(find.text('实验室'), findsOneWidget);
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
    final groups = <(String, List<ExamplePageSpec>)>[
      ('入门加载', jsUiGettingStartedExamplePages),
      ('UI 基础', jsUiFoundationExamplePages),
      ('宿主工程', jsUiPlatformExamplePages),
      ('场景', jsUiScenarioExamplePages),
      ('实验室', jsUiLabExamplePages),
    ];
    for (final (tab, pages) in groups) {
      await tester.tap(find.text(tab));
      await tester.pumpAndSettle();
      for (final page in pages) {
        final title = find.text(page.title);
        await _scrollUntilFound(tester, title);
        expect(title, findsOneWidget);
        expect(find.text(page.description), findsOneWidget);
      }
    }
  });

  testWidgets('registers quickjs_ui counter page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiCounterPage()));

    expect(find.text('单文件计数器'), findsOneWidget);
    expect(find.byTooltip('Refresh render'), findsOneWidget);
    expect(find.byTooltip('Restart page'), findsOneWidget);
    expect(find.byTooltip('Reload source'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui bundle counter page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiBundleCounterPage()));

    expect(find.text('多文件模块计数器'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  testWidgets('registers quickjs_ui controls page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiControlsPage()));

    expect(find.text('布局与媒体基础'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('网络图片'));
    expect(find.text('网络图片'), findsOneWidget);
    await _scrollUntilFound(tester, find.text('本地图片与 Stack'));
    expect(find.text('本地图片与 Stack'), findsOneWidget);
    await _scrollUntilFound(tester, find.text('Placeholder 与 VerticalDivider'));
    expect(find.text('Placeholder 与 VerticalDivider'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui custom components page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JsUiCustomComponentsPage()),
    );

    expect(find.text('自定义组件'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Size: medium'));
    expect(
      find.textContaining('QuickJS UI custom components error'),
      findsNothing,
    );
    expect(find.text('0.4 custom renderer registry'), findsOneWidget);
    expect(find.text('Size: medium'), findsOneWidget);
    expect(find.text('Medium'), findsOneWidget);
    expect(find.text('Reset'), findsOneWidget);
  });

  testWidgets('quickjs_ui custom components survive resize during dispatch', (
    WidgetTester tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: JsUiCustomComponentsPage()),
    );
    await _pumpUntilFound(tester, find.text('Size: medium'));

    for (var index = 0; index < 20; index += 1) {
      tester.view.physicalSize = Size(
        index.isEven ? 640 : 960,
        index.isEven ? 720 : 540,
      );
      await tester.pump();
      await tester.tap(find.byType(Switch));
      await tester.pump();
    }
    await tester.pumpAndSettle();

    expect(
      find.textContaining('QuickJS UI custom components error'),
      findsNothing,
    );
    expect(find.text('Size: medium'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui video player plugin page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JsUiVideoPlayerPluginPage()),
    );

    expect(find.text('视频播放器插件'), findsOneWidget);
    await _pumpUntilFound(
      tester,
      find.textContaining('VideoPlayer plugin demo'),
    );
    expect(
      find.textContaining('QuickJS UI video player plugin error'),
      findsNothing,
    );
    expect(
      find.textContaining('Imported from quickjs_ui/video_player'),
      findsOneWidget,
    );
    await _disposeTestWidget(tester);
  });

  testWidgets('registers quickjs_ui 0.4.2 scroll transition page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JsUiScrollTransitionPage()),
    );

    expect(find.text('滚动控制与嵌套滚动'), findsOneWidget);
    await _pumpUntilFound(
      tester,
      find.text('验证滚动位置事件、按 stable key 定位和独立嵌套滚动区域。'),
    );
    expect(find.textContaining('QuickJS UI 0.4.2 error'), findsNothing);
    expect(find.text('定位到 epsilon'), findsOneWidget);
    expect(find.text('嵌套 SingleChildScrollView'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui 0.4.3 dev panel page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiDevPanelPage()));

    expect(find.text('开发调试面板'), findsWidgets);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('Schema'), findsOneWidget);
    expect(find.text('生命周期'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('计数: 0'));
    expect(find.text('开发调试面板'), findsWidgets);
    expect(find.text('增加'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui network inspector page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(
      const MaterialApp(home: JsUiNetworkInspectorPage()),
    );

    expect(find.text('网络请求调试'), findsOneWidget);
    expect(find.text('状态'), findsOneWidget);
    expect(find.text('Schema'), findsOneWidget);
    expect(find.text('网络'), findsOneWidget);
    expect(find.byType(JsUiInspectorPanel), findsOneWidget);
  });

  testWidgets('registers quickjs_ui todo page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiTodoPage()));

    expect(find.text('待办列表'), findsOneWidget);
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
    await tester.pumpWidget(const MaterialApp(home: JsUiProfileFormPage()));

    expect(find.text('个人资料表单'), findsOneWidget);
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
    await tester.pumpWidget(const MaterialApp(home: JsUiDiffPage()));

    expect(find.text('局部刷新诊断'), findsOneWidget);
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
    await tester.pumpWidget(const MaterialApp(home: JsUiSchemaPage()));

    expect(find.text('JSON Schema 页面'), findsOneWidget);
    await _pumpUntilFound(tester, find.textContaining('quickjs_ui UI schema'));
    expect(find.textContaining('node variants'), findsOneWidget);
    await _pumpUntilFound(tester, find.text('Pure JSON UI schema'));
    expect(find.text('Pure JSON UI schema'), findsOneWidget);
  });

  testWidgets('registers quickjs_ui error overlay page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiErrorPage()));

    expect(find.text('错误诊断浮层'), findsOneWidget);
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
      const MaterialApp(home: JsUiHostCapabilitiesPage()),
    );

    expect(find.text('宿主能力调用'), findsOneWidget);
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
    await _disposeTestWidget(tester);
  });

  testWidgets('registers quickjs_ui permission policy page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsUiPermissionPage()));

    expect(find.text('页面权限策略'), findsOneWidget);
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
      find.textContaining('权限拦截：JsUiPermissionException'),
    );
    expect(find.textContaining('权限拦截：JsUiPermissionException'), findsOneWidget);
  });

  testWidgets('runs quickjs_ui native and JSUI navigation page', (
    WidgetTester tester,
  ) async {
    final navigationLogs = <String>[];
    final previousDebugPrint = debugPrint;
    debugPrint = (String? message, {int? wrapWidth}) {
      if (message != null) {
        navigationLogs.add(message);
      }
    };
    addTearDown(() {
      debugPrint = previousDebugPrint;
    });

    await tester.pumpWidget(const MaterialApp(home: JsUiNavigationPage()));

    expect(find.text('原生与 JS 页面互通'), findsOneWidget);
    expect(find.text('打开 JSUI 详情页'), findsOneWidget);

    await tester.tap(find.text('打开 JSUI 详情页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 详情页'));

    expect(find.text('JSUI 详情页'), findsOneWidget);
    expect(find.text('itemId: 42'), findsWidgets);
    expect(find.text('detail count: 0'), findsOneWidget);
    expect(find.text('详情计数 +1'), findsOneWidget);
    expect(find.textContaining('打开 JSUI 子页'), findsOneWidget);
    expect(find.text('打开原生设置页'), findsOneWidget);
    expect(find.text('打开未注册页面'), findsOneWidget);

    await tester.tap(find.text('详情计数 +1'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('detail count: 1'));

    await tester.tap(find.textContaining('打开 JSUI 子页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 子页'));
    await tester.pumpAndSettle();

    expect(find.text('JSUI 子页'), findsOneWidget);
    expect(find.text('parent count: 1'), findsOneWidget);
    expect(find.text('child local count: 11'), findsOneWidget);
    final parentLeave = navigationLogs.indexWhere(
      (line) => line.contains('detail onRouteLeave'),
    );

    await tester.tap(find.textContaining('替换当前 JSUI 子页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('source: jsui-child-replaced'));
    await tester.pumpAndSettle();

    expect(find.text('JSUI 子页'), findsOneWidget);
    expect(find.text('source: jsui-child-replaced'), findsOneWidget);
    expect(find.text('parent count: 30'), findsOneWidget);
    expect(find.text('child local count: 40'), findsOneWidget);

    await tester.tap(find.text('子页计数 +1'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('child local count: 41'));

    await tester.tap(find.text('返回 JSUI 详情页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 详情页'));
    await tester.pumpAndSettle();
    await _pumpUntilFound(tester, find.textContaining('"from":"jsui-child"'));

    expect(find.text('detail count: 1'), findsOneWidget);
    expect(find.textContaining('"from":"jsui-child"'), findsOneWidget);
    expect(find.textContaining('"localCount":41'), findsOneWidget);

    await tester.tap(find.textContaining('打开 JSUI 子页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 子页'));
    await tester.pumpAndSettle();

    await tester.pageBack();
    await tester.pump();
    await _pumpUntilFound(tester, find.text('JSUI 详情页'));
    await tester.pumpAndSettle();

    expect(find.text('JSUI 子页'), findsNothing);
    expect(find.text('detail count: 1'), findsOneWidget);

    await tester.tap(find.text('打开未注册页面'));
    await tester.pump();
    await _pumpUntilFound(
      tester,
      find.textContaining('missing route rejected'),
    );

    expect(
      find.textContaining('quickjs-ui.navigation.missing'),
      findsOneWidget,
    );

    await tester.tap(find.text('打开原生设置页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('原生设置页'));
    await tester.pumpAndSettle();

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

    expect(find.text('原生与 JS 页面互通'), findsOneWidget);
    expect(find.textContaining('from: jsui-detail'), findsOneWidget);
    expect(find.textContaining('itemId: 42'), findsWidgets);
    final childEnter = navigationLogs.indexWhere(
      (line) => line.contains('child onRouteEnter'),
    );
    debugPrint = previousDebugPrint;
    expect(parentLeave, greaterThanOrEqualTo(0));
    expect(childEnter, greaterThan(parentLeave));
  });

  testWidgets('registers core example pages', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    for (final marker in <String>[
      'memoryLimitBytes',
      'stackLimitBytes',
      'eval',
      'setTimeout',
      'setInterval',
      'for-await',
      'JS sink',
      'runtime module cache',
      'CommonJS',
      'compareValues()',
      'FetchFeatures',
      'Axios/XHR',
      'JsZipPlugin.asset()',
    ]) {
      final finder = find.textContaining(marker);
      await _scrollUntilFound(tester, finder);
      expect(finder, findsWidgets);
    }
  });

  testWidgets('registers zip plugin example page', (WidgetTester tester) async {
    await tester.pumpWidget(const MaterialApp(home: ZipPluginPage()));

    expect(find.text('ZIP 插件包'), findsOneWidget);
    expect(find.textContaining('JsZipPlugin.asset()'), findsOneWidget);
    expect(find.text('hello'), findsOneWidget);
    expect(find.text('profile'), findsOneWidget);
    expect(find.text('manifest'), findsOneWidget);
  });

  testWidgets('runs js-call-dart plugin example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const MaterialApp(home: JsCallDartPluginPage()));

    expect(find.text('JS 调用 Dart 插件'), findsOneWidget);
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
