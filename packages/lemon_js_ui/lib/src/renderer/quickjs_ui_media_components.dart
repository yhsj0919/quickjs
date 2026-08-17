// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:vector_graphics/vector_graphics_compat.dart'
    show RenderingStrategy;

import '../resource/quickjs_ui_resource.dart';
import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_media_file.dart';
import 'quickjs_ui_svg_compat.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiMediaComponentBuilders =
    <String, JsUiComponentBuilder>{'Image': _buildImage, 'Svg': _buildSvg};

Widget _buildImage(JsUiRenderContext context, JsUiNode node) {
  _configureMediaCaches();
  final resource = context.resource(_resourceSource(node), name: 'Image src');
  final width = JsUiProps.doubleValue(node.props['width']);
  final height = JsUiProps.doubleValue(node.props['height']);
  final fit = JsUiProps.boxFit(node.props['fit']);
  final alignment =
      JsUiProps.alignment(node.props['alignment']) ?? Alignment.center;
  final cacheWidth = JsUiProps.intValue(node.props['cacheWidth']);
  final cacheHeight = JsUiProps.intValue(node.props['cacheHeight']);
  final semanticLabel = _semanticLabel(node);
  final excludeFromSemantics = _excludeFromSemantics(node);
  final gaplessPlayback =
      JsUiProps.boolValue(node.props['gaplessPlayback']) ?? false;
  final filterQuality = _filterQuality(node.props['filterQuality']);
  final repeat = _imageRepeat(node.props['repeat']);
  final color = context.color(node.props['color']);
  final colorBlendMode = _imageBlendMode(node.props['blendMode']);
  final image = switch (resource.kind) {
    JsUiResourceKind.asset => Image.asset(
      resource.uri,
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
    ),
    JsUiResourceKind.file => buildJsUiFileImage(
      resource.uri,
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
    ),
    JsUiResourceKind.network => Image.network(
      resource.uri,
      headers: resource.headers.isEmpty ? null : resource.headers,
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
      errorBuilder: (_, _, _) {
        return SizedBox(width: width, height: height);
      },
    ),
    JsUiResourceKind.data => Image.memory(
      _dataUriBytes(resource.uri),
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
    ),
    JsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Image does not support custom resource: ${resource.uri}',
    ),
  };
  return withJsUiGestures(context, node, image);
}

ImageRepeat _imageRepeat(Object? value) => switch (value) {
  null || 'noRepeat' => ImageRepeat.noRepeat,
  'repeat' => ImageRepeat.repeat,
  'repeatX' => ImageRepeat.repeatX,
  'repeatY' => ImageRepeat.repeatY,
  _ => throw const FormatException('Unknown quickjs_ui Image repeat'),
};

BlendMode? _imageBlendMode(Object? value) => switch (value) {
  null => null,
  'srcIn' => BlendMode.srcIn,
  'srcOver' => BlendMode.srcOver,
  'multiply' => BlendMode.multiply,
  'screen' => BlendMode.screen,
  'overlay' => BlendMode.overlay,
  'darken' => BlendMode.darken,
  'lighten' => BlendMode.lighten,
  _ => throw const FormatException('Unknown quickjs_ui Image blendMode'),
};

Widget _buildSvg(JsUiRenderContext context, JsUiNode node) {
  _configureMediaCaches();
  final width = JsUiProps.doubleValue(node.props['width']);
  final height = JsUiProps.doubleValue(node.props['height']);
  final fit = JsUiProps.boxFit(node.props['fit']) ?? BoxFit.contain;
  final semanticLabel = _semanticLabel(node);
  final excludeFromSemantics = _excludeFromSemantics(node);
  final renderingStrategy = _svgRenderingStrategy(
    node.props['renderingStrategy'],
    width: width,
    height: height,
  );
  final color = context.color(node.props['color']);
  final colorFilter = color == null
      ? null
      : ui.ColorFilter.mode(color, ui.BlendMode.srcIn);
  final rawSvg = JsUiProps.string(
    node.props['data'] ?? node.props['string'] ?? node.props['svg'],
  );
  if (rawSvg != null && rawSvg.trimLeft().startsWith('<svg')) {
    return withJsUiGestures(
      context,
      node,
      SvgPicture(
        JsUiSvgStringLoader(rawSvg),
        width: width,
        height: height,
        fit: fit,
        colorFilter: colorFilter,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: excludeFromSemantics,
        renderingStrategy: renderingStrategy,
      ),
    );
  }

  final resource = context.resource(_resourceSource(node), name: 'Svg src');
  final svg = switch (resource.kind) {
    JsUiResourceKind.asset => SvgPicture(
      JsUiSvgAssetLoader(resource.uri),
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      renderingStrategy: renderingStrategy,
    ),
    JsUiResourceKind.file => buildJsUiFileSvg(
      resource.uri,
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      renderingStrategy: renderingStrategy,
    ),
    JsUiResourceKind.network => SvgPicture(
      JsUiSvgNetworkLoader(
        resource.uri,
        headers: resource.headers.isEmpty ? null : resource.headers,
      ),
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      renderingStrategy: renderingStrategy,
    ),
    JsUiResourceKind.data => SvgPicture(
      JsUiSvgStringLoader(_dataUriText(resource.uri)),
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      renderingStrategy: renderingStrategy,
    ),
    JsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Svg does not support custom resource: ${resource.uri}',
    ),
  };
  return withJsUiGestures(context, node, svg);
}

RenderingStrategy _svgRenderingStrategy(
  Object? value, {
  required double? width,
  required double? height,
}) {
  return switch (JsUiProps.string(value, name: 'renderingStrategy')) {
    null =>
      width != null && height != null
          ? RenderingStrategy.raster
          : RenderingStrategy.picture,
    'raster' => RenderingStrategy.raster,
    'picture' => RenderingStrategy.picture,
    _ => throw const FormatException(
      'Unknown quickjs_ui Svg renderingStrategy',
    ),
  };
}

Object? _resourceSource(JsUiNode node) {
  return node.props['src'] ??
      node.props['source'] ??
      node.props['uri'] ??
      node.props['url'] ??
      node.props['path'];
}

String? _semanticLabel(JsUiNode node) {
  return JsUiProps.string(
    node.props['semanticLabel'] ??
        node.props['semanticsLabel'] ??
        node.props['label'],
  );
}

bool _excludeFromSemantics(JsUiNode node) {
  return JsUiProps.boolValue(node.props['excludeFromSemantics']) ?? false;
}

FilterQuality _filterQuality(Object? value) {
  return switch (JsUiProps.string(value, name: 'filterQuality')) {
    null => FilterQuality.medium,
    'none' => FilterQuality.none,
    'low' => FilterQuality.low,
    'medium' => FilterQuality.medium,
    'high' => FilterQuality.high,
    _ => throw const FormatException('Unknown quickjs_ui filterQuality'),
  };
}

const int _jsUiImageCacheMaximumSize = 128;
const int _jsUiImageCacheMaximumSizeBytes = 64 * 1024 * 1024;
const int _jsUiSvgCacheMaximumSize = 64;

bool _jsUiMediaCachesConfigured = false;

void _configureMediaCaches() {
  if (_jsUiMediaCachesConfigured) {
    return;
  }
  _jsUiMediaCachesConfigured = true;

  final imageCache = PaintingBinding.instance.imageCache;
  if (imageCache.maximumSize > _jsUiImageCacheMaximumSize) {
    imageCache.maximumSize = _jsUiImageCacheMaximumSize;
  }
  if (imageCache.maximumSizeBytes > _jsUiImageCacheMaximumSizeBytes) {
    imageCache.maximumSizeBytes = _jsUiImageCacheMaximumSizeBytes;
  }
  if (svg.cache.maximumSize > _jsUiSvgCacheMaximumSize) {
    svg.cache.maximumSize = _jsUiSvgCacheMaximumSize;
  }
}

Uint8List _dataUriBytes(String location) {
  final comma = location.indexOf(',');
  if (!location.startsWith('data:') || comma == -1) {
    throw const FormatException('quickjs_ui data resource is invalid');
  }
  final metadata = location.substring(5, comma);
  final data = location.substring(comma + 1);
  if (metadata.split(';').contains('base64')) {
    return base64Decode(data);
  }
  return Uint8List.fromList(utf8.encode(Uri.decodeComponent(data)));
}

String _dataUriText(String location) {
  return utf8.decode(_dataUriBytes(location));
}
