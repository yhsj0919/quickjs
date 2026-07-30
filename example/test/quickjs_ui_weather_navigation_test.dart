import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/pages/quickjs_ui/scenario/quickjs_ui_weather_background_page.dart';
import 'package:quickjs_example/pages/quickjs_ui/scenario/quickjs_ui_weather_demo_page.dart';

Future<void> _pumpUntilMissing(WidgetTester tester, Finder finder) async {
  for (
    var attempt = 0;
    attempt < 200 && finder.evaluate().isNotEmpty;
    attempt++
  ) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('weather demo exposes a visible back button', (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        initialRoute: '/weather',
        routes: <String, WidgetBuilder>{
          '/': (_) => const Scaffold(body: Text('Examples')),
          '/weather': (_) => const QuickjsUiWeatherDemoPage(),
        },
      ),
    );
    await tester.pump();

    expect(find.byType(BackButton), findsOneWidget);
    await tester.tap(find.byType(BackButton));
    await tester.pumpAndSettle();
    expect(find.text('Examples'), findsOneWidget);
  });

  testWidgets('weather background redraws without loading after resize', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(1280, 1100);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiWeatherBackgroundPage()),
    );
    await _pumpUntilMissing(tester, find.byType(CircularProgressIndicator));

    tester.view.physicalSize = const Size(1400, 1200);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));

    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(find.textContaining('QuickJS UI demo error'), findsNothing);
    expect(find.textContaining('Weather background error'), findsNothing);
    expect(tester.takeException(), isNull);
  });
}
