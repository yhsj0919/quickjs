import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../resource/quickjs_ui_resource.dart';
import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_media_file.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiMediaComponentBuilders =
    <String, QuickjsUiComponentBuilder>{'Image': _buildImage, 'Svg': _buildSvg};

Widget _buildImage(QuickjsUiRenderContext context, QuickjsUiNode node) {
  _configureMediaCaches();
  final resource = context.resource(_resourceSource(node), name: 'Image src');
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final fit = QuickjsUiProps.boxFit(node.props['fit']);
  final cacheWidth = QuickjsUiProps.intValue(node.props['cacheWidth']);
  final cacheHeight = QuickjsUiProps.intValue(node.props['cacheHeight']);
  final semanticLabel = _semanticLabel(node);
  final excludeFromSemantics = _excludeFromSemantics(node);
  final gaplessPlayback =
      QuickjsUiProps.boolValue(node.props['gaplessPlayback']) ?? false;
  final filterQuality = _filterQuality(node.props['filterQuality']);
  final image = switch (resource.kind) {
    QuickjsUiResourceKind.asset => Image.asset(
      resource.location,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
    ),
    QuickjsUiResourceKind.file => buildQuickjsUiFileImage(
      resource.location,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
    ),
    QuickjsUiResourceKind.network => Image.network(
      resource.location,
      headers: resource.headers.isEmpty ? null : resource.headers,
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
      errorBuilder: (_, _, _) {
        return SizedBox(width: width, height: height);
      },
    ),
    QuickjsUiResourceKind.data => Image.memory(
      _dataUriBytes(resource.location),
      width: width,
      height: height,
      fit: fit,
      cacheWidth: cacheWidth,
      cacheHeight: cacheHeight,
      semanticLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
      gaplessPlayback: gaplessPlayback,
      filterQuality: filterQuality,
    ),
    QuickjsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Image does not support custom resource: ${resource.location}',
    ),
  };
  return withQuickjsUiGestures(context, node, image);
}

Widget _buildSvg(QuickjsUiRenderContext context, QuickjsUiNode node) {
  _configureMediaCaches();
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final fit = QuickjsUiProps.boxFit(node.props['fit']) ?? BoxFit.contain;
  final semanticLabel = _semanticLabel(node);
  final excludeFromSemantics = _excludeFromSemantics(node);
  final color = context.color(node.props['color']);
  final colorFilter = color == null
      ? null
      : ui.ColorFilter.mode(color, ui.BlendMode.srcIn);
  final rawSvg = QuickjsUiProps.string(
    node.props['data'] ?? node.props['string'] ?? node.props['svg'],
  );
  if (rawSvg != null && rawSvg.trimLeft().startsWith('<svg')) {
    return withQuickjsUiGestures(
      context,
      node,
      SvgPicture.string(
        rawSvg,
        width: width,
        height: height,
        fit: fit,
        colorFilter: colorFilter,
        semanticsLabel: semanticLabel,
        excludeFromSemantics: excludeFromSemantics,
      ),
    );
  }

  final resource = context.resource(_resourceSource(node), name: 'Svg src');
  final svg = switch (resource.kind) {
    QuickjsUiResourceKind.asset => SvgPicture.asset(
      resource.location,
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    ),
    QuickjsUiResourceKind.file => buildQuickjsUiFileSvg(
      resource.location,
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    ),
    QuickjsUiResourceKind.network => SvgPicture.network(
      resource.location,
      headers: resource.headers.isEmpty ? null : resource.headers,
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    ),
    QuickjsUiResourceKind.data => SvgPicture.string(
      _dataUriText(resource.location),
      width: width,
      height: height,
      fit: fit,
      colorFilter: colorFilter,
      semanticsLabel: semanticLabel,
      excludeFromSemantics: excludeFromSemantics,
    ),
    QuickjsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Svg does not support custom resource: ${resource.location}',
    ),
  };
  return withQuickjsUiGestures(context, node, svg);
}

Object? _resourceSource(QuickjsUiNode node) {
  return node.props['src'] ??
      node.props['source'] ??
      node.props['uri'] ??
      node.props['url'] ??
      node.props['path'];
}

String? _semanticLabel(QuickjsUiNode node) {
  return QuickjsUiProps.string(
    node.props['semanticLabel'] ??
        node.props['semanticsLabel'] ??
        node.props['label'],
  );
}

bool _excludeFromSemantics(QuickjsUiNode node) {
  return QuickjsUiProps.boolValue(node.props['excludeFromSemantics']) ?? false;
}

FilterQuality _filterQuality(Object? value) {
  return switch (QuickjsUiProps.string(value, name: 'filterQuality')) {
    null => FilterQuality.medium,
    'none' => FilterQuality.none,
    'low' => FilterQuality.low,
    'medium' => FilterQuality.medium,
    'high' => FilterQuality.high,
    _ => throw const FormatException('Unknown quickjs_ui filterQuality'),
  };
}

const int _quickjsUiImageCacheMaximumSize = 128;
const int _quickjsUiImageCacheMaximumSizeBytes = 64 * 1024 * 1024;
const int _quickjsUiSvgCacheMaximumSize = 64;

bool _quickjsUiMediaCachesConfigured = false;

void _configureMediaCaches() {
  if (_quickjsUiMediaCachesConfigured) {
    return;
  }
  _quickjsUiMediaCachesConfigured = true;

  final imageCache = PaintingBinding.instance.imageCache;
  if (imageCache.maximumSize > _quickjsUiImageCacheMaximumSize) {
    imageCache.maximumSize = _quickjsUiImageCacheMaximumSize;
  }
  if (imageCache.maximumSizeBytes > _quickjsUiImageCacheMaximumSizeBytes) {
    imageCache.maximumSizeBytes = _quickjsUiImageCacheMaximumSizeBytes;
  }
  if (svg.cache.maximumSize > _quickjsUiSvgCacheMaximumSize) {
    svg.cache.maximumSize = _quickjsUiSvgCacheMaximumSize;
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
