import 'dart:convert';

import 'package:flutter/foundation.dart';

/// A portable performance capture produced by [QuickjsUiPerformanceController].
@immutable
final class QuickjsUiPerformanceReport {
  const QuickjsUiPerformanceReport({
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

  final DateTime startedAt;
  final DateTime endedAt;
  final Duration warmUp;
  final int frameCount;
  final int slowFrameCount;
  final int severeFrameCount;
  final double? buildP50Ms;
  final double? buildP90Ms;
  final double? buildP99Ms;
  final double? buildMaxMs;
  final double? rasterP50Ms;
  final double? rasterP90Ms;
  final double? rasterP99Ms;
  final double? rasterMaxMs;
  final List<QuickjsUiQualityEvent> qualityTimeline;
  final Map<String, int> qualityDurationsMs;
  final int degradeCount;
  final int recoveryCount;
  final Map<String, Object?> environment;
  final Map<String, Object?> scene;

  Duration get duration => endedAt.difference(startedAt);

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

  String toJson({bool pretty = true}) =>
      (pretty ? const JsonEncoder.withIndent('  ') : const JsonEncoder())
          .convert(toMap());
}

@immutable
final class QuickjsUiQualityEvent {
  const QuickjsUiQualityEvent({
    required this.offsetMs,
    required this.quality,
    required this.reason,
  });

  final int offsetMs;
  final String quality;
  final String reason;

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
