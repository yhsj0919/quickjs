import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

const String _svg =
    '<svg viewBox="0 0 10 10" '
    'xmlns="http://www.w3.org/2000/svg">'
    '<rect width="10" height="10" fill="#ffffff"/>'
    '</svg>';

void main() {
  testWidgets('fixed-size Svg defaults to retained raster rendering', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(
          QuickjsUiNode.fromMap(<String, Object?>{
            'type': 'Svg',
            'data': _svg,
            'width': 36,
            'height': 36,
          }),
        ),
      ),
    );

    expect(
      tester.widget<SvgPicture>(find.byType(SvgPicture)).renderingStrategy.name,
      'raster',
    );
  });

  testWidgets('Svg keeps picture rendering for fluid size or explicit opt-in', (
    tester,
  ) async {
    final renderer = QuickjsUiRenderer(onEvent: (_) {});
    addTearDown(renderer.dispose);

    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(
          QuickjsUiNode.fromMap(<String, Object?>{'type': 'Svg', 'data': _svg}),
        ),
      ),
    );
    expect(
      tester.widget<SvgPicture>(find.byType(SvgPicture)).renderingStrategy.name,
      'picture',
    );

    await tester.pumpWidget(
      MaterialApp(
        home: renderer.build(
          QuickjsUiNode.fromMap(<String, Object?>{
            'type': 'Svg',
            'data': _svg,
            'width': 36,
            'height': 36,
            'renderingStrategy': 'picture',
          }),
        ),
      ),
    );
    expect(
      tester.widget<SvgPicture>(find.byType(SvgPicture)).renderingStrategy.name,
      'picture',
    );
  });
}
