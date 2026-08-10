import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_example/pages/quickjs_ui/foundation/quickjs_ui_temperature_chart_page.dart';

Future<void> _pumpUntilFound(WidgetTester tester, Finder finder) async {
  for (var attempt = 0; attempt < 200 && finder.evaluate().isEmpty; attempt++) {
    await tester.runAsync(
      () => Future<void>.delayed(const Duration(milliseconds: 20)),
    );
    await tester.pump();
  }
}

void main() {
  testWidgets('temperature chart loads and responds to pointer hover', (
    tester,
  ) async {
    tester.view.devicePixelRatio = 1;
    tester.view.physicalSize = const Size(900, 650);
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });

    await tester.pumpWidget(
      const MaterialApp(home: QuickjsUiTemperatureChartPage()),
    );
    await _pumpUntilFound(tester, find.text('一周温度趋势'));

    expect(find.text('一周温度趋势'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    final canvas = find.byType(CustomPaint).last;
    final center = tester.getCenter(canvas);
    final gesture = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await gesture.addPointer(location: center);
    await gesture.moveTo(center + const Offset(80, 0));
    await tester.pump(const Duration(milliseconds: 30));

    expect(tester.takeException(), isNull);
    await gesture.removePointer();
  });
}
