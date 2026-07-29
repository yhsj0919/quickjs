import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

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
  return Image.file(
    File(quickjsUiFilePath(location)),
    width: width,
    height: height,
    fit: fit,
    alignment: alignment,
    cacheWidth: cacheWidth,
    cacheHeight: cacheHeight,
    semanticLabel: semanticLabel,
    excludeFromSemantics: excludeFromSemantics,
    gaplessPlayback: gaplessPlayback,
    filterQuality: filterQuality,
    repeat: repeat,
    color: color,
    colorBlendMode: colorBlendMode,
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
  return SvgPicture.file(
    File(quickjsUiFilePath(location)),
    width: width,
    height: height,
    fit: fit,
    colorFilter: colorFilter,
    semanticsLabel: semanticsLabel,
    excludeFromSemantics: excludeFromSemantics,
  );
}

String quickjsUiFilePath(String location) {
  final uri = Uri.tryParse(location);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  return location;
}
