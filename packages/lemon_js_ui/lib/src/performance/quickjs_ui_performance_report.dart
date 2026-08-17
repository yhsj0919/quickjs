import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A portable performance capture produced by [JsUiPerformanceController].
@immutable
final class JsUiPerformanceReport {
  /// Creates a completed performance capture.
  const JsUiPerformanceReport({
    required this.startedAt,
    required this.endedAt,
    required this.warmUp,
    required this.frameCount,
    required this.slowFrameCount,
    required this.severeFrameCount,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.buildP99Ms,
    required this.buildMaxMs,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.rasterMaxMs,
    required this.qualityTimeline,
    required this.qualityDurationsMs,
    required this.degradeCount,
    required this.recoveryCount,
    required this.environment,
    required this.scene,
  });

  /// Time at which the capture session was started.
  final DateTime startedAt;

  /// Time at which the capture session was stopped.
  final DateTime endedAt;

  /// Initial interval excluded while the scene and caches settle.
  final Duration warmUp;

  /// Frames recorded after [warmUp].
  final int frameCount;

  /// Recorded frames exceeding the target frame budget.
  final int slowFrameCount;

  /// Recorded frames exceeding twice the target frame budget.
  final int severeFrameCount;

  /// Median Flutter build duration in milliseconds.
  final double? buildP50Ms;

  /// 90th-percentile Flutter build duration in milliseconds.
  final double? buildP90Ms;

  /// 99th-percentile Flutter build duration in milliseconds.
  final double? buildP99Ms;

  /// Maximum Flutter build duration in milliseconds.
  final double? buildMaxMs;

  /// Median Flutter raster duration in milliseconds.
  final double? rasterP50Ms;

  /// 90th-percentile Flutter raster duration in milliseconds.
  final double? rasterP90Ms;

  /// 99th-percentile Flutter raster duration in milliseconds.
  final double? rasterP99Ms;

  /// Maximum Flutter raster duration in milliseconds.
  final double? rasterMaxMs;

  /// Effective-quality changes during the recorded interval.
  final List<JsUiQualityEvent> qualityTimeline;

  /// Time spent at each quality level, in milliseconds.
  final Map<String, int> qualityDurationsMs;

  /// Number of transitions to a lower quality level.
  final int degradeCount;

  /// Number of transitions to a higher quality level.
  final int recoveryCount;

  /// Platform, build-mode, display, and caller-supplied metadata.
  final Map<String, Object?> environment;

  /// Renderer workload counters and caller-supplied scene metadata.
  final Map<String, Object?> scene;

  /// Wall-clock duration from [startedAt] through [endedAt].
  Duration get duration => endedAt.difference(startedAt);

  /// Serializes this report to JSON-compatible schema version 1 data.
  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': 1,
    'startedAt': startedAt.toUtc().toIso8601String(),
    'endedAt': endedAt.toUtc().toIso8601String(),
    'durationMs': duration.inMilliseconds,
    'warmUpMs': warmUp.inMilliseconds,
    'frameCount': frameCount,
    'slowFrameCount': slowFrameCount,
    'severeFrameCount': severeFrameCount,
    'build': _timingMap(buildP50Ms, buildP90Ms, buildP99Ms, buildMaxMs),
    'raster': _timingMap(rasterP50Ms, rasterP90Ms, rasterP99Ms, rasterMaxMs),
    'qualityTimeline': qualityTimeline.map((event) => event.toMap()).toList(),
    'qualityDurationsMs': qualityDurationsMs,
    'degradeCount': degradeCount,
    'recoveryCount': recoveryCount,
    'environment': environment,
    'scene': scene,
  };

  /// Encodes this report as JSON, indented when [pretty] is true.
  String toJson({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toMap());
}

@immutable
/// One effective-quality state in a performance report timeline.
final class JsUiQualityEvent {
  /// Creates a quality event relative to the capture start.
  const JsUiQualityEvent({
    required this.offsetMs,
    required this.quality,
    required this.reason,
  });

  /// Milliseconds from the session start to this event.
  final int offsetMs;

  /// Effective quality name at this point in the timeline.
  final String quality;

  /// Explanation for the initial state or transition.
  final String reason;

  /// Serializes this event to JSON-compatible structured data.
  Map<String, Object?> toMap() => <String, Object?>{
    'offsetMs': offsetMs,
    'quality': quality,
    'reason': reason,
  };
}

Map<String, Object?> _timingMap(
  double? p50,
  double? p90,
  double? p99,
  double? max,
) => <String, Object?>{
  'p50Ms': ?p50,
  'p90Ms': ?p90,
  'p99Ms': ?p99,
  'maxMs': ?max,
};
