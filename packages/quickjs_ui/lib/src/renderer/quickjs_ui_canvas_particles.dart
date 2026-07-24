part of 'quickjs_ui_canvas_component.dart';

void _validateSnapshotParticleGrid(Map<String, Object?> command) {
  String slot(String name) {
    final value = command[name];
    if (value is! String || value.isEmpty) {
      throw FormatException(
        'quickjs_ui Canvas snapshotParticleGrid $name must be a non-empty string',
      );
    }
    return value;
  }

  double positiveNumber(String name) {
    final value = command[name];
    if (value is! num || !value.isFinite || value <= 0) {
      throw FormatException(
        'quickjs_ui Canvas snapshotParticleGrid $name must be positive',
      );
    }
    return value.toDouble();
  }

  void optionalFiniteNumber(String name) {
    final value = command[name];
    if (value != null && (value is! num || !value.isFinite)) {
      throw FormatException(
        'quickjs_ui Canvas snapshotParticleGrid $name must be finite',
      );
    }
  }

  int positiveInt(String name) {
    final value = command[name];
    if (value is! int || value <= 0) {
      throw FormatException(
        'quickjs_ui Canvas snapshotParticleGrid $name must be a positive integer',
      );
    }
    return value;
  }

  slot('sourceSlot');
  slot('targetSlot');
  optionalFiniteNumber('x');
  optionalFiniteNumber('y');
  positiveNumber('width');
  positiveNumber('height');
  positiveNumber('travelMs');
  positiveNumber('fadeMs');
  positiveNumber('staggerMs');
  final columns = positiveInt('columns');
  final rows = positiveInt('rows');
  positiveInt('bucketCount');
  if (columns * rows > _maxSnapshotParticleFragments) {
    throw const FormatException(
      'quickjs_ui Canvas snapshotParticleGrid fragment limit exceeded',
    );
  }
}

void _drawSnapshotParticleGrid(
  Canvas canvas,
  Map<String, Object?> command,
  _CanvasClock clock,
  QuickjsUiSnapshotRegistry registry,
  Map<String, String> resources,
) {
  final source = _resolveSnapshotSlot(
    command['sourceSlot'],
    registry,
    resources,
  );
  final target = _resolveSnapshotSlot(
    command['targetSlot'],
    registry,
    resources,
  );
  if (source == null || target == null) return;

  final x = _rawFiniteNumber(command['x'], fallback: 0);
  final y = _rawFiniteNumber(command['y'], fallback: 0);
  final width = _rawFiniteNumber(command['width']);
  final height = _rawFiniteNumber(command['height']);
  final columns = command['columns'] as int;
  final rows = command['rows'] as int;
  final bucketCount = command['bucketCount'] as int;
  final staggerMs = _rawFiniteNumber(command['staggerMs']);
  final travelMs = _rawFiniteNumber(command['travelMs']);
  final fadeMs = _rawFiniteNumber(command['fadeMs']);
  final cellWidth = width / columns;
  final cellHeight = height / rows;
  final rowDivisor = math.max(1, rows - 1);

  for (var row = 0; row < rows; row += 1) {
    for (var column = 0; column < columns; column += 1) {
      final index = row * columns + column;
      final randomA = _particleHash(index + 1);
      final randomB = _particleHash(index + 701);
      final randomC = _particleHash(index + 1409);
      final bucket =
          ((row / rowDivisor) * (bucketCount - 1) + (randomA - 0.5) * 7)
              .clamp(0, bucketCount - 1)
              .round();
      final outgoingDelay = math.max(0, bucket - 3) * staggerMs;
      final incomingDelay =
          math.max(0, bucketCount - 1 - bucket - 3) * staggerMs;
      final sourceX = column * cellWidth;
      final sourceY = row * cellHeight;
      final centerX = x + sourceX + cellWidth / 2;
      final centerY = y + sourceY + cellHeight / 2;
      final driftX = 72 + randomB * 104;
      final driftY = -26 - randomC * 88 + (randomA - 0.5) * 28;
      final rotation = (randomB - 0.5) * 1.45;

      _drawSnapshotParticle(
        canvas: canvas,
        snapshot: source,
        sourceX: sourceX,
        sourceY: sourceY,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        centerX: centerX,
        centerY: centerY,
        driftX: driftX,
        driftY: driftY,
        rotation: rotation,
        delayMs: outgoingDelay,
        travelMs: travelMs,
        fadeMs: fadeMs,
        elapsedMs: clock.elapsedMs,
        incoming: false,
      );
      _drawSnapshotParticle(
        canvas: canvas,
        snapshot: target,
        sourceX: sourceX,
        sourceY: sourceY,
        cellWidth: cellWidth,
        cellHeight: cellHeight,
        centerX: centerX,
        centerY: centerY,
        driftX: driftX,
        driftY: driftY,
        rotation: rotation,
        delayMs: incomingDelay,
        travelMs: travelMs,
        fadeMs: fadeMs,
        elapsedMs: clock.elapsedMs,
        incoming: true,
      );
    }
  }
}

void _drawSnapshotParticle({
  required Canvas canvas,
  required QuickjsUiSnapshot snapshot,
  required double sourceX,
  required double sourceY,
  required double cellWidth,
  required double cellHeight,
  required double centerX,
  required double centerY,
  required double driftX,
  required double driftY,
  required double rotation,
  required double delayMs,
  required double travelMs,
  required double fadeMs,
  required double elapsedMs,
  required bool incoming,
}) {
  final travel = _particleProgress(elapsedMs, delayMs, travelMs, easeIn: false);
  final fade = _particleProgress(elapsedMs, delayMs, fadeMs, easeIn: !incoming);
  final ratio = snapshot.pixelRatio;
  final source =
      Rect.fromLTWH(
        sourceX * ratio,
        sourceY * ratio,
        cellWidth * ratio,
        cellHeight * ratio,
      ).intersect(
        Rect.fromLTWH(
          0,
          0,
          snapshot.image.width.toDouble(),
          snapshot.image.height.toDouble(),
        ),
      );
  if (source.isEmpty) return;

  canvas.save();
  canvas.translate(centerX, centerY);
  canvas.translate(
    incoming ? -driftX * 0.78 * (1 - travel) : driftX * travel,
    incoming ? -driftY * 0.65 * (1 - travel) : driftY * travel,
  );
  canvas.rotate(incoming ? -rotation * 0.8 * (1 - travel) : rotation * travel);
  canvas.drawImageRect(
    snapshot.image,
    source,
    Rect.fromLTWH(
      -cellWidth / 2,
      -cellHeight / 2,
      cellWidth + 0.5,
      cellHeight + 0.5,
    ),
    Paint()
      ..isAntiAlias = true
      ..filterQuality = FilterQuality.low
      ..color = Colors.white.withValues(alpha: incoming ? fade : 1 - fade),
  );
  canvas.restore();
}

QuickjsUiSnapshot? _resolveSnapshotSlot(
  Object? rawSlot,
  QuickjsUiSnapshotRegistry registry,
  Map<String, String> resources,
) {
  if (rawSlot is! String) return null;
  final id = resources[rawSlot];
  return id == null ? null : registry.resolve(id);
}

double _particleHash(int value) {
  final raw = math.sin(value * 91.3458) * 47453.5453;
  return raw - raw.floorToDouble();
}

double _particleProgress(
  double elapsedMs,
  double delayMs,
  double durationMs, {
  required bool easeIn,
}) {
  final linear = ((elapsedMs - delayMs) / durationMs).clamp(0.0, 1.0);
  return easeIn ? linear * linear : 1 - math.pow(1 - linear, 2).toDouble();
}

double _rawFiniteNumber(Object? value, {double? fallback}) {
  if (value == null && fallback != null) return fallback;
  if (value is! num || !value.isFinite) {
    throw const FormatException(
      'quickjs_ui Canvas snapshotParticleGrid requires finite numbers',
    );
  }
  return value.toDouble();
}
