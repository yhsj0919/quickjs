import 'dart:io';

import 'package:flutter/services.dart';

/// Loads normalized JSUI text resources from a configured backing store.
final class JsUiResourceResolver {
  /// Creates a resolver backed by a Flutter [AssetBundle].
  JsUiResourceResolver.asset({AssetBundle? bundle, String basePath = ''})
    : this._(
        loadString: (path) => (bundle ?? rootBundle).loadString(
          _resolveResourcePath(basePath, path),
        ),
      );

  /// Creates a resolver backed by local files.
  ///
  /// Invocations throw [UnsupportedError] on platforms without file I/O.
  JsUiResourceResolver.file({String basePath = ''})
    : this._(
        loadString: (path) {
          final resolved = _resolveFilePath(basePath, path);
          return File(resolved).readAsString();
        },
      );

  /// Creates a resolver backed by an in-memory resource map.
  JsUiResourceResolver.memory(Map<String, String> resources)
    : this._(
        loadString: (path) async {
          final normalized = normalizePath(path);
          final source = resources[normalized] ?? resources[path];
          if (source == null) {
            throw StateError('quickjs_ui resource not found: $path');
          }
          return source;
        },
      );

  const JsUiResourceResolver._({required this.loadString});

  /// Loads one normalized resource [path] as text.
  final Future<String> Function(String path) loadString;

  /// Normalizes [path] relative to [from] and rejects root traversal.
  static String normalizePath(String path, {String from = ''}) {
    final normalizedPath = path.replaceAll('\\', '/');
    final baseParts = <String>[];
    if (from.isNotEmpty && !normalizedPath.startsWith('/')) {
      final normalizedFrom = from.replaceAll('\\', '/');
      baseParts.addAll(normalizedFrom.split('/'));
      if (baseParts.isNotEmpty && !normalizedFrom.endsWith('/')) {
        baseParts.removeLast();
      }
    }
    final parts = <String>[...baseParts];
    for (final part in normalizedPath.split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        if (parts.isEmpty) {
          throw FormatException('quickjs_ui path escapes bundle root: $path');
        }
        parts.removeLast();
        continue;
      }
      parts.add(part);
    }
    if (parts.isEmpty) {
      throw FormatException('quickjs_ui path must not be empty: $path');
    }
    return parts.join('/');
  }

  /// Creates a Lemon JS module specifier from [pluginId] and [path].
  static String moduleSpecifier(String pluginId, String path) {
    return '$pluginId/${normalizePath(path)}';
  }
}

String _resolveFilePath(String basePath, String path) {
  final normalized = JsUiResourceResolver.normalizePath(path);
  if (basePath.isEmpty) {
    return normalized;
  }
  final base = basePath.replaceAll('\\', '/');
  final root = base.endsWith('/') ? base.substring(0, base.length - 1) : base;
  return '$root/$normalized';
}

String _resolveResourcePath(String basePath, String path) {
  final normalized = JsUiResourceResolver.normalizePath(path);
  if (basePath.isEmpty) {
    return normalized;
  }
  final base = basePath.replaceAll('\\', '/');
  final index = base.lastIndexOf('/');
  if (index == -1) {
    return normalized;
  }
  return '${base.substring(0, index)}/$normalized';
}
