import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_example/pages/quickjs_ui/integrated/quickjs_ui_weather_demo_page.dart';

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
}
