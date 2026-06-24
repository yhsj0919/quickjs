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

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 100 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 50)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('renders example index', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());
    expect(find.text('01'), findsOneWidget);

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

    expect(
      find.text(examplePages.length.toString().padLeft(2, '0')),
      findsOneWidget,
    );
    expect(examplePages.last.title, 'Fetch');
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

  testWidgets('registers stream callback example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('流式 Callback');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('for-await'), findsOneWidget);
    expect(find.textContaining('JS sink'), findsOneWidget);
  });

  testWidgets('registers module example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Module');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('runtime module cache'), findsOneWidget);
    expect(find.textContaining('CommonJS'), findsWidgets);
  });

  testWidgets('registers npm bundle example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('NPM Bundle');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('单文件 asset'), findsOneWidget);
    expect(find.textContaining('compareValues()'), findsOneWidget);
  });

  testWidgets('registers fetch example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Fetch');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('QuickjsFetchMount'), findsOneWidget);
    expect(find.textContaining('HttpClient'), findsOneWidget);
    expect(find.textContaining('浏览器 fetch'), findsOneWidget);
  });

  testWidgets('registers host modules example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('宿主模块');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(
      find.textContaining('QuickjsRuntimeOptions.modules'),
      findsOneWidget,
    );
    expect(find.textContaining('CommonJS 宿主模块'), findsOneWidget);
    expect(find.textContaining('验证 cache'), findsOneWidget);
    expect(find.textContaining('debugInspect'), findsOneWidget);
    expect(find.textContaining('essential Buffer'), findsOneWidget);
    expect(find.textContaining('node preset'), findsOneWidget);
  });

  testWidgets('interacts with host mounts example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('能力批量挂载');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('QuickjsRuntimeOptions.mounts'), findsOneWidget);
    expect(find.textContaining('Quickjs.mount()'), findsOneWidget);
    expect(find.textContaining('provider'), findsOneWidget);

    await tester.ensureVisible(title);
    await tester.pumpAndSettle();
    await tester.tap(title);
    final readyStatus = find.text('runtime 已就绪：example-initial 已挂载');
    await _pumpUntilFound(tester, readyStatus);
    expect(readyStatus, findsOneWidget);

    await tester.tap(find.text('检查初始化挂载'));
    final initialResult = find.text('初始化 mount => 21/21');
    await _pumpUntilFound(tester, initialResult);
    expect(initialResult, findsOneWidget);

    await tester.tap(find.text('运行时挂载'));
    final runtimeResult = find.text(
      'Quickjs.mount() => 21/runtime-module-2/42',
    );
    await _pumpUntilFound(tester, runtimeResult);
    expect(runtimeResult, findsOneWidget);

    await tester.tap(find.text('替换运行时挂载'));
    final replacementResult = find.text(
      'replace mount => 21/runtime-module-3/63',
    );
    await _pumpUntilFound(tester, replacementResult);
    expect(replacementResult, findsOneWidget);

    expect(find.text('替换运行时挂载'), findsOneWidget);
  });

  testWidgets('registers web host environment example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Web 宿主环境');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('QuickjsHostMount.web()'), findsOneWidget);
    expect(find.textContaining('navigator'), findsOneWidget);
  });

  testWidgets('registers function handle example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Function Handle');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('evaluateHandle'), findsOneWidget);
    expect(find.textContaining('handle.call'), findsOneWidget);
    expect(find.textContaining('callAsync'), findsOneWidget);
    expect(find.textContaining('dispose'), findsOneWidget);
  });

  testWidgets('registers object proxy example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('对象代理');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('bindObject'), findsOneWidget);
    expect(find.textContaining('只读属性'), findsOneWidget);
    expect(find.textContaining('Promise 方法'), findsOneWidget);
    expect(find.textContaining('显式释放'), findsWidgets);
  });

  testWidgets('registers class binding example page', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Class Binding');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('bindClass'), findsOneWidget);
    expect(find.textContaining('new User'), findsOneWidget);
    expect(find.textContaining('await getter/method'), findsOneWidget);
  });

  testWidgets('registers console example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Console');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('onConsole'), findsOneWidget);
    expect(find.textContaining('console.log'), findsOneWidget);
  });

  testWidgets('registers web crypto example page', (WidgetTester tester) async {
    await tester.pumpWidget(const ExampleApp());

    final title = find.text('Web Crypto');
    if (title.evaluate().isEmpty) {
      await tester.scrollUntilVisible(
        title,
        120,
        scrollable: find.byType(Scrollable),
      );
    }
    expect(title, findsOneWidget);
    expect(find.textContaining('QuickjsWebCryptoMount()'), findsOneWidget);
    expect(find.textContaining('randomUUID'), findsOneWidget);
    expect(find.textContaining('getRandomValues'), findsOneWidget);
    expect(find.textContaining('subtle.digest'), findsOneWidget);
  });
}
