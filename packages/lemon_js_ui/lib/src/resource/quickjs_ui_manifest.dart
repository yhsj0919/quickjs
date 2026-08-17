import 'dart:convert';

import 'package:crypto/crypto.dart';

import 'quickjs_ui_resource.dart';
import 'quickjs_ui_resource_resolver.dart';

/// The package manifest schema version supported by this library.
const int jsUiManifestSchemaVersion = 1;

/// The required entry module for a package-root manifest.
const String jsUiPackageEntry = 'main.mjs';

/// The conventional package manifest file name.
const String jsUiPackageManifest = 'manifest.json';

/// Describes the modules, resources, routes, and permissions in a JSUI package.
final class JsUiManifest {
  /// Creates a package manifest from validated values.
  const JsUiManifest({
    this.schemaVersion = jsUiManifestSchemaVersion,
    required this.id,
    required this.version,
    required this.entry,
    required this.modules,
    this.name,
    this.resources = const <String, JsUiResourceReference>{},
    this.permissions = const <String>[],
    this.routes = const <String, JsUiRouteManifest>{},
    this.cache,
    this.metadata = const <String, Object?>{},
  });

  /// Manifest schema version.
  final int schemaVersion;

  /// Stable package identifier.
  final String id;

  /// Optional user-visible package name.
  final String? name;

  /// Application-defined package version.
  final String version;

  /// Normalized entry-module path.
  final String entry;

  /// Declared JavaScript modules keyed by normalized package path.
  final Map<String, JsUiModuleManifest> modules;

  /// Declared non-module resources.
  final Map<String, JsUiResourceReference> resources;

  /// Host permission names requested by the package.
  final List<String> permissions;

  /// Named routes exported by the package.
  final Map<String, JsUiRouteManifest> routes;

  /// Optional cache policy metadata.
  final JsUiCacheManifest? cache;

  /// Application-defined structured metadata.
  final Map<String, Object?> metadata;

  /// Parses and validates a JSON manifest [source].
  factory JsUiManifest.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'quickjs_ui package manifest must be an object',
      );
    }
    return JsUiManifest.fromMap(
      decoded.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }

  /// Parses and validates structured manifest data.
  factory JsUiManifest.fromMap(Map<String, Object?> manifest) {
    final schemaVersion = _intValue(
      manifest['schemaVersion'],
      'schemaVersion',
      defaultValue: jsUiManifestSchemaVersion,
    )!;
    if (schemaVersion != jsUiManifestSchemaVersion) {
      throw FormatException(
        'quickjs_ui package manifest schemaVersion is not supported: '
        '$schemaVersion',
      );
    }
    final entry = JsUiResourceResolver.normalizePath(
      _string(manifest['entry'], 'entry'),
    );
    final modules = _modules(manifest['modules']);
    if (!modules.containsKey(entry)) {
      throw FormatException(
        'quickjs_ui package manifest entry must be listed in modules: $entry',
      );
    }
    return JsUiManifest(
      schemaVersion: schemaVersion,
      id: _string(manifest['id'], 'id'),
      name: _optionalString(manifest['name'], 'name'),
      version: _string(manifest['version'], 'version'),
      entry: entry,
      modules: modules,
      resources: _resources(manifest['resources']),
      permissions: _stringList(manifest['permissions'], 'permissions'),
      routes: _routes(manifest['routes']),
      cache: manifest['cache'] == null
          ? null
          : JsUiCacheManifest.fromMap(_map(manifest['cache'], 'cache')),
      metadata: _metadata(manifest['metadata']),
    );
  }

  /// Validates the stricter entry requirements for a package root.
  void validatePackageRoot() {
    if (entry != jsUiPackageEntry) {
      throw FormatException(
        'quickjs_ui package manifest entry must be "$jsUiPackageEntry"',
      );
    }
    if (!modules.containsKey(jsUiPackageEntry)) {
      throw const FormatException(
        'quickjs_ui package modules must contain main.mjs',
      );
    }
  }

  /// Verifies that relative imports in [loadedModules] are declared modules.
  void validateImports(Map<String, String> loadedModules) {
    final declared = modules.keys.toSet();
    for (final module in loadedModules.entries) {
      for (final importPath in jsUiStaticImports(module.value)) {
        if (!jsUiIsRelativeImport(importPath)) {
          continue;
        }
        final imported = JsUiResourceResolver.normalizePath(
          importPath,
          from: module.key,
        );
        if (!declared.contains(imported)) {
          throw FormatException(
            'quickjs_ui package import is not declared in modules: $imported',
          );
        }
      }
    }
  }

  /// Serializes this manifest to JSON-compatible structured data.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'schemaVersion': schemaVersion,
      'id': id,
      if (name != null) 'name': name,
      'version': version,
      'entry': entry,
      'modules': <String, Object?>{
        for (final entry in modules.entries) entry.key: entry.value.toMap(),
      },
      if (resources.isNotEmpty)
        'resources': <String, Object?>{
          for (final entry in resources.entries) entry.key: entry.value.toMap(),
        },
      if (permissions.isNotEmpty) 'permissions': permissions,
      if (routes.isNotEmpty)
        'routes': <String, Object?>{
          for (final entry in routes.entries) entry.key: entry.value.toMap(),
        },
      if (cache != null) 'cache': cache!.toMap(),
      if (metadata.isNotEmpty) 'metadata': metadata,
    };
  }
}

/// Describes one JavaScript module declared by a package manifest.
final class JsUiModuleManifest {
  /// Creates a module declaration.
  const JsUiModuleManifest({
    required this.path,
    this.source,
    this.sha256,
    this.type = 'module',
  });

  /// Normalized logical module path used by imports.
  final String path;

  /// Optional resource path from which the module source is loaded.
  final String? source;

  /// Optional lowercase SHA-256 digest of the source text.
  final String? sha256;

  /// Module content type, normally `module`.
  final String type;

  /// The resource path used to load this module.
  String get loadPath => source ?? path;

  /// Verifies [content] against [sha256] when a digest is declared.
  void verifySource(String content) {
    if (sha256 == null) {
      return;
    }
    final actual = jsUiSha256Hex(content);
    if (actual != sha256) {
      throw FormatException(
        'quickjs_ui package module checksum mismatch: $path',
      );
    }
  }

  /// Serializes this module declaration.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      if (source != null) 'source': source,
      if (sha256 != null) 'sha256': sha256,
      if (type != 'module') 'type': type,
    };
  }
}

/// Declares a named navigation entry exported by a JSUI package.
final class JsUiRouteManifest {
  /// Creates a route declaration.
  const JsUiRouteManifest({
    required this.entry,
    this.title,
    this.initialProps = const <String, Object?>{},
  });

  /// Normalized module entry path for the route.
  final String entry;

  /// Optional user-visible route title.
  final String? title;

  /// Structured properties supplied when the route opens.
  final Map<String, Object?> initialProps;

  /// Parses a route declaration from structured manifest data.
  factory JsUiRouteManifest.fromMap(Map<String, Object?> map) {
    return JsUiRouteManifest(
      entry: JsUiResourceResolver.normalizePath(
        _string(map['entry'], 'routes.entry'),
      ),
      title: _optionalString(map['title'], 'routes.title'),
      initialProps: _metadata(map['initialProps']),
    );
  }

  /// Serializes this route declaration.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'entry': entry,
      if (title != null) 'title': title,
      if (initialProps.isNotEmpty) 'initialProps': initialProps,
    };
  }
}

/// Describes package resource caching preferences.
final class JsUiCacheManifest {
  /// Creates cache metadata.
  const JsUiCacheManifest({
    this.mode = 'versioned',
    this.immutable = false,
    this.maxAgeSeconds,
  });

  /// Application-defined cache strategy name.
  final String mode;

  /// Whether resources may be treated as immutable.
  final bool immutable;

  /// Optional maximum cache age in seconds.
  final int? maxAgeSeconds;

  /// Parses cache metadata from structured manifest data.
  factory JsUiCacheManifest.fromMap(Map<String, Object?> map) {
    return JsUiCacheManifest(
      mode: _optionalString(map['mode'], 'cache.mode') ?? 'versioned',
      immutable: _boolValue(map['immutable'], 'cache.immutable') ?? false,
      maxAgeSeconds: _intValue(map['maxAgeSeconds'], 'cache.maxAgeSeconds'),
    );
  }

  /// Serializes this cache metadata.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'mode': mode,
      if (immutable) 'immutable': immutable,
      if (maxAgeSeconds != null) 'maxAgeSeconds': maxAgeSeconds,
    };
  }
}

/// Returns the lowercase SHA-256 digest of UTF-8 [source].
String jsUiSha256Hex(String source) {
  return sha256.convert(utf8.encode(source)).toString();
}

/// Extracts static `import` and re-export specifiers from module [source].
///
/// Dynamic `import()` expressions are not included.
Iterable<String> jsUiStaticImports(String source) sync* {
  final patterns = <RegExp>[
    RegExp(
      r'''import\s+(?:[^'"]*?\s+from\s+)?["']([^"']+)["']''',
      multiLine: true,
    ),
    RegExp(r'''export\s+[^'"]*?\s+from\s+["']([^"']+)["']''', multiLine: true),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(source)) {
      final specifier = match.group(1);
      if (specifier != null && specifier.isNotEmpty) {
        yield specifier;
      }
    }
  }
}

/// Whether [specifier] is a `./` or `../` relative module import.
bool jsUiIsRelativeImport(String specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../');
}

Map<String, JsUiModuleManifest> _modules(Object? value) {
  if (value is List) {
    return Map<String, JsUiModuleManifest>.unmodifiable(<
      String,
      JsUiModuleManifest
    >{
      for (final item in value)
        JsUiResourceResolver.normalizePath(
          _string(item, 'modules[]'),
        ): JsUiModuleManifest(
          path: JsUiResourceResolver.normalizePath(_string(item, 'modules[]')),
        ),
    });
  }
  if (value is Map) {
    return Map<String, JsUiModuleManifest>.unmodifiable(
      value.map((key, moduleValue) {
        final path = JsUiResourceResolver.normalizePath('$key');
        if (moduleValue is String) {
          return MapEntry<String, JsUiModuleManifest>(
            path,
            JsUiModuleManifest(
              path: path,
              source: JsUiResourceResolver.normalizePath(moduleValue),
            ),
          );
        }
        final map = _map(moduleValue, 'modules.$key');
        return MapEntry<String, JsUiModuleManifest>(
          path,
          JsUiModuleManifest(
            path: path,
            source: map['source'] == null
                ? null
                : JsUiResourceResolver.normalizePath(
                    _string(map['source'], 'modules.$key.source'),
                  ),
            sha256: _sha256(map['sha256'] ?? map['checksum'], 'modules.$key'),
            type: _optionalString(map['type'], 'modules.$key.type') ?? 'module',
          ),
        );
      }),
    );
  }
  throw const FormatException(
    'quickjs_ui package manifest "modules" must be an array or object',
  );
}

Map<String, JsUiResourceReference> _resources(Object? value) {
  if (value == null) {
    return const <String, JsUiResourceReference>{};
  }
  if (value is List) {
    return Map<String, JsUiResourceReference>.unmodifiable(
      <String, JsUiResourceReference>{
        for (final item in value)
          _resourceKey(JsUiResourceReference.parse(item, name: 'resources[]')):
              JsUiResourceReference.parse(item, name: 'resources[]'),
      },
    );
  }
  if (value is Map) {
    return Map<String, JsUiResourceReference>.unmodifiable(
      value.map((key, resourceValue) {
        final resource = JsUiResourceReference.parse(
          resourceValue is Map
              ? <String, Object?>{
                  'uri': '$key',
                  ...resourceValue.map(
                    (key, value) => MapEntry<String, Object?>('$key', value),
                  ),
                }
              : resourceValue,
          name: 'resources.$key',
        );
        return MapEntry<String, JsUiResourceReference>('$key', resource);
      }),
    );
  }
  throw const FormatException(
    'quickjs_ui package manifest "resources" must be an array or object',
  );
}

Map<String, JsUiRouteManifest> _routes(Object? value) {
  if (value == null) {
    return const <String, JsUiRouteManifest>{};
  }
  final map = _map(value, 'routes');
  return Map<String, JsUiRouteManifest>.unmodifiable(
    map.map((key, value) {
      return MapEntry<String, JsUiRouteManifest>(
        key,
        JsUiRouteManifest.fromMap(_map(value, 'routes.$key')),
      );
    }),
  );
}

Map<String, Object?> _metadata(Object? value) {
  if (value == null) {
    return const <String, Object?>{};
  }
  return Map<String, Object?>.unmodifiable(_map(value, 'metadata'));
}

String _resourceKey(JsUiResourceReference resource) {
  if (resource.kind == JsUiResourceKind.asset) {
    return JsUiResourceResolver.normalizePath(resource.uri);
  }
  return resource.uri;
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is Map) {
    return value.map((key, value) => MapEntry<String, Object?>('$key', value));
  }
  throw FormatException(
    'quickjs_ui package manifest "$name" must be an object',
  );
}

List<String> _stringList(Object? value, String name) {
  if (value == null) {
    return const <String>[];
  }
  if (value is! List) {
    throw FormatException(
      'quickjs_ui package manifest "$name" must be an array',
    );
  }
  return List<String>.unmodifiable(
    value.map((item) => _string(item, '$name[]')),
  );
}

String _string(Object? value, String name) {
  if (value is String && value.isNotEmpty) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be a string');
}

String? _optionalString(Object? value, String name) {
  if (value == null) {
    return null;
  }
  return _string(value, name);
}

String? _sha256(Object? value, String name) {
  final text = _optionalString(value, '$name.sha256');
  if (text == null) {
    return null;
  }
  if (!RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(text)) {
    throw FormatException(
      'quickjs_ui package manifest "$name.sha256" must be 64 hex chars',
    );
  }
  return text.toLowerCase();
}

int? _intValue(Object? value, String name, {int? defaultValue}) {
  if (value == null) {
    return defaultValue;
  }
  if (value is int) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be an int');
}

bool? _boolValue(Object? value, String name) {
  if (value == null) {
    return null;
  }
  if (value is bool) {
    return value;
  }
  throw FormatException('quickjs_ui package manifest "$name" must be a bool');
}
