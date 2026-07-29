import 'dart:ui' as ui;

import 'package:flutter/material.dart';

Widget buildQuickjsUiFileImage(
  String location, {
  double? width,
  double? height,
  BoxFit? fit,
  AlignmentGeometry alignment = Alignment.center,
  int? cacheWidth,
  int? cacheHeight,
  String? semanticLabel,
  bool excludeFromSemantics = false,
  bool gaplessPlayback = false,
  FilterQuality filterQuality = FilterQuality.medium,
  ImageRepeat repeat = ImageRepeat.noRepeat,
  Color? color,
  BlendMode? colorBlendMode,
}) {
  throw UnsupportedError(
    'quickjs_ui file Image resources are not supported on this platform: '
    '$location',
  );
}

Widget buildQuickjsUiFileSvg(
  String location, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  ui.ColorFilter? colorFilter,
  String? semanticsLabel,
  bool excludeFromSemantics = false,
}) {
  throw UnsupportedError(
    'quickjs_ui file Svg resources are not supported on this platform: '
    '$location',
  );
}
