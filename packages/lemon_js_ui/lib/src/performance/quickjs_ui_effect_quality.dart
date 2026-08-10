import 'dart:collection';
import 'dart:ui' show Size;

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

import 'quickjs_ui_performance_report.dart';

enum QuickjsUiEffectQuality { high, balanced, low, off }

enum QuickjsUiPerformanceMode { auto, high, balanced, low, off }

/// Host-owned performance controller for renderer-local effect degradation.
///
/// Auto mode uses Flutter frame timings and hysteresis. It never rebuilds the
/// JavaScript page or sends per-frame data over the bridge.
final class QuickjsUiPerformanceController extends ChangeNotifier {
  QuickjsUiPerformanceController({
    this.mode = QuickjsUiPerformanceMode.high,
    Duration? targetFrameBudget,
    this.degradeAfterFrames = 24,
    this.upgradeAfterFrames = 240,
  }) : _targetFrameBudget =
           targetFrameBudget ?? const Duration(microseconds: 8333),
       _hasExplicitFrameBudget = targetFrameBudget != null,
       assert(degradeAfterFrames > 0),
       assert(upgradeAfterFrames > degradeAfterFrames),
       _quality = _qualityForMode(mode);

  final QuickjsUiPerformanceMode mode;
  final int degradeAfterFrames;
  final int upgradeAfterFrames;
  Duration _targetFrameBudget;
  final bool _hasExplicitFrameBudget;
  QuickjsUiEffectQuality _quality;
  bool _reduceMotion = false;
  double? _refreshRate;
  String? _lastTransitionReason;
  final ListQueue<double> _buildSamplesMs = ListQueue<double>();
  final ListQueue<double> _rasterSamplesMs = ListQueue<double>();
  final ListQueue<double> _canvasPaintSamplesMs = ListQueue<double>();
  int _canvasCount = 0;
  int _animatedCanvasCount = 0;
  int _canvasCommandCount = 0;
  int _canvasPathSegmentCount = 0;
  int _snapshotParticleFragments = 0;
  int _blurEffectCount = 0;
  int _backdropBlurEffectCount = 0;
  int _colorFilterEffectCount = 0;
  int _retainedSceneCount = 0;
  int _snapshotCount = 0;
  int _snapshotPixels = 0;
  int _canvasRepaintCount = 0;
  int _rejectedCanvasCommandCount = 0;
  String? _lastCanvasRejection;
  int _slowFrames = 0;
  int _stableFrames = 0;
  bool _started = false;
  Size? _logicalDisplaySize;
  double? _devicePixelRatio;
  _PerformanceSession? _session;

  QuickjsUiEffectQuality get quality =>
      _reduceMotion ? QuickjsUiEffectQuality.off : _quality;
  Duration get targetFrameBudget => _targetFrameBudget;
  double? get refreshRate => _refreshRate;
  bool get reduceMotion => _reduceMotion;
  bool get isStarted => _started;
  bool get isSessionActive => _session != null;

  void updateDisplayRefreshRate(double refreshRate) {
    if (!refreshRate.isFinite || refreshRate <= 0) return;
    _refreshRate = refreshRate;
    if (!_hasExplicitFrameBudget) {
      _targetFrameBudget = Duration(
        microseconds: (Duration.microsecondsPerSecond / refreshRate).round(),
      );
    }
  }

  void updateDisplayMetrics({
    required Size logicalSize,
    required double devicePixelRatio,
  }) {
    _logicalDisplaySize = logicalSize;
    if (devicePixelRatio.isFinite && devicePixelRatio > 0) {
      _devicePixelRatio = devicePixelRatio;
    }
  }

  /// Starts an explicit capture. Frames during [warmUp] are intentionally
  /// excluded while the scene and shader caches settle.
  void startSession({
    Duration warmUp = const Duration(seconds: 2),
    Map<String, Object?> scene = const <String, Object?>{},
    Map<String, Object?> metadata = const <String, Object?>{},
  }) {
    if (_session != null) {
      throw StateError('A performance session is already active.');
    }
    final now = DateTime.now();
    _session = _PerformanceSession(
      startedAt: now,
      warmUp: warmUp,
      initialQuality: quality.name,
      scene: Map<String, Object?>.unmodifiable(scene),
      metadata: Map<String, Object?>.unmodifiable(metadata),
    );
  }

  /// Stops the active capture and returns a stable, JSON-serializable report.
  QuickjsUiPerformanceReport stopSession() {
    final session = _session;
    if (session == null) {
      throw StateError('No performance session is active.');
    }
    _session = null;
    final sceneMetrics = snapshot.toMap()
      ..removeWhere(
        (key, _) => const <String>{
          'mode',
          'quality',
          'refreshRate',
          'targetFrameBudgetMs',
          'reducedMotion',
          'buildP50Ms',
          'buildP90Ms',
          'buildP99Ms',
          'rasterP50Ms',
          'rasterP90Ms',
          'rasterP99Ms',
          'consecutiveSlowFrames',
          'consecutiveStableFrames',
          'lastTransitionReason',
        }.contains(key),
      );
    return session.finish(
      endedAt: DateTime.now(),
      environment: <String, Object?>{
        'platform': kIsWeb ? 'web' : defaultTargetPlatform.name,
        'buildMode': kReleaseMode
            ? 'release'
            : kProfileMode
            ? 'profile'
            : 'debug',
        if (_refreshRate != null) 'refreshRate': _refreshRate,
        'targetFrameBudgetMs': targetFrameBudget.inMicroseconds / 1000,
        if (_logicalDisplaySize != null) ...<String, Object?>{
          'logicalWidth': _logicalDisplaySize!.width,
          'logicalHeight': _logicalDisplaySize!.height,
        },
        if (_devicePixelRatio != null) 'devicePixelRatio': _devicePixelRatio,
        ...session.metadata,
      },
      sceneMetrics: <String, Object?>{...sceneMetrics, ...session.scene},
    );
  }

  void updateReduceMotion(bool value) {
    if (_reduceMotion == value) return;
    _reduceMotion = value;
    _lastTransitionReason = value
        ? 'system reduced motion enabled'
        : 'system reduced motion disabled';
    _session?.addQualityChange(
      timestamp: DateTime.now(),
      quality: quality.name,
      reason: _lastTransitionReason!,
    );
    notifyListeners();
  }

  QuickjsUiPerformanceSnapshot get snapshot => QuickjsUiPerformanceSnapshot(
    mode: mode,
    quality: quality,
    refreshRate: _refreshRate,
    targetFrameBudget: _targetFrameBudget,
    reduceMotion: _reduceMotion,
    buildP50Ms: _percentile(_buildSamplesMs, 0.50),
    buildP90Ms: _percentile(_buildSamplesMs, 0.90),
    buildP99Ms: _percentile(_buildSamplesMs, 0.99),
    rasterP50Ms: _percentile(_rasterSamplesMs, 0.50),
    rasterP90Ms: _percentile(_rasterSamplesMs, 0.90),
    rasterP99Ms: _percentile(_rasterSamplesMs, 0.99),
    consecutiveSlowFrames: _slowFrames,
    consecutiveStableFrames: _stableFrames,
    lastTransitionReason: _lastTransitionReason,
    canvasCount: _canvasCount,
    animatedCanvasCount: _animatedCanvasCount,
    canvasCommandCount: _canvasCommandCount,
    canvasPathSegmentCount: _canvasPathSegmentCount,
    requestedParticleFragments: _snapshotParticleFragments,
    effectiveParticleFragments: _effectiveParticleFragments(
      _snapshotParticleFragments,
      quality,
    ),
    blurEffectCount: _blurEffectCount,
    clampedBlurEffectCount: quality == QuickjsUiEffectQuality.high
        ? 0
        : _blurEffectCount,
    backdropBlurEffectCount: _backdropBlurEffectCount,
    disabledBackdropBlurCount: quality.index >= QuickjsUiEffectQuality.low.index
        ? _backdropBlurEffectCount
        : 0,
    colorFilterEffectCount: _colorFilterEffectCount,
    disabledColorFilterCount: quality.index >= QuickjsUiEffectQuality.low.index
        ? _colorFilterEffectCount
        : 0,
    stoppedCanvasTickerCount: quality == QuickjsUiEffectQuality.off
        ? _animatedCanvasCount
        : 0,
    retainedSceneCount: _retainedSceneCount,
    snapshotCount: _snapshotCount,
    snapshotPixels: _snapshotPixels,
    canvasRepaintCount: _canvasRepaintCount,
    canvasPaintP50Ms: _percentile(_canvasPaintSamplesMs, 0.50),
    canvasPaintP90Ms: _percentile(_canvasPaintSamplesMs, 0.90),
    canvasPaintP99Ms: _percentile(_canvasPaintSamplesMs, 0.99),
    rejectedCanvasCommandCount: _rejectedCanvasCommandCount,
    lastCanvasRejection: _lastCanvasRejection,
  );

  void beginRenderPass() {
    _canvasCount = 0;
    _animatedCanvasCount = 0;
    _canvasCommandCount = 0;
    _canvasPathSegmentCount = 0;
    _snapshotParticleFragments = 0;
    _blurEffectCount = 0;
    _backdropBlurEffectCount = 0;
    _colorFilterEffectCount = 0;
  }

  void recordCanvasSchema({
    required int commandCount,
    required int pathSegmentCount,
    required int particleFragments,
    required bool animated,
  }) {
    _canvasCount += 1;
    if (animated) _animatedCanvasCount += 1;
    _canvasCommandCount += commandCount;
    _canvasPathSegmentCount += pathSegmentCount;
    _snapshotParticleFragments += particleFragments;
  }

  void recordEffectSchema({
    required bool blur,
    required bool backdropBlur,
    required bool colorFilter,
  }) {
    if (blur) _blurEffectCount += 1;
    if (backdropBlur) _backdropBlurEffectCount += 1;
    if (colorFilter) _colorFilterEffectCount += 1;
  }

  void updateResourceMetrics({
    required int retainedSceneCount,
    required int snapshotCount,
    required int snapshotPixels,
  }) {
    _retainedSceneCount = retainedSceneCount;
    _snapshotCount = snapshotCount;
    _snapshotPixels = snapshotPixels;
  }

  void recordCanvasPaint(Duration elapsed) {
    _canvasRepaintCount += 1;
    _appendSample(_canvasPaintSamplesMs, elapsed.inMicroseconds / 1000);
  }

  void recordCanvasRejection(Object error) {
    _rejectedCanvasCommandCount += 1;
    _lastCanvasRejection = '$error';
  }

  void start() {
    if (_started) return;
    SchedulerBinding.instance.addTimingsCallback(_handleTimings);
    _started = true;
  }

  void stop() {
    if (!_started) return;
    SchedulerBinding.instance.removeTimingsCallback(_handleTimings);
    _started = false;
  }

  @visibleForTesting
  void addFrameSample({
    required Duration build,
    required Duration raster,
    DateTime? timestamp,
  }) {
    _appendSample(_buildSamplesMs, build.inMicroseconds / 1000);
    _appendSample(_rasterSamplesMs, raster.inMicroseconds / 1000);
    _session?.addFrame(
      timestamp: timestamp ?? DateTime.now(),
      build: build,
      raster: raster,
      frameBudget: targetFrameBudget,
    );
    if (mode != QuickjsUiPerformanceMode.auto) return;
    final elapsed = build > raster ? build : raster;
    final slowThreshold = targetFrameBudget * 1.15;
    final stableThreshold = targetFrameBudget * 0.75;
    if (elapsed > slowThreshold) {
      _slowFrames += 1;
      _stableFrames = 0;
      if (_slowFrames >= degradeAfterFrames) {
        _setQuality(
          _degraded(_quality),
          reason: 'frame time exceeded 115% of budget',
        );
        _slowFrames = 0;
      }
      return;
    }
    _slowFrames = 0;
    if (elapsed < stableThreshold) {
      _stableFrames += 1;
      if (_stableFrames >= upgradeAfterFrames) {
        _setQuality(
          _upgraded(_quality),
          reason: 'frame time stayed below 75% of budget',
        );
        _stableFrames = 0;
      }
    } else {
      _stableFrames = 0;
    }
  }

  void _handleTimings(List<FrameTiming> timings) {
    for (final timing in timings) {
      addFrameSample(
        build: timing.buildDuration,
        raster: timing.rasterDuration,
      );
    }
  }

  void _setQuality(QuickjsUiEffectQuality value, {required String reason}) {
    if (_quality == value) return;
    _quality = value;
    _lastTransitionReason = reason;
    _session?.addQualityChange(
      timestamp: DateTime.now(),
      quality: quality.name,
      reason: reason,
    );
    notifyListeners();
  }

  @override
  void dispose() {
    stop();
    super.dispose();
  }
}

final class _PerformanceSession {
  _PerformanceSession({
    required this.startedAt,
    required this.warmUp,
    required this.initialQuality,
    required this.scene,
    required this.metadata,
  });

  final DateTime startedAt;
  final Duration warmUp;
  final String initialQuality;
  final Map<String, Object?> scene;
  final Map<String, Object?> metadata;
  final List<double> _buildMs = <double>[];
  final List<double> _rasterMs = <double>[];
  final List<_QualityChange> _changes = <_QualityChange>[];
  int _slowFrames = 0;
  int _severeFrames = 0;

  DateTime get recordingStartsAt => startedAt.add(warmUp);

  void addFrame({
    required DateTime timestamp,
    required Duration build,
    required Duration raster,
    required Duration frameBudget,
  }) {
    if (timestamp.isBefore(recordingStartsAt)) return;
    final buildMs = build.inMicroseconds / 1000;
    final rasterMs = raster.inMicroseconds / 1000;
    _buildMs.add(buildMs);
    _rasterMs.add(rasterMs);
    final frame = build > raster ? build : raster;
    if (frame > frameBudget) _slowFrames += 1;
    if (frame > frameBudget * 2) _severeFrames += 1;
  }

  void addQualityChange({
    required DateTime timestamp,
    required String quality,
    required String reason,
  }) {
    _changes.add(_QualityChange(timestamp, quality, reason));
  }

  QuickjsUiPerformanceReport finish({
    required DateTime endedAt,
    required Map<String, Object?> environment,
    required Map<String, Object?> sceneMetrics,
  }) {
    final captureStart = recordingStartsAt.isAfter(endedAt)
        ? endedAt
        : recordingStartsAt;
    final relevantChanges = _changes
        .where((change) => !change.at.isBefore(captureStart))
        .toList();
    final events = <QuickjsUiQualityEvent>[
      QuickjsUiQualityEvent(
        offsetMs: captureStart.difference(startedAt).inMilliseconds,
        quality: _qualityAt(captureStart),
        reason: 'capture started',
      ),
      for (final change in relevantChanges)
        QuickjsUiQualityEvent(
          offsetMs: change.at.difference(startedAt).inMilliseconds,
          quality: change.quality,
          reason: change.reason,
        ),
    ];
    final durations = <String, int>{};
    for (var index = 0; index < events.length; index += 1) {
      final nextOffset = index + 1 < events.length
          ? events[index + 1].offsetMs
          : endedAt.difference(startedAt).inMilliseconds;
      durations.update(
        events[index].quality,
        (value) =>
            value + (nextOffset - events[index].offsetMs).clamp(0, 1 << 31),
        ifAbsent: () => (nextOffset - events[index].offsetMs).clamp(0, 1 << 31),
      );
    }
    var degradeCount = 0;
    var recoveryCount = 0;
    for (var index = 1; index < events.length; index += 1) {
      final previous = _qualityRank(events[index - 1].quality);
      final current = _qualityRank(events[index].quality);
      if (current > previous) degradeCount += 1;
      if (current < previous) recoveryCount += 1;
    }
    return QuickjsUiPerformanceReport(
      startedAt: startedAt,
      endedAt: endedAt,
      warmUp: warmUp,
      frameCount: _buildMs.length,
      slowFrameCount: _slowFrames,
      severeFrameCount: _severeFrames,
      buildP50Ms: _listPercentile(_buildMs, 0.50),
      buildP90Ms: _listPercentile(_buildMs, 0.90),
      buildP99Ms: _listPercentile(_buildMs, 0.99),
      buildMaxMs: _listMax(_buildMs),
      rasterP50Ms: _listPercentile(_rasterMs, 0.50),
      rasterP90Ms: _listPercentile(_rasterMs, 0.90),
      rasterP99Ms: _listPercentile(_rasterMs, 0.99),
      rasterMaxMs: _listMax(_rasterMs),
      qualityTimeline: List<QuickjsUiQualityEvent>.unmodifiable(events),
      qualityDurationsMs: Map<String, int>.unmodifiable(durations),
      degradeCount: degradeCount,
      recoveryCount: recoveryCount,
      environment: Map<String, Object?>.unmodifiable(environment),
      scene: Map<String, Object?>.unmodifiable(sceneMetrics),
    );
  }

  String _qualityAt(DateTime timestamp) {
    var result = initialQuality;
    for (final change in _changes) {
      if (!change.at.isBefore(timestamp)) break;
      result = change.quality;
    }
    return result;
  }
}

final class _QualityChange {
  const _QualityChange(this.at, this.quality, this.reason);
  final DateTime at;
  final String quality;
  final String reason;
}

final class QuickjsUiPerformanceSnapshot {
  const QuickjsUiPerformanceSnapshot({
    required this.mode,
    required this.quality,
    required this.refreshRate,
    required this.targetFrameBudget,
    required this.reduceMotion,
    required this.buildP50Ms,
    required this.buildP90Ms,
    required this.buildP99Ms,
    required this.rasterP50Ms,
    required this.rasterP90Ms,
    required this.rasterP99Ms,
    required this.consecutiveSlowFrames,
    required this.consecutiveStableFrames,
    required this.lastTransitionReason,
    required this.canvasCount,
    required this.animatedCanvasCount,
    required this.canvasCommandCount,
    required this.canvasPathSegmentCount,
    required this.requestedParticleFragments,
    required this.effectiveParticleFragments,
    required this.blurEffectCount,
    required this.clampedBlurEffectCount,
    required this.backdropBlurEffectCount,
    required this.disabledBackdropBlurCount,
    required this.colorFilterEffectCount,
    required this.disabledColorFilterCount,
    required this.stoppedCanvasTickerCount,
    required this.retainedSceneCount,
    required this.snapshotCount,
    required this.snapshotPixels,
    required this.canvasRepaintCount,
    required this.canvasPaintP50Ms,
    required this.canvasPaintP90Ms,
    required this.canvasPaintP99Ms,
    required this.rejectedCanvasCommandCount,
    required this.lastCanvasRejection,
  });

  final QuickjsUiPerformanceMode mode;
  final QuickjsUiEffectQuality quality;
  final double? refreshRate;
  final Duration targetFrameBudget;
  final bool reduceMotion;
  final double? buildP50Ms;
  final double? buildP90Ms;
  final double? buildP99Ms;
  final double? rasterP50Ms;
  final double? rasterP90Ms;
  final double? rasterP99Ms;
  final int consecutiveSlowFrames;
  final int consecutiveStableFrames;
  final String? lastTransitionReason;
  final int canvasCount;
  final int animatedCanvasCount;
  final int canvasCommandCount;
  final int canvasPathSegmentCount;
  final int requestedParticleFragments;
  final int effectiveParticleFragments;
  final int blurEffectCount;
  final int clampedBlurEffectCount;
  final int backdropBlurEffectCount;
  final int disabledBackdropBlurCount;
  final int colorFilterEffectCount;
  final int disabledColorFilterCount;
  final int stoppedCanvasTickerCount;
  final int retainedSceneCount;
  final int snapshotCount;
  final int snapshotPixels;
  final int canvasRepaintCount;
  final double? canvasPaintP50Ms;
  final double? canvasPaintP90Ms;
  final double? canvasPaintP99Ms;
  final int rejectedCanvasCommandCount;
  final String? lastCanvasRejection;

  Map<String, Object?> toMap() => <String, Object?>{
    'mode': mode.name,
    'quality': quality.name,
    if (refreshRate != null) 'refreshRate': refreshRate,
    'targetFrameBudgetMs': targetFrameBudget.inMicroseconds / 1000,
    'reducedMotion': reduceMotion,
    if (buildP50Ms != null) 'buildP50Ms': buildP50Ms,
    if (buildP90Ms != null) 'buildP90Ms': buildP90Ms,
    if (buildP99Ms != null) 'buildP99Ms': buildP99Ms,
    if (rasterP50Ms != null) 'rasterP50Ms': rasterP50Ms,
    if (rasterP90Ms != null) 'rasterP90Ms': rasterP90Ms,
    if (rasterP99Ms != null) 'rasterP99Ms': rasterP99Ms,
    'consecutiveSlowFrames': consecutiveSlowFrames,
    'consecutiveStableFrames': consecutiveStableFrames,
    if (lastTransitionReason != null)
      'lastTransitionReason': lastTransitionReason,
    'canvasCount': canvasCount,
    'animatedCanvasCount': animatedCanvasCount,
    'canvasCommandCount': canvasCommandCount,
    'canvasPathSegmentCount': canvasPathSegmentCount,
    'requestedParticleFragments': requestedParticleFragments,
    'effectiveParticleFragments': effectiveParticleFragments,
    'blurEffectCount': blurEffectCount,
    'clampedBlurEffectCount': clampedBlurEffectCount,
    'backdropBlurEffectCount': backdropBlurEffectCount,
    'disabledBackdropBlurCount': disabledBackdropBlurCount,
    'colorFilterEffectCount': colorFilterEffectCount,
    'disabledColorFilterCount': disabledColorFilterCount,
    'stoppedCanvasTickerCount': stoppedCanvasTickerCount,
    'retainedSceneCount': retainedSceneCount,
    'snapshotCount': snapshotCount,
    'snapshotPixels': snapshotPixels,
    'canvasRepaintCount': canvasRepaintCount,
    if (canvasPaintP50Ms != null) 'canvasPaintP50Ms': canvasPaintP50Ms,
    if (canvasPaintP90Ms != null) 'canvasPaintP90Ms': canvasPaintP90Ms,
    if (canvasPaintP99Ms != null) 'canvasPaintP99Ms': canvasPaintP99Ms,
    'rejectedCanvasCommandCount': rejectedCanvasCommandCount,
    if (lastCanvasRejection != null) 'lastCanvasRejection': lastCanvasRejection,
  };
}

int _effectiveParticleFragments(
  int requested,
  QuickjsUiEffectQuality quality,
) => switch (quality) {
  QuickjsUiEffectQuality.high => requested,
  QuickjsUiEffectQuality.balanced => requested.clamp(0, 1024),
  QuickjsUiEffectQuality.low => requested.clamp(0, 256),
  QuickjsUiEffectQuality.off => 0,
};

void _appendSample(ListQueue<double> samples, double value) {
  samples.add(value);
  if (samples.length > 240) samples.removeFirst();
}

double? _percentile(Iterable<double> samples, double percentile) {
  if (samples.isEmpty) return null;
  final sorted = samples.toList()..sort();
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}

double? _listPercentile(List<double> samples, double percentile) =>
    _percentile(samples, percentile);

double? _listMax(List<double> samples) {
  if (samples.isEmpty) return null;
  return samples.reduce((left, right) => left > right ? left : right);
}

int _qualityRank(String quality) => switch (quality) {
  'high' => 0,
  'balanced' => 1,
  'low' => 2,
  'off' => 3,
  _ => 0,
};

QuickjsUiEffectQuality _qualityForMode(QuickjsUiPerformanceMode mode) =>
    switch (mode) {
      QuickjsUiPerformanceMode.auto ||
      QuickjsUiPerformanceMode.high => QuickjsUiEffectQuality.high,
      QuickjsUiPerformanceMode.balanced => QuickjsUiEffectQuality.balanced,
      QuickjsUiPerformanceMode.low => QuickjsUiEffectQuality.low,
      QuickjsUiPerformanceMode.off => QuickjsUiEffectQuality.off,
    };

QuickjsUiEffectQuality _degraded(QuickjsUiEffectQuality quality) =>
    switch (quality) {
      QuickjsUiEffectQuality.high => QuickjsUiEffectQuality.balanced,
      QuickjsUiEffectQuality.balanced => QuickjsUiEffectQuality.low,
      QuickjsUiEffectQuality.low || QuickjsUiEffectQuality.off => quality,
    };

QuickjsUiEffectQuality _upgraded(QuickjsUiEffectQuality quality) =>
    switch (quality) {
      QuickjsUiEffectQuality.low => QuickjsUiEffectQuality.balanced,
      QuickjsUiEffectQuality.balanced => QuickjsUiEffectQuality.high,
      QuickjsUiEffectQuality.high || QuickjsUiEffectQuality.off => quality,
    };
