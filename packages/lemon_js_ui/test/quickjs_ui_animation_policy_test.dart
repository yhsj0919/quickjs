import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js_ui/src/performance/quickjs_ui_effect_quality.dart';

void main() {
  test('host updates override system input and restore configured quality', () {
    final policy = JsUiPerformanceController(
      mode: JsUiPerformanceMode.low,
      motion: JsUiMotionMode.enabled,
    );
    addTearDown(policy.dispose);
    policy.updateSystemReduceMotion(true);
    expect(policy.quality, JsUiEffectQuality.low);
    policy.update(motion: JsUiMotionMode.system);
    expect(policy.animationsDisabled, isTrue);
    policy.update(
      mode: JsUiPerformanceMode.high,
      motion: JsUiMotionMode.enabled,
    );
    expect(policy.quality, JsUiEffectQuality.high);
    policy.update(mode: JsUiPerformanceMode.off);
    expect(policy.animationDuration(const Duration(seconds: 1)), Duration.zero);
    policy.update(mode: JsUiPerformanceMode.auto);
    expect(policy.quality, JsUiEffectQuality.high);
  });

  test('updates notify once and reset automatic hysteresis', () {
    final policy = JsUiPerformanceController(
      mode: JsUiPerformanceMode.auto,
      degradeAfterFrames: 2,
      upgradeAfterFrames: 4,
    );
    addTearDown(policy.dispose);
    var notifications = 0;
    policy.addListener(() => notifications++);
    policy.addFrameSample(
      build: const Duration(seconds: 1),
      raster: Duration.zero,
    );
    policy.update(
      mode: JsUiPerformanceMode.low,
      motion: JsUiMotionMode.reduced,
    );
    expect(notifications, 1);
    policy.update(
      mode: JsUiPerformanceMode.low,
      motion: JsUiMotionMode.reduced,
    );
    expect(notifications, 1);
    policy.update(
      mode: JsUiPerformanceMode.auto,
      motion: JsUiMotionMode.enabled,
    );
    policy.addFrameSample(
      build: const Duration(seconds: 1),
      raster: Duration.zero,
    );
    expect(policy.quality, JsUiEffectQuality.high);
  });
}
