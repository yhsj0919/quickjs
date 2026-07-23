part of 'quickjs_ui_canvas_component.dart';

void _drawSnapshotImage(
  Canvas canvas,
  Map<String, Object?> command,
  _CanvasClock clock,
  QuickjsUiSnapshotRegistry registry,
  Map<String, String> resources,
) {
  final slot = command['imageSlot'];
  final id =
      command['snapshotId'] ??
      command['image'] ??
      (slot is String ? resources[slot] : null);
  if (id == null && slot is String) return;
  if (id is! String) {
    throw const FormatException(
      'quickjs_ui Canvas image requires snapshotId or imageSlot',
    );
  }
  final snapshot = registry.resolve(id);
  if (snapshot == null) return;

  final sourceX = _optionalNumber(command['sx'], clock) ?? 0;
  final sourceY = _optionalNumber(command['sy'], clock) ?? 0;
  final sourceWidth =
      _optionalNumber(command['sWidth'], clock) ?? snapshot.width;
  final sourceHeight =
      _optionalNumber(command['sHeight'], clock) ?? snapshot.height;
  final destinationWidth =
      _optionalNumber(command['dWidth'], clock) ?? sourceWidth;
  final destinationHeight =
      _optionalNumber(command['dHeight'], clock) ?? sourceHeight;
  if (destinationWidth <= 0 || destinationHeight <= 0) return;

  final ratio = snapshot.pixelRatio;
  final source =
      Rect.fromLTWH(
        sourceX * ratio,
        sourceY * ratio,
        sourceWidth * ratio,
        sourceHeight * ratio,
      ).intersect(
        Rect.fromLTWH(
          0,
          0,
          snapshot.image.width.toDouble(),
          snapshot.image.height.toDouble(),
        ),
      );
  if (source.isEmpty) return;

  final opacity = (_optionalNumber(command['globalAlpha'], clock) ?? 1.0).clamp(
    0.0,
    1.0,
  );
  canvas.drawImageRect(
    snapshot.image,
    source,
    Rect.fromLTWH(
      _number(command['dx'], 'dx', clock),
      _number(command['dy'], 'dy', clock),
      destinationWidth,
      destinationHeight,
    ),
    Paint()
      ..isAntiAlias = command['antiAlias'] != false
      ..filterQuality = switch (command['filterQuality']) {
        'none' => FilterQuality.none,
        'medium' => FilterQuality.medium,
        'high' => FilterQuality.high,
        _ => FilterQuality.low,
      }
      ..color = Colors.white.withValues(alpha: opacity)
      ..blendMode = _blendMode(command['blendMode']),
  );
}
