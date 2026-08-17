// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

import 'quickjs_ui_svg_compat.dart';

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
  return Image.file(
    File(jsUiFilePath(location)),
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
  return SvgPicture(
    _JsUiSvgFileLoader(File(jsUiFilePath(location))),
    width: width,
    height: height,
    fit: fit,
    colorFilter: colorFilter,
    semanticsLabel: semanticsLabel,
    excludeFromSemantics: excludeFromSemantics,
    renderingStrategy: renderingStrategy,
  );
}

final class _JsUiSvgFileLoader extends SvgFileLoader {
  const _JsUiSvgFileLoader(super.file);

  @override
  String provideSvg(void message) =>
      normalizeJsUiSvg(super.provideSvg(message));
}

String jsUiFilePath(String location) {
  final uri = Uri.tryParse(location);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  return location;
}
