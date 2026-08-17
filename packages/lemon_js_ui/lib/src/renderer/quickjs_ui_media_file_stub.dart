// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

Widget buildJsUiFileImage(
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

Widget buildJsUiFileSvg(
  String location, {
  double? width,
  double? height,
  BoxFit fit = BoxFit.contain,
  ui.ColorFilter? colorFilter,
  String? semanticsLabel,
  bool excludeFromSemantics = false,
  RenderingStrategy renderingStrategy = RenderingStrategy.picture,
}) {
  throw UnsupportedError(
    'quickjs_ui file Svg resources are not supported on this platform: '
    '$location',
  );
}
