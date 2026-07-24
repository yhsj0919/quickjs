import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_types.dart';
import 'quickjs_ui_canvas_scene.dart';
import 'quickjs_ui_animation.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_snapshot.dart';

part 'quickjs_ui_canvas_animation.dart';
part 'quickjs_ui_canvas_image.dart';
part 'quickjs_ui_canvas_particles.dart';

const int _maxCanvasCommands = 10000;
const int _maxPathSegments = 20000;
const int _maxSaveDepth = 128;
const int _maxSnapshotParticleFragments = 4096;

final QuickjsUiComponentBuilderMap quickjsUiCanvasComponentBuilders =
    <String, QuickjsUiComponentBuilder>{'Canvas': _buildCanvas};

Widget _buildCanvas(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final scene = _resolveScene(context, node);
  final staticCommands = scene.staticCommands;
  final commands = scene.commands;
  if (staticCommands.any(_containsAnimation)) {
    throw const FormatException(
      'quickjs_ui Canvas staticCommands cannot contain animations',
    );
  }
  final onFrame = QuickjsUiProps.event(node.props['onFrame']);
  final onAnimationEnd = QuickjsUiProps.event(node.props['onAnimationEnd']);
  final surface = _QuickjsUiCanvasSurface(
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    backgroundColor: context.color(node.props['backgroundColor']),
    staticCommands: staticCommands,
    commands: commands,
    resources: _canvasResources(node.props['resources']),
    paused: node.props['paused'] == true,
    playToken: node.props['playToken'],
    reverse: node.props['reverse'] == true,
    forceWillChange: node.props['willChange'] == true,
    snapshotRegistry: context.snapshotRegistry,
    onAnimationEnd: onAnimationEnd == null
        ? null
        : () => context.dispatchEvent(
            onAnimationEnd,
            defaultCoalesceKey:
                'Canvas:${node.key ?? 'anonymous'}:onAnimationEnd',
          ),
  );
  Widget canvas = RepaintBoundary(child: surface);
  canvas = _withPointerEvents(context, node, canvas);
  if (onFrame != null) {
    canvas = _QuickjsUiFrameSampler(
      interval: Duration(
        milliseconds: _frameIntervalMs(node.props['frameIntervalMs']),
      ),
      onFrame: (frame) => context.dispatchEvent(
        onFrame,
        payload: frame,
        defaultCoalesceKey: 'Canvas:${node.key ?? 'anonymous'}:onFrame',
        kind: QuickjsUiEventKind.sample,
      ),
      child: canvas,
    );
  }
  return withQuickjsUiGestures(context, node, canvas);
}

Map<String, String> _canvasResources(Object? raw) {
  if (raw == null) return const <String, String>{};
  if (raw is! Map) {
    throw const FormatException(
      'quickjs_ui Canvas resources must be an object',
    );
  }
  return Map<String, String>.unmodifiable(
    raw.map((key, value) {
      if (value is! String || value.isEmpty) {
        throw const FormatException(
          'quickjs_ui Canvas resource values must be snapshot ids',
        );
      }
      return MapEntry('$key', value);
    }),
  );
}

QuickjsUiCanvasScene _resolveScene(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final sceneKey = QuickjsUiProps.string(node.props['sceneKey']);
  final hasCommands = node.props.containsKey('commands');
  final hasStaticCommands = node.props.containsKey('staticCommands');
  if (sceneKey == null) {
    return QuickjsUiCanvasScene(
      commands: _commands(node.props['commands'], name: 'commands'),
      staticCommands: _commands(
        node.props['staticCommands'],
        name: 'staticCommands',
        optional: true,
      ),
    );
  }
  if (sceneKey.isEmpty) {
    throw const FormatException('quickjs_ui Canvas sceneKey cannot be empty');
  }
  if (hasCommands || hasStaticCommands) {
    if (!hasCommands) {
      throw FormatException(
        'quickjs_ui Canvas scene "$sceneKey" requires commands when registered',
      );
    }
    final scene = QuickjsUiCanvasScene(
      commands: _commands(node.props['commands'], name: 'commands'),
      staticCommands: _commands(
        node.props['staticCommands'],
        name: 'staticCommands',
        optional: true,
      ),
    );
    context.canvasSceneRegistry.register(sceneKey, scene);
    return scene;
  }
  final scene = context.canvasSceneRegistry.resolve(sceneKey);
  if (scene == null) {
    throw FormatException(
      'quickjs_ui Canvas scene "$sceneKey" has not been registered',
    );
  }
  return scene;
}

List<Map<String, Object?>> _commands(
  Object? raw, {
  required String name,
  bool optional = false,
}) {
  if (raw == null && optional) return const <Map<String, Object?>>[];
  if (raw is! List) {
    throw FormatException('quickjs_ui Canvas $name must be a list');
  }
  if (raw.length > _maxCanvasCommands) {
    throw const FormatException('quickjs_ui Canvas command limit exceeded');
  }
  final commands = <Map<String, Object?>>[
    for (final value in raw) _commandMap(value),
  ];
  _validateCommands(commands);
  return commands;
}

void _validateCommands(List<Map<String, Object?>> commands) {
  const ops = <String>{
    'clear',
    'save',
    'restore',
    'translate',
    'rotate',
    'scale',
    'clipRect',
    'line',
    'rect',
    'circle',
    'arc',
    'path',
    'text',
    'image',
    'snapshotParticleGrid',
  };
  var saveDepth = 0;
  var pathSegments = 0;
  for (var index = 0; index < commands.length; index += 1) {
    final op = commands[index]['op'];
    if (op is! String || !ops.contains(op)) {
      throw FormatException('Unsupported quickjs_ui Canvas op "$op" at $index');
    }
    if (op == 'save' && ++saveDepth > _maxSaveDepth) {
      throw const FormatException(
        'quickjs_ui Canvas save depth limit exceeded',
      );
    }
    if (op == 'restore' && --saveDepth < 0) {
      throw FormatException(
        'quickjs_ui Canvas restore at $index has no matching save',
      );
    }
    if (op == 'path') {
      final segments = commands[index]['segments'];
      if (segments is! List) {
        throw const FormatException(
          'quickjs_ui Canvas path segments must be a list',
        );
      }
      pathSegments += segments.length;
      if (pathSegments > _maxPathSegments) {
        throw const FormatException(
          'quickjs_ui Canvas path segment limit exceeded',
        );
      }
    }
    if (op == 'snapshotParticleGrid') {
      _validateSnapshotParticleGrid(commands[index]);
    }
  }
  if (saveDepth != 0) {
    throw const FormatException(
      'quickjs_ui Canvas save and restore commands must be balanced',
    );
  }
}

Widget _withPointerEvents(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Widget child,
) {
  final down = QuickjsUiProps.event(node.props['onPointerDown']);
  final move = QuickjsUiProps.event(node.props['onPointerMove']);
  final up = QuickjsUiProps.event(node.props['onPointerUp']);
  final cancel = QuickjsUiProps.event(node.props['onPointerCancel']);
  if (down == null && move == null && up == null && cancel == null) {
    return child;
  }
  void dispatch(
    Map<String, Object?> event,
    PointerEvent details,
    String prop, {
    bool sample = false,
  }) {
    context.dispatchEvent(
      event,
      defaultCoalesceKey: quickjsUiEventKey(node, prop),
      kind: sample ? QuickjsUiEventKind.sample : QuickjsUiEventKind.command,
      payload: <String, Object?>{
        'pointer': details.pointer,
        'x': details.localPosition.dx,
        'y': details.localPosition.dy,
        'globalX': details.position.dx,
        'globalY': details.position.dy,
        'deltaX': details.delta.dx,
        'deltaY': details.delta.dy,
        'buttons': details.buttons,
        'pressure': details.pressure,
        'timestampMs': DateTime.now().millisecondsSinceEpoch,
      },
    );
  }

  return Listener(
    behavior: HitTestBehavior.opaque,
    onPointerDown: down == null
        ? null
        : (details) => dispatch(down, details, 'onPointerDown'),
    onPointerMove: move == null
        ? null
        : (details) => dispatch(move, details, 'onPointerMove', sample: true),
    onPointerUp: up == null
        ? null
        : (details) => dispatch(up, details, 'onPointerUp'),
    onPointerCancel: cancel == null
        ? null
        : (details) => dispatch(cancel, details, 'onPointerCancel'),
    child: child,
  );
}

final class _QuickjsUiCanvasSurface extends StatefulWidget {
  _QuickjsUiCanvasSurface({
    required this.width,
    required this.height,
    required this.backgroundColor,
    required this.staticCommands,
    required this.commands,
    required this.resources,
    required this.paused,
    required this.playToken,
    required this.reverse,
    required this.forceWillChange,
    required this.snapshotRegistry,
    required this.onAnimationEnd,
  }) : timeline = QuickjsUiAnimationTimeline.from(commands);

  final double? width;
  final double? height;
  final Color? backgroundColor;
  final List<Map<String, Object?>> staticCommands;
  final List<Map<String, Object?>> commands;
  final Map<String, String> resources;
  final bool paused;
  final Object? playToken;
  final bool reverse;
  final bool forceWillChange;
  final QuickjsUiSnapshotRegistry snapshotRegistry;
  final VoidCallback? onAnimationEnd;
  final QuickjsUiAnimationTimeline timeline;

  @override
  State<_QuickjsUiCanvasSurface> createState() =>
      _QuickjsUiCanvasSurfaceState();
}

final class _QuickjsUiCanvasSurfaceState extends State<_QuickjsUiCanvasSurface>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  final _repaint = _CanvasRepaintSignal();
  double _elapsedMs = 0;
  double _playbackOffsetMs = 0;
  bool _didCompleteAnimation = false;
  int _animationGeneration = 0;
  late _QuickjsUiCanvasPainter _painter;

  @override
  void initState() {
    super.initState();
    _painter = _createPainter();
    _ticker = createTicker((elapsed) {
      _elapsedMs = _playbackOffsetMs + elapsed.inMicroseconds / 1000;
      _repaint.repaint();
      final timeline = widget.timeline;
      if (!timeline.isContinuous && _elapsedMs >= timeline.endMs) {
        _ticker.stop();
        _notifyAnimationEndAfterPaint();
      }
    });
    _syncTicker();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiCanvasSurface oldWidget) {
    super.didUpdateWidget(oldWidget);
    final restart =
        !identical(oldWidget.commands, widget.commands) ||
        oldWidget.playToken != widget.playToken ||
        oldWidget.reverse != widget.reverse;
    if (restart) {
      if (_ticker.isActive) _ticker.stop();
      _elapsedMs = 0;
      _playbackOffsetMs = 0;
      _didCompleteAnimation = false;
      _animationGeneration += 1;
    } else if (!oldWidget.paused && widget.paused) {
      _playbackOffsetMs = _elapsedMs;
    }
    _painter.disposePicture();
    _painter = _createPainter();
    _syncTicker();
  }

  _QuickjsUiCanvasPainter _createPainter() => _QuickjsUiCanvasPainter(
    staticCommands: widget.staticCommands,
    commands: widget.commands,
    backgroundColor: widget.backgroundColor,
    snapshotRegistry: widget.snapshotRegistry,
    resources: widget.resources,
    elapsedMs: _animationTimeMs,
    repaint: _repaint,
  );

  void _syncTicker() {
    if (widget.timeline.hasAnimations && !widget.paused) {
      if (!_ticker.isActive) _ticker.start();
    } else {
      if (_ticker.isActive) _ticker.stop();
    }
  }

  double _animationTimeMs() {
    if (!widget.reverse) return _elapsedMs;
    final endMs = widget.timeline.endMs;
    if (!endMs.isFinite) {
      throw const FormatException(
        'quickjs_ui Canvas cannot reverse a continuous animation',
      );
    }
    return math.max(0, endMs - _elapsedMs);
  }

  void _notifyAnimationEndAfterPaint() {
    if (_didCompleteAnimation) return;
    _didCompleteAnimation = true;
    final generation = _animationGeneration;
    final callback = widget.onAnimationEnd;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && generation == _animationGeneration) callback?.call();
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    _painter.disposePicture();
    _repaint.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: widget.width,
      height: widget.height,
      child: CustomPaint(
        painter: _painter,
        isComplex: widget.staticCommands.length + widget.commands.length > 20,
        willChange:
            widget.forceWillChange ||
            (widget.timeline.hasAnimations && !widget.paused),
      ),
    );
  }
}

final class _CanvasRepaintSignal extends ChangeNotifier {
  void repaint() => notifyListeners();
}

final class _QuickjsUiCanvasPainter extends CustomPainter {
  _QuickjsUiCanvasPainter({
    required this.staticCommands,
    required this.commands,
    required this.backgroundColor,
    required this.snapshotRegistry,
    required this.resources,
    required this.elapsedMs,
    required Listenable repaint,
  }) : super(repaint: repaint);

  final List<Map<String, Object?>> staticCommands;
  final List<Map<String, Object?>> commands;
  final Color? backgroundColor;
  final QuickjsUiSnapshotRegistry snapshotRegistry;
  final Map<String, String> resources;
  final double Function() elapsedMs;
  ui.Picture? _staticPicture;
  Size? _staticPictureSize;

  @override
  void paint(Canvas canvas, Size size) {
    if (backgroundColor case final color?) {
      canvas.drawRect(Offset.zero & size, Paint()..color = color);
    }
    if (staticCommands.isNotEmpty) {
      if (_staticPicture == null || _staticPictureSize != size) {
        _staticPicture?.dispose();
        final recorder = ui.PictureRecorder();
        _paintCommands(
          Canvas(recorder),
          size,
          staticCommands,
          const _CanvasClock(elapsedMs: 0, epochMs: 0),
          snapshotRegistry,
          resources,
        );
        _staticPicture = recorder.endRecording();
        _staticPictureSize = size;
      }
      canvas.drawPicture(_staticPicture!);
    }
    _paintCommands(
      canvas,
      size,
      commands,
      _CanvasClock(
        elapsedMs: elapsedMs(),
        epochMs: DateTime.now().microsecondsSinceEpoch / 1000,
      ),
      snapshotRegistry,
      resources,
    );
  }

  void disposePicture() {
    _staticPicture?.dispose();
    _staticPicture = null;
  }

  @override
  bool shouldRepaint(covariant _QuickjsUiCanvasPainter oldDelegate) => true;
}

final class _QuickjsUiFrameSampler extends StatefulWidget {
  const _QuickjsUiFrameSampler({
    required this.interval,
    required this.onFrame,
    required this.child,
  });

  final Duration interval;
  final ValueChanged<Map<String, Object?>> onFrame;
  final Widget child;

  @override
  State<_QuickjsUiFrameSampler> createState() => _QuickjsUiFrameSamplerState();
}

final class _QuickjsUiFrameSamplerState extends State<_QuickjsUiFrameSampler>
    with SingleTickerProviderStateMixin {
  late final Ticker _ticker;
  Duration? _lastDispatchElapsed;
  int _frame = 0;

  @override
  void initState() {
    super.initState();
    _ticker = createTicker(_tick)..start();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiFrameSampler oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.interval != widget.interval) _lastDispatchElapsed = null;
  }

  void _tick(Duration elapsed) {
    final previous = _lastDispatchElapsed;
    if (previous != null && elapsed - previous < widget.interval) return;
    _lastDispatchElapsed = elapsed;
    widget.onFrame(<String, Object?>{
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
      'elapsedMs': elapsed.inMicroseconds / 1000,
      'deltaMs': previous == null
          ? 0.0
          : (elapsed - previous).inMicroseconds / 1000,
      'frame': _frame++,
    });
  }

  @override
  void dispose() {
    _ticker.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

void _paintCommands(
  Canvas canvas,
  Size size,
  List<Map<String, Object?>> commands,
  _CanvasClock clock,
  QuickjsUiSnapshotRegistry snapshotRegistry,
  Map<String, String> resources,
) {
  var saveDepth = 0;
  for (final command in commands) {
    switch (command['op']) {
      case 'clear':
        canvas.drawRect(
          Offset.zero & size,
          Paint()
            ..blendMode = BlendMode.src
            ..color = _color(command['color']) ?? Colors.transparent,
        );
      case 'save':
        canvas.save();
        saveDepth += 1;
      case 'restore':
        canvas.restore();
        saveDepth -= 1;
      case 'translate':
        canvas.translate(
          _number(command['x'], 'x', clock),
          _number(command['y'], 'y', clock),
        );
      case 'rotate':
        canvas.rotate(_number(command['radians'], 'radians', clock));
      case 'scale':
        final x = _number(command['x'], 'x', clock);
        canvas.scale(x, _optionalNumber(command['y'], clock) ?? x);
      case 'clipRect':
        canvas.clipRect(_rect(command, clock));
      case 'line':
        canvas.drawLine(
          Offset(
            _number(command['x1'], 'x1', clock),
            _number(command['y1'], 'y1', clock),
          ),
          Offset(
            _number(command['x2'], 'x2', clock),
            _number(command['y2'], 'y2', clock),
          ),
          _paint(command, clock, fill: false),
        );
      case 'rect':
        final rect = _rect(command, clock);
        final radius = _optionalNumber(command['radius'], clock) ?? 0;
        _drawFillAndStroke(canvas, command, clock, (paint) {
          if (radius > 0) {
            canvas.drawRRect(
              RRect.fromRectAndRadius(rect, Radius.circular(radius)),
              paint,
            );
          } else {
            canvas.drawRect(rect, paint);
          }
        });
      case 'circle':
        final center = Offset(
          _number(command['cx'], 'cx', clock),
          _number(command['cy'], 'cy', clock),
        );
        final radius = _number(command['radius'], 'radius', clock);
        _drawFillAndStroke(
          canvas,
          command,
          clock,
          (paint) => canvas.drawCircle(center, radius, paint),
        );
      case 'arc':
        final rect = Rect.fromCircle(
          center: Offset(
            _number(command['cx'], 'cx', clock),
            _number(command['cy'], 'cy', clock),
          ),
          radius: _number(command['radius'], 'radius', clock),
        );
        _drawFillAndStroke(
          canvas,
          command,
          clock,
          (paint) => canvas.drawArc(
            rect,
            _number(command['start'], 'start', clock),
            _number(command['sweep'], 'sweep', clock),
            command['useCenter'] == true,
            paint,
          ),
        );
      case 'path':
        final path = _path(command['segments'], clock);
        _drawFillAndStroke(
          canvas,
          command,
          clock,
          (paint) => canvas.drawPath(path, paint),
        );
      case 'text':
        _drawText(canvas, command, clock);
      case 'image':
        _drawSnapshotImage(canvas, command, clock, snapshotRegistry, resources);
      case 'snapshotParticleGrid':
        _drawSnapshotParticleGrid(
          canvas,
          command,
          clock,
          snapshotRegistry,
          resources,
        );
    }
  }
  assert(saveDepth == 0);
}

void _drawFillAndStroke(
  Canvas canvas,
  Map<String, Object?> command,
  _CanvasClock clock,
  void Function(Paint paint) draw,
) {
  final hasFill = command['fill'] != null;
  final hasStroke = command['stroke'] != null;
  if (hasFill) draw(_paint(command, clock, fill: true));
  if (hasStroke || !hasFill) draw(_paint(command, clock, fill: false));
}

Paint _paint(
  Map<String, Object?> command,
  _CanvasClock clock, {
  required bool fill,
}) {
  final opacity = (_optionalNumber(command['globalAlpha'], clock) ?? 1.0).clamp(
    0.0,
    1.0,
  );
  final color =
      _color(fill ? command['fill'] : command['stroke']) ?? Colors.black;
  return Paint()
    ..isAntiAlias = command['antiAlias'] != false
    ..style = fill ? PaintingStyle.fill : PaintingStyle.stroke
    ..color = color.withValues(alpha: color.a * opacity)
    ..strokeWidth = _optionalNumber(command['strokeWidth'], clock) ?? 1
    ..strokeCap = switch (command['strokeCap']) {
      'round' => StrokeCap.round,
      'square' => StrokeCap.square,
      _ => StrokeCap.butt,
    }
    ..strokeJoin = switch (command['strokeJoin']) {
      'round' => StrokeJoin.round,
      'bevel' => StrokeJoin.bevel,
      _ => StrokeJoin.miter,
    }
    ..blendMode = _blendMode(command['blendMode']);
}

BlendMode _blendMode(Object? value) => switch (value) {
  'multiply' => BlendMode.multiply,
  'screen' => BlendMode.screen,
  'overlay' => BlendMode.overlay,
  'darken' => BlendMode.darken,
  'lighten' => BlendMode.lighten,
  'plus' || 'add' => BlendMode.plus,
  'difference' => BlendMode.difference,
  'clear' => BlendMode.clear,
  _ => BlendMode.srcOver,
};

Rect _rect(Map<String, Object?> command, _CanvasClock clock) => Rect.fromLTWH(
  _number(command['x'], 'x', clock),
  _number(command['y'], 'y', clock),
  _number(command['width'], 'width', clock),
  _number(command['height'], 'height', clock),
);

Path _path(Object? rawSegments, _CanvasClock clock) {
  final segments = rawSegments! as List;
  final path = Path();
  for (final raw in segments) {
    final segment = _commandMap(raw);
    switch (segment['op']) {
      case 'moveTo':
        path.moveTo(
          _number(segment['x'], 'x', clock),
          _number(segment['y'], 'y', clock),
        );
      case 'lineTo':
        path.lineTo(
          _number(segment['x'], 'x', clock),
          _number(segment['y'], 'y', clock),
        );
      case 'quadraticTo':
        path.quadraticBezierTo(
          _number(segment['cx'], 'cx', clock),
          _number(segment['cy'], 'cy', clock),
          _number(segment['x'], 'x', clock),
          _number(segment['y'], 'y', clock),
        );
      case 'cubicTo':
        path.cubicTo(
          _number(segment['cx1'], 'cx1', clock),
          _number(segment['cy1'], 'cy1', clock),
          _number(segment['cx2'], 'cx2', clock),
          _number(segment['cy2'], 'cy2', clock),
          _number(segment['x'], 'x', clock),
          _number(segment['y'], 'y', clock),
        );
      case 'arc':
        final start = _number(segment['start'], 'start', clock);
        final end = _number(segment['end'], 'end', clock);
        var sweep = end - start;
        if (segment['counterclockwise'] == true && sweep > 0) {
          sweep -= math.pi * 2;
        } else if (segment['counterclockwise'] != true && sweep < 0) {
          sweep += math.pi * 2;
        }
        path.arcTo(
          Rect.fromCircle(
            center: Offset(
              _number(segment['cx'], 'cx', clock),
              _number(segment['cy'], 'cy', clock),
            ),
            radius: _number(segment['radius'], 'radius', clock),
          ),
          start,
          sweep,
          false,
        );
      case 'close':
        path.close();
      default:
        throw FormatException(
          'Unsupported quickjs_ui Canvas path op "${segment['op']}"',
        );
    }
  }
  return path;
}

void _drawText(
  Canvas canvas,
  Map<String, Object?> command,
  _CanvasClock clock,
) {
  final opacity = (_optionalNumber(command['globalAlpha'], clock) ?? 1.0).clamp(
    0.0,
    1.0,
  );
  final color = _color(command['color']) ?? Colors.black;
  final painter =
      TextPainter(
        text: TextSpan(
          text: '${command['text'] ?? ''}',
          style: TextStyle(
            color: color.withValues(alpha: color.a * opacity),
            fontSize: _optionalNumber(command['fontSize'], clock) ?? 14,
            fontWeight: command['fontWeight'] == 'bold'
                ? FontWeight.bold
                : FontWeight.normal,
            fontFamily: command['fontFamily'] as String?,
          ),
        ),
        textDirection: TextDirection.ltr,
        textAlign: switch (command['align']) {
          'center' => TextAlign.center,
          'right' => TextAlign.right,
          _ => TextAlign.left,
        },
      )..layout(
        maxWidth:
            _optionalNumber(command['maxWidth'], clock) ?? double.infinity,
      );
  var x = _number(command['x'], 'x', clock);
  if (command['align'] == 'center') x -= painter.width / 2;
  if (command['align'] == 'right') x -= painter.width;
  var y = _number(command['y'], 'y', clock);
  y -= switch (command['baseline']) {
    'top' || 'hanging' => 0,
    'middle' => painter.height / 2,
    'bottom' || 'ideographic' => painter.height,
    _ => painter.computeDistanceToActualBaseline(TextBaseline.alphabetic),
  };
  painter.paint(canvas, Offset(x, y));
}

Map<String, Object?> _commandMap(Object? raw) {
  if (raw is! Map) {
    throw const FormatException('quickjs_ui Canvas command must be an object');
  }
  return raw.map((key, value) => MapEntry<String, Object?>('$key', value));
}

int _frameIntervalMs(Object? value) {
  final interval = value == null
      ? 16
      : QuickjsUiProps.intValue(value, name: 'Canvas frameIntervalMs');
  if (interval == null || interval < 16 || interval > 60000) {
    throw const FormatException(
      'quickjs_ui Canvas frameIntervalMs must be between 16 and 60000',
    );
  }
  return interval;
}

Color? _color(Object? value) {
  if (value == null) return null;
  if (value is int) return Color(value);
  if (value is! String) {
    throw const FormatException('quickjs_ui Canvas color must be a string');
  }
  var hex = value.trim();
  if (hex.startsWith('#')) hex = hex.substring(1);
  if (hex.length == 6) hex = 'FF$hex';
  if (hex.length != 8) {
    throw FormatException('Invalid quickjs_ui Canvas color "$value"');
  }
  return Color(int.parse(hex, radix: 16));
}
