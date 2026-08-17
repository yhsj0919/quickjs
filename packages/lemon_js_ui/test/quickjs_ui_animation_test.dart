import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/src/renderer/quickjs_ui_animation.dart';

void main() {
  test('numeric keyframes hold and interpolate values', () {
    final animation = <String, Object?>{
      'from': 0,
      'to': 0,
      'durationMs': 1000,
      'keyframes': <Object?>[
        <String, Object?>{'offset': 0, 'value': 0},
        <String, Object?>{'offset': 0.8, 'value': 0},
        <String, Object?>{'offset': 0.9, 'value': 1},
        <String, Object?>{'offset': 1, 'value': 0},
      ],
    };

    expect(_sample(animation, 700), 0);
    expect(_sample(animation, 850), closeTo(0.5, 0.0001));
    expect(_sample(animation, 900), 1);
    expect(_sample(animation, 950), closeTo(0.5, 0.0001));
  });

  test('numeric keyframes reject unordered offsets', () {
    final animation = <String, Object?>{
      'from': 0,
      'to': 0,
      'durationMs': 1000,
      'keyframes': <Object?>[
        <String, Object?>{'offset': 0, 'value': 0},
        <String, Object?>{'offset': 0.8, 'value': 1},
        <String, Object?>{'offset': 0.5, 'value': 0},
        <String, Object?>{'offset': 1, 'value': 0},
      ],
    };

    expect(() => _sample(animation, 700), throwsFormatException);
  });
}

double? _sample(Map<String, Object?> animation, double elapsedMs) {
  return jsUiAnimatedNumber(
    animation,
    JsUiAnimationClock(elapsedMs: elapsedMs, epochMs: 0),
  );
}
