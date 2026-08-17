// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

({BoxDecoration? background, Decoration? foreground}) splitJsUiRoundedBorder(
  BoxDecoration? decoration,
) {
  final border = decoration?.border;
  if (decoration == null || border is! Border || border.isUniform) {
    return (background: decoration, foreground: null);
  }
  if (decoration.borderRadius == null && decoration.shape != BoxShape.circle) {
    return (background: decoration, foreground: null);
  }
  return (
    background: BoxDecoration(
      color: decoration.color,
      image: decoration.image,
      borderRadius: decoration.borderRadius,
      boxShadow: decoration.boxShadow,
      gradient: decoration.gradient,
      backgroundBlendMode: decoration.backgroundBlendMode,
      shape: decoration.shape,
    ),
    foreground: _NonUniformRoundedBorderDecoration(
      border: border,
      borderRadius: decoration.borderRadius,
      shape: decoration.shape,
    ),
  );
}

final class _NonUniformRoundedBorderDecoration extends Decoration {
  const _NonUniformRoundedBorderDecoration({
    required this.border,
    required this.borderRadius,
    required this.shape,
  });

  final Border border;
  final BorderRadiusGeometry? borderRadius;
  final BoxShape shape;

  @override
  EdgeInsetsGeometry get padding => border.dimensions;

  @override
  BoxPainter createBoxPainter([VoidCallback? onChanged]) =>
      _NonUniformRoundedBorderPainter(this);
}

final class _NonUniformRoundedBorderPainter extends BoxPainter {
  const _NonUniformRoundedBorderPainter(this.decoration);

  final _NonUniformRoundedBorderDecoration decoration;

  @override
  void paint(Canvas canvas, Offset offset, ImageConfiguration configuration) {
    final size = configuration.size;
    if (size == null || size.isEmpty) return;
    final rect = offset & size;
    canvas.save();
    if (decoration.shape == BoxShape.circle) {
      canvas.clipPath(Path()..addOval(rect));
    } else {
      final radius = decoration.borderRadius?.resolve(
        configuration.textDirection,
      );
      canvas.clipRRect((radius ?? BorderRadius.zero).toRRect(rect));
    }
    _paintSide(
      canvas,
      decoration.border.left,
      Rect.fromLTWH(
        rect.left,
        rect.top,
        decoration.border.left.width,
        rect.height,
      ),
    );
    _paintSide(
      canvas,
      decoration.border.top,
      Rect.fromLTWH(
        rect.left,
        rect.top,
        rect.width,
        decoration.border.top.width,
      ),
    );
    _paintSide(
      canvas,
      decoration.border.right,
      Rect.fromLTWH(
        rect.right - decoration.border.right.width,
        rect.top,
        decoration.border.right.width,
        rect.height,
      ),
    );
    _paintSide(
      canvas,
      decoration.border.bottom,
      Rect.fromLTWH(
        rect.left,
        rect.bottom - decoration.border.bottom.width,
        rect.width,
        decoration.border.bottom.width,
      ),
    );
    canvas.restore();
  }

  void _paintSide(Canvas canvas, BorderSide side, Rect rect) {
    if (side.style == BorderStyle.none || side.width <= 0) return;
    canvas.drawRect(rect, Paint()..color = side.color);
  }
}
