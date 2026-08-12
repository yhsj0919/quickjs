import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_example/pages/core/hybrid_extension_page.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 500 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'hybrid demo keeps manifest, Core and JSUI in separate assets',
    () async {
      final sources = await Future.wait(<Future<String>>[
        rootBundle.loadString('assets/extensions/hybrid_demo/manifest.json'),
        rootBundle.loadString('assets/extensions/hybrid_demo/service/main.mjs'),
        rootBundle.loadString('assets/extensions/hybrid_demo/ui/login.mjs'),
      ]);

      expect(sources[0], contains('content-source/v1'));
      expect(sources[1], contains('export function getHome'));
      expect(sources[2], contains("from 'quickjs_extensions/plugin_service'"));
    },
  );

  testWidgets('hybrid demo calls Core and opens its JSUI route', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 1000);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(const MaterialApp(home: HybridExtensionPage()));
    await _pumpUntilFound(tester, find.text('打开插件 JSUI 登录页'));

    final visibleText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    expect(
      find.text('调用插件 Core 方法'),
      findsOneWidget,
      reason: '当前页面文本：$visibleText',
    );
    await tester.tap(find.text('调用插件 Core 方法'));
    final coreResult = find.byWidgetPredicate(
      (widget) =>
          widget is SelectableText &&
          (widget.data ?? '').contains('Core 返回的首页数据'),
    );
    await _pumpUntilFound(tester, coreResult);

    final coreResultText = tester
        .widgetList<Text>(find.byType(Text))
        .map((widget) => widget.data)
        .whereType<String>()
        .toList();
    final selectableText = tester
        .widgetList<SelectableText>(find.byType(SelectableText))
        .map((widget) => widget.data)
        .toList();
    expect(
      coreResult,
      findsOneWidget,
      reason: 'Core 调用后的页面文本：$coreResultText；结果：$selectableText',
    );
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('打开插件 JSUI 登录页'));
    await tester.pump();
    await _pumpUntilFound(tester, find.text('调用 Core 登录'));

    expect(find.text('插件提供的登录页'), findsOneWidget);
    expect(find.text('尚未登录'), findsOneWidget);
    expect(tester.takeException(), isNull);

    await tester.tap(find.text('调用 Core 登录'));
    await _pumpUntilFound(tester, find.text('登录成功：demo@example.com'));

    expect(find.text('登录成功：demo@example.com'), findsOneWidget);
    expect(tester.takeException(), isNull);
  });
}
