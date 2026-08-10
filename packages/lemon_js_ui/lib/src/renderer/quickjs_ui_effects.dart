import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import '../performance/quickjs_ui_effect_quality.dart';
import 'quickjs_ui_animation.dart';
import 'quickjs_ui_frame_scheduler.dart';
import 'quickjs_ui_render_context.dart';

Widget withQuickjsUiEffects(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Widget child,
) {
  final props = node.props;
  final transform =
      props['transform'] ??
      (props.containsKey('translate') ||
              props.containsKey('scale') ||
              props.containsKey('rotate') ||
              props.containsKey('rotation') ||
              props.containsKey('transformAlignment')
          ? <String, Object?>{
              if (props.containsKey('translate'))
                'translate': props['translate'],
              if (props.containsKey('scale')) 'scale': props['scale'],
              if (props.containsKey('rotate')) 'rotate': props['rotate'],
              if (props.containsKey('rotation')) 'rotation': props['rotation'],
              if (props.containsKey('transformAlignment'))
                'alignment': props['transformAlignment'],
            }
          : null);
  final hasEffects =
      props.containsKey('opacity') ||
      props.containsKey('transform') ||
      transform != null ||
      props.containsKey('clipRadius') ||
      props.containsKey('blur') ||
      props.containsKey('backdropBlur') ||
      props.containsKey('colorFilter');
  if (!hasEffects) return child;
  context.performanceController.recordEffectSchema(
    blur: props.containsKey('blur'),
    backdropBlur: props.containsKey('backdropBlur'),
    colorFilter: props.containsKey('colorFilter'),
  );

  final onAnimationEnd = QuickjsUiProps.event(props['onAnimationEnd']);
  return _QuickjsUiEffects(
    opacity: props['opacity'],
    transform: transform,
    clipRadius: props['clipRadius'],
    blur: props['blur'],
    backdropBlur: props['backdropBlur'],
    colorFilter: props['colorFilter'],
    clipBehavior: _clipBehavior(props['clipBehavior']),
    animationFrameIntervalMs: _animationFrameIntervalMs(
      props['animationFrameIntervalMs'],
    ),
    frameScheduler: context.frameScheduler,
    paused: props['paused'] == true,
    playToken: props['playToken'],
    reverse: props['reverse'] == true,
    performanceController: context.performanceController,
    resolveColor: context.color,
    onAnimationEnd: onAnimationEnd == null
        ? null
        : () => context.dispatchEvent(
            onAnimationEnd,
            defaultCoalesceKey:
                '${node.type}:${node.key ?? 'anonymous'}:onAnimationEnd',
          ),
    child: child,
  );
}

final class _QuickjsUiEffects extends StatefulWidget {
  _QuickjsUiEffects({
    required this.opacity,
    required this.transform,
    required this.clipRadius,
    required this.blur,
    required this.backdropBlur,
    required this.colorFilter,
    required this.clipBehavior,
    required this.animationFrameIntervalMs,
    required this.frameScheduler,
    required this.paused,
    required this.playToken,
    required this.reverse,
    required this.performanceController,
    required this.resolveColor,
    required this.onAnimationEnd,
    required this.child,
  }) : values = <Object?>[opacity, transform, clipRadius, blur, backdropBlur],
       valueHash = quickjsUiValueHash(<Object?>[
         opacity,
         transform,
         clipRadius,
         blur,
         backdropBlur,
         colorFilter,
       ]),
       timeline = QuickjsUiAnimationTimeline.from(<Object?>[
         opacity,
         transform,
         clipRadius,
         blur,
         backdropBlur,
       ]);

  final Object? opacity;
  final Object? transform;
  final Object? clipRadius;
  final Object? blur;
  final Object? backdropBlur;
  final Object? colorFilter;
  final Clip clipBehavior;
  final int? animationFrameIntervalMs;
  final QuickjsUiFrameScheduler frameScheduler;
  final bool paused;
  final Object? playToken;
  final bool reverse;
  final QuickjsUiPerformanceController performanceController;
  final Color? Function(Object? value) resolveColor;
  final VoidCallback? onAnimationEnd;
  final Widget child;
  final List<Object?> values;
  final int valueHash;
  final QuickjsUiAnimationTimeline timeline;

  @override
  State<_QuickjsUiEffects> createState() => _QuickjsUiEffectsState();
}

final class _QuickjsUiEffectsState extends State<_QuickjsUiEffects>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  double _elapsedMs = 0;
  double _playbackOffsetMs = 0;
  bool _didComplete = false;
  int _generation = 0;
  QuickjsUiFrameClock? _frameClock;
  final Stopwatch _limitedStopwatch = Stopwatch();

  @override
  void initState() {
    super.initState();
    widget.performanceController.addListener(_qualityChanged);
    _ticker = createTicker(_tick);
    _syncScheduler();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiEffects oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.performanceController != widget.performanceController) {
      oldWidget.performanceController.removeListener(_qualityChanged);
      widget.performanceController.addListener(_qualityChanged);
    }
    final restart =
        oldWidget.valueHash != widget.valueHash ||
        oldWidget.playToken != widget.playToken ||
        oldWidget.reverse != widget.reverse;
    if (restart) {
      _stopScheduler();
      _elapsedMs = 0;
      _playbackOffsetMs = 0;
      _didComplete = false;
      _generation += 1;
    } else if (!oldWidget.paused && widget.paused) {
      _playbackOffsetMs = _elapsedMs;
    } else if (oldWidget.animationFrameIntervalMs !=
        widget.animationFrameIntervalMs) {
      _playbackOffsetMs = _elapsedMs;
      _stopScheduler();
    }
    _syncScheduler();
  }

  void _tick(Duration elapsed) {
    _elapsedMs = _playbackOffsetMs + elapsed.inMicroseconds / 1000;
    final timeline = widget.timeline;
    final completed = !timeline.isContinuous && _elapsedMs >= timeline.endMs;
    if (mounted) setState(() {});
    if (completed) {
      _stopScheduler();
      _notifyAnimationEndAfterPaint();
    }
  }

  void _limitedTick() {
    _tick(Duration(microseconds: (_limitedStopwatch.elapsedMicroseconds)));
  }

  void _syncScheduler() {
    final shouldRun =
        widget.timeline.hasAnimations &&
        !widget.paused &&
        (widget.timeline.isContinuous || !_didComplete) &&
        widget.performanceController.quality != QuickjsUiEffectQuality.off;
    if (!shouldRun) {
      _stopScheduler();
      return;
    }
    final interval = widget.animationFrameIntervalMs;
    if (interval == null) {
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    if (_frameClock != null) return;
    _limitedStopwatch
      ..reset()
      ..start();
    _frameClock = widget.frameScheduler.clockFor(interval)
      ..addListener(_limitedTick);
  }

  void _stopScheduler() {
    if (_ticker.isActive) _ticker.stop();
    _frameClock?.removeListener(_limitedTick);
    _frameClock = null;
    _limitedStopwatch
      ..stop()
      ..reset();
  }

  void _qualityChanged() {
    if (!mounted) return;
    _syncScheduler();
    setState(() {});
  }

  void _notifyAnimationEndAfterPaint() {
    if (_didComplete) return;
    _didComplete = true;
    final generation = _generation;
    final callback = widget.onAnimationEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _generation) callback?.call();
    });
  }

  double _animationTimeMs() {
    if (!widget.reverse) return _elapsedMs;
    final endMs = widget.timeline.endMs;
    if (!endMs.isFinite) {
      throw const FormatException(
        'quickjs_ui cannot reverse a continuous widget effect',
      );
    }
    return math.max(0, endMs - _elapsedMs);
  }

  @override
  void dispose() {
    widget.performanceController.removeListener(_qualityChanged);
    _stopScheduler();
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final quality = widget.performanceController.quality;
    final resolvedElapsed = quality == QuickjsUiEffectQuality.off
        ? (widget.timeline.endMs.isFinite ? widget.timeline.endMs : 1e12)
        : _animationTimeMs();
    final clock = QuickjsUiAnimationClock(
      elapsedMs: resolvedElapsed,
      epochMs: DateTime.now().microsecondsSinceEpoch / 1000,
    );
    Widget result = widget.child;

    final colorFilter = widget.colorFilter;
    if (colorFilter is Map &&
        quality.index <= QuickjsUiEffectQuality.balanced.index) {
      final color = widget.resolveColor(colorFilter['color']);
      if (color != null) {
        result = RepaintBoundary(
          child: ClipRect(
            clipBehavior: Clip.hardEdge,
            child: ColorFiltered(
              colorFilter: ColorFilter.mode(
                color,
                _blendMode(colorFilter['blendMode']),
              ),
              child: result,
            ),
          ),
        );
      }
    }

    final blur = _qualityBlur(_blur(widget.blur, clock), quality);
    if (widget.blur != null && quality != QuickjsUiEffectQuality.off) {
      result = RepaintBoundary(
        child: ClipRect(
          clipBehavior: Clip.hardEdge,
          child: ImageFiltered(
            imageFilter: ui.ImageFilter.blur(sigmaX: blur.$1, sigmaY: blur.$2),
            child: result,
          ),
        ),
      );
    }

    final backdropBlur = _qualityBlur(
      _blur(widget.backdropBlur, clock),
      quality,
    );
    if (widget.backdropBlur != null &&
        quality.index <= QuickjsUiEffectQuality.balanced.index) {
      result = RepaintBoundary(
        child: ClipRect(
          clipBehavior: Clip.hardEdge,
          child: BackdropFilter(
            filter: ui.ImageFilter.blur(
              sigmaX: backdropBlur.$1,
              sigmaY: backdropBlur.$2,
            ),
            child: result,
          ),
        ),
      );
    }

    final radius = _number(widget.clipRadius, clock, fallback: 0);
    if (widget.clipRadius != null) {
      result = ClipRRect(
        borderRadius: BorderRadius.circular(radius),
        clipBehavior: widget.clipBehavior,
        child: result,
      );
    }

    final transform = widget.transform;
    if (transform is Map) {
      final alignment = _alignment(transform['alignment']);
      final scale = transform['scale'];
      final scaleX = scale is Map
          ? _number(scale['x'], clock, fallback: 1)
          : _number(scale, clock, fallback: 1);
      final scaleY = scale is Map
          ? _number(scale['y'], clock, fallback: scaleX)
          : scaleX;
      final rotation = _number(
        transform['rotate'] ?? transform['rotation'],
        clock,
        fallback: 0,
      );
      final translate = transform['translate'];
      var x = 0.0;
      var y = 0.0;
      if (translate is Map) {
        x = _number(translate['x'], clock, fallback: 0);
        y = _number(translate['y'], clock, fallback: 0);
      }
      if (widget.timeline.hasAnimations) {
        result = RepaintBoundary(child: result);
      }
      if (transform.containsKey('scale') ||
          transform.containsKey('rotate') ||
          transform.containsKey('rotation') ||
          translate is Map) {
        final matrix = Matrix4.translationValues(x, y, 0)
          ..rotateZ(rotation)
          ..multiply(Matrix4.diagonal3Values(scaleX, scaleY, 1));
        result = Transform(
          transform: matrix,
          alignment: alignment,
          child: result,
        );
      }
    }

    final opacity = _number(widget.opacity, clock, fallback: 1).clamp(0.0, 1.0);
    if (widget.opacity != null) {
      result = Opacity(opacity: opacity, child: result);
    }
    return result;
  }
}

int? _animationFrameIntervalMs(Object? value) {
  if (value == null) return null;
  final interval = QuickjsUiProps.intValue(
    value,
    name: 'animationFrameIntervalMs',
  );
  if (interval == null || interval < 4 || interval > 1000) {
    throw const FormatException(
      'quickjs_ui animationFrameIntervalMs must be between 4 and 1000',
    );
  }
  return interval;
}

(double, double) _qualityBlur(
  (double, double) blur,
  QuickjsUiEffectQuality quality,
) {
  final maximum = switch (quality) {
    QuickjsUiEffectQuality.high => 100.0,
    QuickjsUiEffectQuality.balanced => 12.0,
    QuickjsUiEffectQuality.low => 4.0,
    QuickjsUiEffectQuality.off => 0.0,
  };
  return (blur.$1.clamp(0, maximum), blur.$2.clamp(0, maximum));
}

(double, double) _blur(Object? raw, QuickjsUiAnimationClock clock) {
  if (raw is Map &&
      !(raw.containsKey('from') &&
          raw.containsKey('to') &&
          raw.containsKey('durationMs'))) {
    final x = _number(raw['sigmaX'] ?? raw['sigma'], clock, fallback: 0);
    final y = _number(raw['sigmaY'] ?? raw['sigma'], clock, fallback: x);
    return (x.clamp(0, 100).toDouble(), y.clamp(0, 100).toDouble());
  }
  final value = _number(raw, clock, fallback: 0).clamp(0, 100);
  return (value.toDouble(), value.toDouble());
}

double _number(
  Object? raw,
  QuickjsUiAnimationClock clock, {
  required double fallback,
}) {
  final value = quickjsUiAnimatedNumber(raw, clock) ?? fallback;
  if (!value.isFinite) {
    throw const FormatException('quickjs_ui effect values must be finite');
  }
  return value;
}

Clip _clipBehavior(Object? value) => switch (value) {
  'none' => Clip.none,
  'hardEdge' => Clip.hardEdge,
  'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
  _ => Clip.antiAlias,
};

Alignment _alignment(Object? value) => switch (value) {
  'topLeft' => Alignment.topLeft,
  'topCenter' => Alignment.topCenter,
  'topRight' => Alignment.topRight,
  'centerLeft' => Alignment.centerLeft,
  'centerRight' => Alignment.centerRight,
  'bottomLeft' => Alignment.bottomLeft,
  'bottomCenter' => Alignment.bottomCenter,
  'bottomRight' => Alignment.bottomRight,
  _ => Alignment.center,
};

BlendMode _blendMode(Object? value) => switch (value) {
  'multiply' => BlendMode.multiply,
  'screen' => BlendMode.screen,
  'overlay' => BlendMode.overlay,
  'darken' => BlendMode.darken,
  'lighten' => BlendMode.lighten,
  'plus' || 'add' => BlendMode.plus,
  'difference' => BlendMode.difference,
  _ => BlendMode.srcIn,
};
