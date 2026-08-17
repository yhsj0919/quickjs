part of 'quickjs_ui_canvas_component.dart';

typedef _CanvasClock = JsUiAnimationClock;

bool _containsAnimation(Object? value) =>
    JsUiAnimationTimeline.from(value).hasAnimations;

double _number(Object? raw, String name, _CanvasClock clock) {
  final value = _optionalNumber(raw, clock);
  if (value == null || !value.isFinite) {
    throw FormatException('quickjs_ui Canvas $name must be a finite number');
  }
  return value;
}

double? _optionalNumber(Object? raw, _CanvasClock clock) {
  return jsUiAnimatedNumber(raw, clock);
}
