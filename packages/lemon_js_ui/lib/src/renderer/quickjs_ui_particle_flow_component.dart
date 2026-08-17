// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_types.dart';
import 'quickjs_ui_frame_scheduler.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiParticleFlowComponentBuilders =
    <String, JsUiComponentBuilder>{'ParticleFlow': _buildParticleFlow};

Widget _buildParticleFlow(JsUiRenderContext context, JsUiNode node) {
  final width = JsUiProps.doubleValue(node.props['width']);
  final height = JsUiProps.doubleValue(node.props['height']);
  if (width == null || width <= 0 || height == null || height <= 0) {
    throw const FormatException(
      'quickjs_ui ParticleFlow requires positive width and height',
    );
  }
  final children = context.children(node);
  final particles = _particles(node.props['particles']);
  if (particles.length != children.length) {
    throw const FormatException(
      'quickjs_ui ParticleFlow particles and children must have equal length',
    );
  }
  final intervalMs = JsUiProps.intValue(node.props['frameIntervalMs']);
  if (intervalMs != null && (intervalMs < 4 || intervalMs > 1000)) {
    throw const FormatException(
      'quickjs_ui ParticleFlow frameIntervalMs must be between 4 and 1000',
    );
  }
  return _ParticleFlow(
    width: width,
    height: height,
    particles: particles,
    frameIntervalMs: intervalMs,
    paused: node.props['paused'] == true,
    playToken: node.props['playToken'],
    frameScheduler: context.frameScheduler,
    children: children,
  );
}

List<_Particle> _particles(Object? value) {
  if (value is! List) {
    throw const FormatException(
      'quickjs_ui ParticleFlow particles must be an array',
    );
  }
  return List<_Particle>.generate(value.length, (index) {
    final item = value[index];
    if (item is! Map) {
      throw FormatException(
        'quickjs_ui ParticleFlow particles[$index] must be an object',
      );
    }
    double number(String name, {double? fallback}) {
      final resolved = JsUiProps.doubleValue(item[name]) ?? fallback;
      if (resolved == null || !resolved.isFinite) {
        throw FormatException(
          'quickjs_ui ParticleFlow particles[$index].$name must be a number',
        );
      }
      return resolved;
    }

    final durationMs = number('durationMs');
    if (durationMs <= 0) {
      throw FormatException(
        'quickjs_ui ParticleFlow particles[$index].durationMs must be positive',
      );
    }
    return _Particle(
      fromX: number('fromX'),
      toX: number('toX'),
      fromY: number('fromY'),
      toY: number('toY'),
      fromOpacity: number('fromOpacity', fallback: 1).clamp(0, 1),
      toOpacity: number('toOpacity', fallback: 1).clamp(0, 1),
      fromScale: number('fromScale', fallback: 1),
      toScale: number('toScale', fallback: 1),
      fromRotation: number('fromRotation', fallback: 0),
      toRotation: number('toRotation', fallback: 0),
      durationMs: durationMs,
      phaseMs: number('phaseMs', fallback: 0),
    );
  }, growable: false);
}

class _ParticleFlow extends StatefulWidget {
  const _ParticleFlow({
    required this.width,
    required this.height,
    required this.particles,
    required this.frameIntervalMs,
    required this.paused,
    required this.playToken,
    required this.frameScheduler,
    required this.children,
  });

  final double width;
  final double height;
  final List<_Particle> particles;
  final int? frameIntervalMs;
  final bool paused;
  final Object? playToken;
  final JsUiFrameScheduler frameScheduler;
  final List<Widget> children;

  @override
  State<_ParticleFlow> createState() => _ParticleFlowState();
}

class _ParticleFlowState extends State<_ParticleFlow>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _ParticleRepaint _repaint = _ParticleRepaint();
  final Stopwatch _stopwatch = Stopwatch();
  JsUiFrameClock? _frameClock;
  double _elapsedMs = 0;
  double _playbackOffsetMs = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_onTicker);
    _syncClock();
  }

  @override
  void didUpdateWidget(covariant _ParticleFlow oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.playToken != widget.playToken) {
      _playbackOffsetMs = 0;
      _elapsedMs = 0;
      _stopClock();
    } else if (!oldWidget.paused && widget.paused) {
      _playbackOffsetMs = _elapsedMs;
      _stopClock();
    } else if (oldWidget.frameIntervalMs != widget.frameIntervalMs ||
        oldWidget.frameScheduler != widget.frameScheduler) {
      _playbackOffsetMs = _elapsedMs;
      _stopClock();
    }
    _syncClock();
  }

  void _syncClock() {
    if (widget.paused || _ticker.isActive || _frameClock != null) return;
    _stopwatch
      ..reset()
      ..start();
    final interval = widget.frameIntervalMs;
    if (interval == null) {
      if (!_ticker.isActive) _ticker.start();
      return;
    }
    _frameClock = widget.frameScheduler.clockFor(interval)
      ..addListener(_onLimitedFrame);
  }

  void _onTicker(Duration elapsed) {
    _elapsedMs = _playbackOffsetMs + elapsed.inMicroseconds / 1000;
    _repaint.markFrame();
  }

  void _onLimitedFrame() {
    _elapsedMs = _playbackOffsetMs + _stopwatch.elapsedMicroseconds / 1000;
    _repaint.markFrame();
  }

  void _stopClock() {
    if (_ticker.isActive) _ticker.stop();
    _frameClock?.removeListener(_onLimitedFrame);
    _frameClock = null;
    _stopwatch
      ..stop()
      ..reset();
  }

  @override
  void dispose() {
    _stopClock();
    _ticker.dispose();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: Flow(
        clipBehavior: Clip.none,
        delegate: _ParticleFlowDelegate(
          particles: widget.particles,
          elapsedMs: () => _elapsedMs,
          repaint: _repaint,
        ),
        children: widget.children,
      ),
    );
  }
}

class _ParticleFlowDelegate extends FlowDelegate {
  _ParticleFlowDelegate({
    required this.particles,
    required this.elapsedMs,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<_Particle> particles;
  final double Function() elapsedMs;

  @override
  BoxConstraints getConstraintsForChild(int index, BoxConstraints constraints) {
    return BoxConstraints.loose(constraints.biggest);
  }

  @override
  void paintChildren(FlowPaintingContext context) {
    final elapsed = elapsedMs();
    final count = math.min(context.childCount, particles.length);
    for (var index = 0; index < count; index += 1) {
      final particle = particles[index];
      final time = elapsed + particle.phaseMs;
      final progress =
          ((time % particle.durationMs) + particle.durationMs) %
          particle.durationMs /
          particle.durationMs;
      final y = particle.fromY + (particle.toY - particle.fromY) * progress;
      final x = particle.fromX + (particle.toX - particle.fromX) * progress;
      final scale =
          particle.fromScale +
          (particle.toScale - particle.fromScale) * progress;
      final rotation =
          particle.fromRotation +
          (particle.toRotation - particle.fromRotation) * progress;
      final opacity =
          particle.fromOpacity +
          (particle.toOpacity - particle.fromOpacity) * progress;
      final transform = rotation == 0 && scale == 1
          ? Matrix4.translationValues(x, y, 0)
          : (Matrix4.translationValues(x, y, 0)
              ..rotateZ(rotation)
              ..multiply(Matrix4.diagonal3Values(scale, scale, 1)));
      context.paintChild(index, transform: transform, opacity: opacity);
    }
  }

  @override
  bool shouldRepaint(covariant _ParticleFlowDelegate oldDelegate) {
    return oldDelegate.particles != particles;
  }
}

class _Particle {
  const _Particle({
    required this.fromX,
    required this.toX,
    required this.fromY,
    required this.toY,
    required this.fromOpacity,
    required this.toOpacity,
    required this.fromScale,
    required this.toScale,
    required this.fromRotation,
    required this.toRotation,
    required this.durationMs,
    required this.phaseMs,
  });

  final double fromX;
  final double toX;
  final double fromY;
  final double toY;
  final double fromOpacity;
  final double toOpacity;
  final double fromScale;
  final double toScale;
  final double fromRotation;
  final double toRotation;
  final double durationMs;
  final double phaseMs;
}

class _ParticleRepaint extends ChangeNotifier {
  void markFrame() => notifyListeners();
}
