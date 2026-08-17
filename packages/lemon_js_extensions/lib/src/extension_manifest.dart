import 'dart:convert';

/// Current schema version accepted by [JsExtensionManifest].
const int jsExtensionManifestSchemaVersion = 2;

/// 描述一个统一扩展安装单元的清单。
final class JsExtensionManifest {
  /// Creates and validates an extension manifest.
  JsExtensionManifest({
    required this.id,
    required this.name,
    this.description = '',
    required this.version,
    this.versionCode = 0,
    required this.compatibilityCode,
    this.schemaVersion = jsExtensionManifestSchemaVersion,
    this.service,
    this.ui,
    this.entry,
    this.icon,
    this.homepage,
    this.updateUrl,
    this.downloadUrl,
    Map<String, JsExtensionFlowManifest> flows =
        const <String, JsExtensionFlowManifest>{},
    this.capabilities = const JsExtensionCapabilityManifest(),
    this.storageVersion = 0,
    List<String> resources = const <String>[],
    List<String> permissions = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : flows = Map<String, JsExtensionFlowManifest>.unmodifiable(flows),
       resources = List<String>.unmodifiable(resources),
       permissions = List<String>.unmodifiable(permissions),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    _validate();
  }

  /// Parses a manifest from its JSON [source].
  factory JsExtensionManifest.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('JS extension manifest must be an object');
    }
    return JsExtensionManifest.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  /// Parses a manifest from a decoded JSON object.
  factory JsExtensionManifest.fromMap(Map<String, Object?> map) {
    final schemaVersion = _int(map['schemaVersion'], 'schemaVersion');
    if (schemaVersion != jsExtensionManifestSchemaVersion) {
      throw FormatException(
        'Unsupported JS extension manifest schemaVersion: $schemaVersion',
      );
    }
    final service = map['service'];
    final ui = map['ui'];
    return JsExtensionManifest(
      schemaVersion: schemaVersion,
      id: _string(map['id'], 'id'),
      name: _string(map['name'], 'name'),
      description: _string(map['description'], 'description'),
      version: _string(map['version'], 'version'),
      versionCode: _int(map['versionCode'], 'versionCode'),
      compatibilityCode: _string(map['compatibilityCode'], 'compatibilityCode'),
      service: service == null
          ? null
          : JsExtensionServiceManifest.fromMap(_map(service, 'service')),
      ui: ui == null ? null : JsExtensionUiManifest.fromMap(_map(ui, 'ui')),
      entry: map['entry'] == null
          ? null
          : JsExtensionEntry.fromMap(_map(map['entry'], 'entry')),
      icon: _optionalString(map['icon'], 'icon'),
      homepage: _optionalHttpsUri(map['homepage'], 'homepage'),
      updateUrl: _optionalHttpsUri(map['updateUrl'], 'updateUrl'),
      downloadUrl: _optionalHttpsUri(map['downloadUrl'], 'downloadUrl'),
      flows: _objectMap(map['flows'], 'flows').map(
        (key, value) => MapEntry(
          key,
          JsExtensionFlowManifest.fromMap(_map(value, 'flows.$key')),
        ),
      ),
      capabilities: JsExtensionCapabilityManifest.fromMap(
        _objectMap(map['capabilities'], 'capabilities'),
      ),
      storageVersion: map['storageVersion'] == null
          ? 0
          : _int(map['storageVersion'], 'storageVersion'),
      resources: _stringList(map['resources'], 'resources'),
      permissions: _stringList(map['permissions'], 'permissions'),
      metadata: _objectMap(map['metadata'], 'metadata'),
    );
  }

  /// Manifest schema version.
  final int schemaVersion;

  /// Stable extension identifier.
  final String id;

  /// User-visible extension name.
  final String name;

  /// User-visible extension description.
  final String description;

  /// User-visible version string.
  final String version;

  /// Monotonic version used for update ordering.
  final int versionCode;

  /// Host compatibility contract identifier.
  final String compatibilityCode;

  /// Optional Core service declaration.
  final JsExtensionServiceManifest? service;

  /// Optional JSUI declaration.
  final JsExtensionUiManifest? ui;

  /// Default UI entry for launching the extension.
  final JsExtensionEntry? entry;

  /// Package-relative icon path or absolute HTTPS URL.
  final String? icon;

  /// Extension homepage, when declared.
  final Uri? homepage;

  /// Endpoint used to check for updates.
  final Uri? updateUrl;

  /// Endpoint used to download the extension package.
  final Uri? downloadUrl;

  /// Named business flows exposed by the extension.
  final Map<String, JsExtensionFlowManifest> flows;

  /// Required and optional host capabilities.
  final JsExtensionCapabilityManifest capabilities;

  /// Version of the extension's persistent storage schema.
  final int storageVersion;

  /// Additional package-relative resources.
  final List<String> resources;

  /// Permissions requested by the extension.
  final List<String> permissions;

  /// Extension-defined manifest metadata.
  final Map<String, Object?> metadata;

  /// Converts this manifest to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'schemaVersion': schemaVersion,
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'versionCode': versionCode,
    'compatibilityCode': compatibilityCode,
    if (icon != null) 'icon': icon,
    if (homepage != null) 'homepage': homepage.toString(),
    if (updateUrl != null) 'updateUrl': updateUrl.toString(),
    if (downloadUrl != null) 'downloadUrl': downloadUrl.toString(),
    if (service != null) 'service': service!.toMap(),
    if (ui != null) 'ui': ui!.toMap(),
    if (entry != null) 'entry': entry!.toMap(),
    if (flows.isNotEmpty)
      'flows': <String, Object?>{
        for (final entry in flows.entries) entry.key: entry.value.toMap(),
      },
    if (capabilities.isNotEmpty) 'capabilities': capabilities.toMap(),
    if (storageVersion != 0) 'storageVersion': storageVersion,
    if (resources.isNotEmpty) 'resources': resources,
    if (permissions.isNotEmpty) 'permissions': permissions,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };

  /// Encodes this manifest as JSON.
  String toJson() => jsonEncode(toMap());

  void _validate() {
    _requireIdentifier(id, 'id');
    if (name.trim().isEmpty) {
      throw const FormatException('JS extension name must not be empty');
    }
    if (version.trim().isEmpty) {
      throw const FormatException('JS extension version must not be empty');
    }
    if (versionCode < 0) {
      throw const FormatException(
        'JS extension versionCode must not be negative',
      );
    }
    if (storageVersion < 0) {
      throw const FormatException(
        'JS extension storageVersion must not be negative',
      );
    }
    _requireUnique(resources, 'resources');
    for (final resource in resources) {
      _requirePackagePath(resource, 'resources');
    }
    _requireIdentifier(compatibilityCode, 'compatibilityCode');
    if (service == null && ui == null) {
      throw const FormatException(
        'JS extension must declare service, ui, or both',
      );
    }
    final routes = ui?.routes ?? const <String, JsExtensionRoute>{};
    final defaultEntry = entry;
    if (defaultEntry != null) {
      _entryDisplay(defaultEntry.display);
    }
    if (defaultEntry != null && !routes.containsKey(defaultEntry.route)) {
      throw FormatException(
        'JS extension entry references missing route '
        '"${defaultEntry.route}"',
      );
    }
    if (ui != null && service == null && defaultEntry == null) {
      throw const FormatException(
        'JSUI-only extension must declare a default entry route',
      );
    }
    final iconValue = icon;
    if (iconValue != null) {
      final uri = Uri.tryParse(iconValue);
      if (uri != null && uri.hasScheme) {
        if (uri.scheme != 'https' || uri.host.isEmpty) {
          throw const FormatException(
            'JS extension network icon must use an absolute HTTPS URL',
          );
        }
      } else {
        _requirePackagePath(iconValue, 'icon');
      }
    }
    for (final entry in flows.entries) {
      _requireIdentifier(entry.key, 'flows key');
      if (!routes.containsKey(entry.value.route)) {
        throw FormatException(
          'JS extension flow "${entry.key}" references missing route '
          '"${entry.value.route}"',
        );
      }
    }
    _requireUnique(permissions, 'permissions');
  }
}

/// 插件对宿主可选能力及最低版本的声明。
final class JsExtensionCapabilityManifest {
  /// Creates a host-capability declaration.
  const JsExtensionCapabilityManifest({
    this.required = const <String, int>{},
    this.optional = const <String, int>{},
  });

  /// Parses a capability declaration from a decoded JSON object.
  factory JsExtensionCapabilityManifest.fromMap(Map<String, Object?> map) {
    Map<String, int> parseVersions(String field) => Map.unmodifiable(
      _objectMap(map[field], 'capabilities.$field').map((name, value) {
        _requireIdentifier(name, 'capabilities.$field key');
        final version = _int(value, 'capabilities.$field.$name');
        if (version < 1) {
          throw FormatException(
            'JS extension capability version must be positive: $name',
          );
        }
        return MapEntry(name, version);
      }),
    );

    final required = parseVersions('required');
    final optional = parseVersions('optional');
    final duplicated = required.keys.toSet().intersection(
      optional.keys.toSet(),
    );
    if (duplicated.isNotEmpty) {
      throw FormatException(
        'JS extension capabilities cannot be both required and optional: '
        '${duplicated.join(', ')}',
      );
    }
    return JsExtensionCapabilityManifest(
      required: required,
      optional: optional,
    );
  }

  /// Capabilities that must be available, mapped to minimum versions.
  final Map<String, int> required;

  /// Capabilities that may be used when available, mapped to minimum versions.
  final Map<String, int> optional;

  /// Whether any capability is declared.
  bool get isNotEmpty => required.isNotEmpty || optional.isNotEmpty;

  /// Converts this declaration to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    if (required.isNotEmpty) 'required': required,
    if (optional.isNotEmpty) 'optional': optional,
  };
}

/// UI-only 小程序或可视扩展的默认启动入口。
final class JsExtensionEntry {
  /// Creates a default UI entry.
  const JsExtensionEntry({required this.route, this.display = 'standalone'});

  /// Parses a default UI entry from a decoded JSON object.
  factory JsExtensionEntry.fromMap(Map<String, Object?> map) =>
      JsExtensionEntry(
        route: _string(map['route'], 'entry.route'),
        display: _entryDisplay(map['display']),
      );

  /// Route identifier to open.
  final String route;

  /// Presentation mode; currently only `standalone` is supported.
  final String display;

  /// Converts this entry to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'route': route,
    'display': display,
  };
}

String _entryDisplay(Object? value) {
  final display = _optionalString(value, 'entry.display') ?? 'standalone';
  if (display != 'standalone') {
    throw FormatException(
      'JS extension entry.display currently supports only "standalone"',
    );
  }
  return display;
}

/// Core 服务组件的清单。
final class JsExtensionServiceManifest {
  /// Creates and validates a Core service declaration.
  JsExtensionServiceManifest({
    required this.entry,
    required this.contract,
    List<String> publicExports = const <String>[],
    List<String> uiExports = const <String>[],
    this.storageMigrationExport,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : publicExports = List<String>.unmodifiable(publicExports),
       uiExports = List<String>.unmodifiable(uiExports),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    if (entry.trim().isEmpty || contract.trim().isEmpty) {
      throw const FormatException(
        'JS extension service entry and contract must not be empty',
      );
    }
    _requirePackagePath(entry, 'service.entry');
    _requireUnique(publicExports, 'service.publicExports');
    _requireUnique(uiExports, 'service.uiExports');
    final overlap = publicExports.toSet().intersection(uiExports.toSet());
    if (overlap.isNotEmpty) {
      throw FormatException(
        'JS extension service exports cannot be both public and UI-only: '
        '${overlap.join(', ')}',
      );
    }
    final migrationExport = storageMigrationExport;
    if (migrationExport != null) {
      _requireIdentifier(migrationExport, 'service.storageMigrationExport');
      if (publicExports.contains(migrationExport) ||
          uiExports.contains(migrationExport)) {
        throw const FormatException(
          'JS extension storage migration export must be internal',
        );
      }
    }
  }

  /// Parses a Core service declaration from a decoded JSON object.
  factory JsExtensionServiceManifest.fromMap(Map<String, Object?> map) =>
      JsExtensionServiceManifest(
        entry: _string(map['entry'], 'service.entry'),
        contract: _string(map['contract'], 'service.contract'),
        publicExports: _stringList(
          map['publicExports'],
          'service.publicExports',
        ),
        uiExports: _stringList(map['uiExports'], 'service.uiExports'),
        storageMigrationExport: _optionalString(
          map['storageMigrationExport'],
          'service.storageMigrationExport',
        ),
        metadata: _objectMap(map['metadata'], 'service.metadata'),
      );

  /// Package-relative JavaScript module entry.
  final String entry;

  /// Service contract implemented by this extension.
  final String contract;

  /// Methods callable by the host application.
  final List<String> publicExports;

  /// Methods callable only by this extension's UI.
  final List<String> uiExports;

  /// Internal method that migrates persistent storage.
  final String? storageMigrationExport;

  /// Service-defined metadata.
  final Map<String, Object?> metadata;

  /// Converts this service declaration to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'entry': entry,
    'contract': contract,
    if (publicExports.isNotEmpty) 'publicExports': publicExports,
    if (uiExports.isNotEmpty) 'uiExports': uiExports,
    if (storageMigrationExport != null)
      'storageMigrationExport': storageMigrationExport,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// JSUI 组件的清单。
final class JsExtensionUiManifest {
  /// Creates and validates a JSUI declaration.
  JsExtensionUiManifest({
    required Map<String, JsExtensionRoute> routes,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : routes = Map<String, JsExtensionRoute>.unmodifiable(routes),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    if (routes.isEmpty) {
      throw const FormatException('JS extension ui.routes must not be empty');
    }
    for (final entry in routes.entries) {
      _requireIdentifier(entry.key, 'ui.routes key');
      if (entry.value.entry.trim().isEmpty) {
        throw FormatException(
          'JS extension ui route "${entry.key}" entry is empty',
        );
      }
      _requirePackagePath(entry.value.entry, 'ui.routes.${entry.key}.entry');
      _requireUnique(
        entry.value.permissions,
        'ui.routes.${entry.key}.permissions',
      );
    }
  }

  /// Parses a JSUI declaration from a decoded JSON object.
  factory JsExtensionUiManifest.fromMap(Map<String, Object?> map) =>
      JsExtensionUiManifest(
        routes: _objectMap(map['routes'], 'ui.routes').map(
          (key, value) => MapEntry(
            key,
            JsExtensionRoute.fromMap(_map(value, 'ui.routes.$key')),
          ),
        ),
        metadata: _objectMap(map['metadata'], 'ui.metadata'),
      );

  /// Named routes provided by the extension.
  final Map<String, JsExtensionRoute> routes;

  /// UI-defined metadata.
  final Map<String, Object?> metadata;

  /// Converts this UI declaration to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'routes': <String, Object?>{
      for (final entry in routes.entries) entry.key: entry.value.toMap(),
    },
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// 一个由扩展提供的 JSUI 页面入口。
final class JsExtensionRoute {
  /// Creates a JSUI route declaration.
  const JsExtensionRoute({
    required this.entry,
    this.title,
    this.permissions = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  /// Parses a route from a decoded JSON object.
  factory JsExtensionRoute.fromMap(Map<String, Object?> map) {
    final entry = _string(map['entry'], 'route.entry');
    if (entry.trim().isEmpty) {
      throw const FormatException('JS extension route entry is empty');
    }
    return JsExtensionRoute(
      entry: entry,
      title: _optionalString(map['title'], 'route.title'),
      permissions: List<String>.unmodifiable(
        _stringList(map['permissions'], 'route.permissions'),
      ),
      metadata: Map<String, Object?>.unmodifiable(
        _objectMap(map['metadata'], 'route.metadata'),
      ),
    );
  }

  /// Package-relative JSUI module entry.
  final String entry;

  /// Optional user-visible route title.
  final String? title;

  /// Permissions required to open this route.
  final List<String> permissions;

  /// Route-defined metadata.
  final Map<String, Object?> metadata;

  /// Converts this route to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'entry': entry,
    if (title != null) 'title': title,
    if (permissions.isNotEmpty) 'permissions': permissions,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// 将业务交互名称映射到 JSUI 路由的清单项。
final class JsExtensionFlowManifest {
  /// Creates a named business-flow declaration.
  const JsExtensionFlowManifest({
    required this.route,
    this.metadata = const <String, Object?>{},
  });

  /// Parses a flow from a decoded JSON object.
  factory JsExtensionFlowManifest.fromMap(Map<String, Object?> map) =>
      JsExtensionFlowManifest(
        route: _string(map['route'], 'flow.route'),
        metadata: Map<String, Object?>.unmodifiable(
          _objectMap(map['metadata'], 'flow.metadata'),
        ),
      );

  /// JSUI route used to perform this flow.
  final String route;

  /// Flow-defined metadata.
  final Map<String, Object?> metadata;

  /// Converts this flow to a JSON-compatible map.
  Map<String, Object?> toMap() => <String, Object?>{
    'route': route,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _string(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('JS extension $name must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  return _string(value, name);
}

int _int(Object? value, String name) {
  if (value is! int) {
    throw FormatException('JS extension $name must be an integer');
  }
  return value;
}

Uri? _optionalHttpsUri(Object? value, String name) {
  final source = _optionalString(value, name);
  if (source == null) return null;
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException('JS extension $name must be an absolute HTTPS URL');
  }
  return uri;
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('JS extension $name must be an object');
  }
  return value.map((key, item) => MapEntry('$key', item));
}

Map<String, Object?> _objectMap(Object? value, String name) {
  if (value == null) return const <String, Object?>{};
  return _map(value, name);
}

List<String> _stringList(Object? value, String name) {
  if (value == null) return const <String>[];
  if (value is! List || value.any((item) => item is! String)) {
    throw FormatException('JS extension $name must be a string list');
  }
  return value.cast<String>();
}

void _requireIdentifier(String value, String name) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(value)) {
    throw FormatException('JS extension $name is invalid: $value');
  }
}

void _requireUnique(List<String> values, String name) {
  if (values.any((value) => value.trim().isEmpty)) {
    throw FormatException('JS extension $name contains an empty value');
  }
  if (values.toSet().length != values.length) {
    throw FormatException('JS extension $name contains duplicates');
  }
}

void _requirePackagePath(String value, String name) {
  if (value.startsWith('/') ||
      value.contains(r'\') ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw FormatException(
      'JS extension $name must be a normalized package-relative path: '
      '$value',
    );
  }
}
