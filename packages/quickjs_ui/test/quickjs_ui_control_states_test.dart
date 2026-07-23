import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

void main() {
  testWidgets('buttons resolve unified states and render named slots', (
    tester,
  ) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ElevatedButton',
      'onPressed': <String, Object?>{'method': 'submit'},
      'leading': <String, Object?>{'type': 'Text', 'data': 'L'},
      'child': <String, Object?>{'type': 'Text', 'data': 'Content'},
      'trailing': <String, Object?>{'type': 'Text', 'data': 'R'},
      'stateTransition': <String, Object?>{
        'durationMs': 100,
        'curve': 'linear',
      },
      'stateStyles': <String, Object?>{
        'normal': <String, Object?>{
          'backgroundColor': '#112233',
          'foregroundColor': '#ffffff',
          'scale': 1,
        },
        'hovered': <String, Object?>{
          'backgroundColor': '#224466',
          'scale': 1.025,
        },
        'focused': <String, Object?>{'backgroundColor': '#336699'},
        'pressed': <String, Object?>{
          'backgroundColor': '#00aacc',
          'scale': 0.96,
        },
        'disabled': <String, Object?>{'backgroundColor': '#445566'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
      ),
    );

    expect(find.text('L'), findsOneWidget);
    expect(find.text('Content'), findsOneWidget);
    expect(find.text('R'), findsOneWidget);
    Color surfaceColor() {
      return tester
          .widget<ElevatedButton>(find.byType(ElevatedButton))
          .style!
          .backgroundColor!
          .resolve(<WidgetState>{})!;
    }

    double surfaceScale() {
      for (final transform in tester.widgetList<Transform>(
        find.byType(Transform),
      )) {
        if (transform.transform.storage[0] != 1) {
          return transform.transform.storage[0];
        }
      }
      return 1;
    }

    expect(surfaceColor(), const Color(0xFF112233));
    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 50));
    expect(surfaceScale(), closeTo(1.0125, 0.001));
    final interruptedFrame = surfaceScale();

    await mouse.down(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pump();
    expect(surfaceScale(), closeTo(interruptedFrame, 0.0001));
    await tester.pump(const Duration(milliseconds: 100));
    expect(surfaceScale(), closeTo(0.96, 0.0001));
    await mouse.up();
    await mouse.moveTo(const Offset(799, 599));
    await mouse.removePointer();
    await tester.pump();
  });

  testWidgets('Switch and Slider expose thumb, track and overlay styles', (
    tester,
  ) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'Column',
      'children': <Object?>[
        <String, Object?>{
          'type': 'Switch',
          'value': true,
          'onChanged': <String, Object?>{'method': 'toggle'},
          'stateTransition': <String, Object?>{
            'durationMs': 100,
            'curve': 'linear',
          },
          'thumbStyle': <String, Object?>{
            'normal': <String, Object?>{'color': '#aaaaaa'},
            'selected': <String, Object?>{'color': '#ffffff'},
            'pressed': <String, Object?>{'color': '#00ffff'},
          },
          'trackStyle': <String, Object?>{
            'normal': <String, Object?>{'color': '#222222'},
            'selected': <String, Object?>{
              'color': '#008899',
              'borderColor': '#00ffff',
              'borderWidth': 2,
            },
          },
        },
        <String, Object?>{
          'type': 'Slider',
          'value': 0.5,
          'onChanged': <String, Object?>{'method': 'slide'},
          'stateTransition': <String, Object?>{
            'durationMs': 100,
            'curve': 'linear',
          },
          'trackStyle': <String, Object?>{
            'normal': <String, Object?>{
              'activeColor': '#00aacc',
              'inactiveColor': '#334455',
              'height': 7,
            },
            'pressed': <String, Object?>{'activeColor': '#ff0000'},
          },
          'thumbStyle': <String, Object?>{
            'normal': <String, Object?>{'color': '#ffffff', 'radius': 12},
          },
          'overlayStyle': <String, Object?>{
            'normal': <String, Object?>{'color': '#3300aacc', 'radius': 25},
          },
        },
      ],
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
      ),
    );

    final toggle = tester.widget<Switch>(find.byType(Switch));
    expect(toggle.thumbColor!.resolve(<WidgetState>{}), Colors.white);
    expect(toggle.trackOutlineWidth!.resolve(<WidgetState>{}), 2);
    final switchGesture = await tester.startGesture(
      tester.getCenter(find.byType(Switch)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final pressedToggle = tester.widget<Switch>(find.byType(Switch));
    expect(
      pressedToggle.thumbColor!.resolve(<WidgetState>{}),
      const Color(0xFF00FFFF),
    );
    await switchGesture.up();

    final sliderTheme = tester.widget<SliderTheme>(find.byType(SliderTheme));
    expect(sliderTheme.data.activeTrackColor, const Color(0xFF00AACC));
    expect(sliderTheme.data.inactiveTrackColor, const Color(0xFF334455));
    expect(sliderTheme.data.trackHeight, 7);
    expect(sliderTheme.data.thumbShape, isA<RoundSliderThumbShape>());
    expect(
      (sliderTheme.data.thumbShape! as RoundSliderThumbShape)
          .enabledThumbRadius,
      12,
    );
    final gesture = await tester.startGesture(
      tester.getCenter(find.byType(Slider)),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final pressedTheme = tester.widget<SliderTheme>(find.byType(SliderTheme));
    expect(pressedTheme.data.activeTrackColor, const Color(0xFFFF0000));
    await gesture.up();
  });

  testWidgets('TextField renders structural slots and state borders', (
    tester,
  ) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'TextField',
      'value': 'hello',
      'leading': <String, Object?>{'type': 'Text', 'data': 'Leading'},
      'prefix': <String, Object?>{'type': 'Text', 'data': 'Prefix'},
      'suffix': <String, Object?>{'type': 'Text', 'data': 'Suffix'},
      'trailing': <String, Object?>{'type': 'Text', 'data': 'Trailing'},
      'stateTransition': <String, Object?>{
        'durationMs': 100,
        'curve': 'linear',
      },
      'stateStyles': <String, Object?>{
        'normal': <String, Object?>{
          'fillColor': '#112233',
          'borderColor': '#334455',
          'borderWidth': 1,
          'borderRadius': 12,
        },
        'focused': <String, Object?>{
          'fillColor': '#102a3a',
          'borderColor': '#00ffff',
          'borderWidth': 2,
        },
        'disabled': <String, Object?>{'borderColor': '#222222'},
      },
    });

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(body: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
      ),
    );

    for (final label in <String>['Leading', 'Prefix', 'Suffix', 'Trailing']) {
      expect(find.text(label), findsOneWidget);
    }
    final field = tester.widget<TextField>(find.byType(TextField));
    expect(field.decoration!.fillColor, const Color(0xFF112233));

    await tester.tap(find.byType(TextField));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    final focusedField = tester.widget<TextField>(find.byType(TextField));
    expect(focusedField.decoration!.fillColor, const Color(0xFF102A3A));
    final focused =
        focusedField.decoration!.focusedBorder! as OutlineInputBorder;
    expect(focused.borderSide.color, const Color(0xFF00FFFF));
    expect(focused.borderSide.width, 2);
  });

  testWidgets('reduced motion resolves control states immediately', (
    tester,
  ) async {
    final node = QuickjsUiNode.fromMap(<String, Object?>{
      'type': 'ElevatedButton',
      'onPressed': <String, Object?>{'method': 'submit'},
      'child': <String, Object?>{'type': 'Text', 'data': 'Motion'},
      'stateTransition': <String, Object?>{'durationMs': 1000},
      'stateStyles': <String, Object?>{
        'normal': <String, Object?>{'backgroundColor': '#112233', 'scale': 1},
        'hovered': <String, Object?>{
          'backgroundColor': '#00ffff',
          'scale': 1.1,
        },
      },
    });
    await tester.pumpWidget(
      MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(disableAnimations: true),
          child: Scaffold(body: QuickjsUiRenderer(onEvent: (_) {}).build(node)),
        ),
      ),
    );

    final mouse = await tester.createGesture(kind: PointerDeviceKind.mouse);
    await mouse.addPointer(location: const Offset(799, 599));
    await tester.pump();
    await mouse.moveTo(tester.getCenter(find.byType(ElevatedButton)));
    await tester.pump();
    final button = tester.widget<ElevatedButton>(find.byType(ElevatedButton));
    expect(
      button.style!.backgroundColor!.resolve(<WidgetState>{
        WidgetState.hovered,
      }),
      const Color(0xFF00FFFF),
    );
    final surface = tester
        .widgetList<Transform>(find.byType(Transform))
        .firstWhere((transform) => transform.transform.storage[0] != 1);
    expect(surface.transform.storage[0], closeTo(1.1, 0.0001));
    await mouse.moveTo(const Offset(799, 599));
    await mouse.removePointer();
    await tester.pump();
  });
}
