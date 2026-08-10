import 'dart:convert';

import 'package:archive/archive.dart';
import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';
import 'quickjs_plugin.dart';

/// Convenience loader for zipped JavaScript plugin packages.
///
/// A zip plugin package should contain `quickjs-plugin.json` or
/// `manifest.json`. The manifest supports the same contract fields as
/// [QuickjsPluginManifest]. JavaScript files under the manifest directory are
/// mapped into plugin modules using the manifest `id` as namespace.
///
/// Example zip layout:
///
/// ```text
/// manifest.json
/// main.js
/// modules/helper.js
/// ```
///
/// With `entry: "demo/main"`, `main.js` maps to `demo/main`, and
/// `modules/helper.js` maps to `demo/modules/helper.js`.
final class QuickjsZipPlugin {
  const QuickjsZipPlugin._();

  /// Loads a plugin zip from Flutter assets.
  static Future<QuickjsPlugin> asset({
    required String assetKey,
    AssetBundle? bundle,
    String? manifestPath,
  }) async {
    final data = await (bundle ?? rootBundle).load(assetKey);
    return QuickjsZipPlugin.bytes(
      data.buffer.asUint8List(data.offsetInBytes, data.lengthInBytes),
      manifestPath: manifestPath,
    );
  }

  /// Loads a plugin zip from in-memory bytes.
  static QuickjsPlugin bytes(Uint8List zipBytes, {String? manifestPath}) {
    final archive = ZipDecoder().decodeBytes(zipBytes);
    return archivePackage(archive, manifestPath: manifestPath);
  }

  /// Loads a plugin from an already decoded [Archive].
  static QuickjsPlugin archivePackage(Archive archive, {String? manifestPath}) {
    final files = _archiveFiles(archive);
    final manifestEntry = _findManifest(files, manifestPath);
    final manifestJson = utf8.decode(manifestEntry.value);
    final manifestValue = jsonDecode(manifestJson);
    if (manifestValue is! Map<String, Object?>) {
      throw const JsValueConversionException(
        'QuickJS zip plugin manifest must be a JSON object',
      );
    }
    final manifest = _manifestFromJson(manifestValue);
    final root = _dirname(manifestEntry.key);
    final moduleFiles = _moduleFileMap(
      files,
      root: root,
      manifestPath: manifestEntry.key,
      manifest: manifest,
      manifestJson: manifestValue,
    );
    return QuickjsPlugin(
      manifest: manifest,
      modules: <QuickjsPluginModule>[
        for (final entry in moduleFiles.entries)
          QuickjsPluginModule.bytes(specifier: entry.key, bytes: entry.value),
      ],
    );
  }

  static Map<String, Uint8List> _archiveFiles(Archive archive) {
    final files = <String, Uint8List>{};
    for (final file in archive.files) {
      if (!file.isFile) {
        continue;
      }
      final name = _normalizePath(file.name);
      if (name.isEmpty) {
        continue;
      }
      files[name] = file.content;
    }
    return files;
  }

  static MapEntry<String, Uint8List> _findManifest(
    Map<String, Uint8List> files,
    String? manifestPath,
  ) {
    if (manifestPath != null) {
      final normalized = _normalizePath(manifestPath);
      final bytes = files[normalized];
      if (bytes == null) {
        throw JsValueConversionException(
          'QuickJS zip plugin manifest is missing: $normalized',
        );
      }
      return MapEntry<String, Uint8List>(normalized, bytes);
    }

    final candidates = files.entries.where((entry) {
      final name = entry.key.split('/').last;
      return name == 'quickjs-plugin.json' || name == 'manifest.json';
    }).toList();
    if (candidates.isEmpty) {
      throw const JsValueConversionException(
        'QuickJS zip plugin must contain quickjs-plugin.json or manifest.json',
      );
    }
    candidates.sort((left, right) {
      final depth = left.key
          .split('/')
          .length
          .compareTo(right.key.split('/').length);
      return depth == 0 ? left.key.compareTo(right.key) : depth;
    });
    return candidates.first;
  }

  static QuickjsPluginManifest _manifestFromJson(Map<String, Object?> json) {
    return QuickjsPluginManifest(
      id: _requiredString(json, 'id'),
      version: _requiredString(json, 'version'),
      entry: _requiredString(json, 'entry'),
      exports: _stringList(json, 'exports', required: true),
      init: _optionalString(json, 'init'),
      dispose: _optionalString(json, 'dispose'),
      permissions: _stringList(json, 'permissions'),
      metadata: _objectMap(json, 'metadata'),
    );
  }

  static Map<String, Uint8List> _moduleFileMap(
    Map<String, Uint8List> files, {
    required String root,
    required String manifestPath,
    required QuickjsPluginManifest manifest,
    required Map<String, Object?> manifestJson,
  }) {
    final explicitFiles = manifestJson['files'];
    if (explicitFiles != null) {
      if (explicitFiles is! Map) {
        throw const JsValueConversionException(
          'QuickJS zip plugin manifest files must be an object',
        );
      }
      return <String, Uint8List>{
        for (final entry in explicitFiles.entries)
          _requireModuleSpecifier(entry.key, manifest): _requireZipFile(
            files,
            root,
            entry.value,
          ),
      };
    }

    final modules = <String, Uint8List>{};
    final entryTail = manifest.entry.substring(manifest.id.length + 1);
    for (final entry in files.entries) {
      if (entry.key == manifestPath) {
        continue;
      }
      if (!_isJavaScriptModule(entry.key)) {
        continue;
      }
      final relative = _relativeToRoot(entry.key, root);
      if (relative == null || relative.isEmpty) {
        continue;
      }
      final specifier =
          relative == '$entryTail.js' || relative == '$entryTail.mjs'
          ? manifest.entry
          : '${manifest.id}/$relative';
      modules[specifier] = entry.value;
    }
    if (modules.isEmpty) {
      throw const JsValueConversionException(
        'QuickJS zip plugin does not contain JavaScript modules',
      );
    }
    return modules;
  }

  static String _requireModuleSpecifier(
    Object? value,
    QuickjsPluginManifest manifest,
  ) {
    if (value is! String || value.isEmpty) {
      throw const JsValueConversionException(
        'QuickJS zip plugin files keys must be module specifiers',
      );
    }
    if (!value.startsWith('${manifest.id}/')) {
      throw JsValueConversionException(
        'QuickJS zip plugin file specifier must use namespace '
        '"${manifest.id}/": $value',
      );
    }
    return value;
  }

  static Uint8List _requireZipFile(
    Map<String, Uint8List> files,
    String root,
    Object? value,
  ) {
    if (value is! String || value.isEmpty) {
      throw const JsValueConversionException(
        'QuickJS zip plugin files values must be zip paths',
      );
    }
    final path = _normalizePath(root.isEmpty ? value : '$root/$value');
    final bytes = files[path];
    if (bytes == null) {
      throw JsValueConversionException(
        'QuickJS zip plugin module file is missing: $path',
      );
    }
    return bytes;
  }

  static String _requiredString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw JsValueConversionException(
      'QuickJS zip plugin manifest field must be a non-empty string: $key',
    );
  }

  static String? _optionalString(Map<String, Object?> json, String key) {
    final value = json[key];
    if (value == null) {
      return null;
    }
    if (value is String && value.isNotEmpty) {
      return value;
    }
    throw JsValueConversionException(
      'QuickJS zip plugin manifest field must be a non-empty string: $key',
    );
  }

  static List<String> _stringList(
    Map<String, Object?> json,
    String key, {
    bool required = false,
  }) {
    final value = json[key];
    if (value == null && !required) {
      return const <String>[];
    }
    if (value is List && value.every((item) => item is String)) {
      return List<String>.unmodifiable(value.cast<String>());
    }
    throw JsValueConversionException(
      'QuickJS zip plugin manifest field must be a string list: $key',
    );
  }

  static Map<String, Object?> _objectMap(
    Map<String, Object?> json,
    String key,
  ) {
    final value = json[key];
    if (value == null) {
      return const <String, Object?>{};
    }
    if (value is Map) {
      return Map<String, Object?>.unmodifiable(
        value.map((key, value) => MapEntry<String, Object?>('$key', value)),
      );
    }
    throw JsValueConversionException(
      'QuickJS zip plugin manifest field must be an object: $key',
    );
  }

  static bool _isJavaScriptModule(String path) {
    return path.endsWith('.js') || path.endsWith('.mjs');
  }

  static String? _relativeToRoot(String path, String root) {
    if (root.isEmpty) {
      return path;
    }
    final prefix = '$root/';
    if (!path.startsWith(prefix)) {
      return null;
    }
    return path.substring(prefix.length);
  }

  static String _dirname(String path) {
    final slash = path.lastIndexOf('/');
    return slash < 0 ? '' : path.substring(0, slash);
  }

  static String _normalizePath(String path) {
    final parts = <String>[];
    for (final part in path.replaceAll('\\', '/').split('/')) {
      if (part.isEmpty || part == '.') {
        continue;
      }
      if (part == '..') {
        throw JsValueConversionException(
          'QuickJS zip plugin path must not contain ..: $path',
        );
      }
      parts.add(part);
    }
    return parts.join('/');
  }
}
