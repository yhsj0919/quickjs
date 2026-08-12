import 'dart:convert';

const int quickjsExtensionManifestSchemaVersion = 2;

/// 描述一个统一扩展安装单元的清单。
final class QuickjsExtensionManifest {
  QuickjsExtensionManifest({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.versionCode,
    required this.compatibilityCode,
    this.schemaVersion = quickjsExtensionManifestSchemaVersion,
    this.service,
    this.ui,
    this.entry,
    this.icon,
    this.homepage,
    this.updateUrl,
    this.downloadUrl,
    Map<String, QuickjsExtensionFlowManifest> flows =
        const <String, QuickjsExtensionFlowManifest>{},
    this.capabilities = const QuickjsExtensionCapabilityManifest(),
    this.storageVersion = 0,
    List<String> resources = const <String>[],
    List<String> permissions = const <String>[],
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : flows = Map<String, QuickjsExtensionFlowManifest>.unmodifiable(flows),
       resources = List<String>.unmodifiable(resources),
       permissions = List<String>.unmodifiable(permissions),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    _validate();
  }

  factory QuickjsExtensionManifest.parse(String source) {
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException(
        'QuickJS extension manifest must be an object',
      );
    }
    return QuickjsExtensionManifest.fromMap(
      decoded.map((key, value) => MapEntry('$key', value)),
    );
  }

  factory QuickjsExtensionManifest.fromMap(Map<String, Object?> map) {
    final schemaVersion = _int(map['schemaVersion'], 'schemaVersion');
    if (schemaVersion != quickjsExtensionManifestSchemaVersion) {
      throw FormatException(
        'Unsupported QuickJS extension manifest schemaVersion: $schemaVersion',
      );
    }
    final service = map['service'];
    final ui = map['ui'];
    return QuickjsExtensionManifest(
      schemaVersion: schemaVersion,
      id: _string(map['id'], 'id'),
      name: _string(map['name'], 'name'),
      description: _string(map['description'], 'description'),
      version: _string(map['version'], 'version'),
      versionCode: _int(map['versionCode'], 'versionCode'),
      compatibilityCode: _string(map['compatibilityCode'], 'compatibilityCode'),
      service: service == null
          ? null
          : QuickjsServiceManifest.fromMap(_map(service, 'service')),
      ui: ui == null
          ? null
          : QuickjsUiExtensionManifest.fromMap(_map(ui, 'ui')),
      entry: map['entry'] == null
          ? null
          : QuickjsExtensionEntry.fromMap(_map(map['entry'], 'entry')),
      icon: _optionalString(map['icon'], 'icon'),
      homepage: _optionalHttpsUri(map['homepage'], 'homepage'),
      updateUrl: _optionalHttpsUri(map['updateUrl'], 'updateUrl'),
      downloadUrl: _optionalHttpsUri(map['downloadUrl'], 'downloadUrl'),
      flows: _objectMap(map['flows'], 'flows').map(
        (key, value) => MapEntry(
          key,
          QuickjsExtensionFlowManifest.fromMap(_map(value, 'flows.$key')),
        ),
      ),
      capabilities: QuickjsExtensionCapabilityManifest.fromMap(
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

  final int schemaVersion;
  final String id;
  final String name;
  final String description;
  final String version;
  final int versionCode;
  final String compatibilityCode;
  final QuickjsServiceManifest? service;
  final QuickjsUiExtensionManifest? ui;
  final QuickjsExtensionEntry? entry;
  final String? icon;
  final Uri? homepage;
  final Uri? updateUrl;
  final Uri? downloadUrl;
  final Map<String, QuickjsExtensionFlowManifest> flows;
  final QuickjsExtensionCapabilityManifest capabilities;
  final int storageVersion;
  final List<String> resources;
  final List<String> permissions;
  final Map<String, Object?> metadata;

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

  String toJson() => jsonEncode(toMap());

  void _validate() {
    _requireIdentifier(id, 'id');
    if (name.trim().isEmpty) {
      throw const FormatException('QuickJS extension name must not be empty');
    }
    if (version.trim().isEmpty) {
      throw const FormatException(
        'QuickJS extension version must not be empty',
      );
    }
    if (versionCode < 0) {
      throw const FormatException(
        'QuickJS extension versionCode must not be negative',
      );
    }
    if (storageVersion < 0) {
      throw const FormatException(
        'QuickJS extension storageVersion must not be negative',
      );
    }
    _requireUnique(resources, 'resources');
    for (final resource in resources) {
      _requirePackagePath(resource, 'resources');
    }
    _requireIdentifier(compatibilityCode, 'compatibilityCode');
    if (service == null && ui == null) {
      throw const FormatException(
        'QuickJS extension must declare service, ui, or both',
      );
    }
    final routes = ui?.routes ?? const <String, QuickjsExtensionRoute>{};
    final defaultEntry = entry;
    if (defaultEntry != null) {
      _entryDisplay(defaultEntry.display);
    }
    if (defaultEntry != null && !routes.containsKey(defaultEntry.route)) {
      throw FormatException(
        'QuickJS extension entry references missing route '
        '"${defaultEntry.route}"',
      );
    }
    if (ui != null && service == null && defaultEntry == null) {
      throw const FormatException(
        'QuickJS UI-only extension must declare a default entry route',
      );
    }
    final iconValue = icon;
    if (iconValue != null) {
      final uri = Uri.tryParse(iconValue);
      if (uri != null && uri.hasScheme) {
        if (uri.scheme != 'https' || uri.host.isEmpty) {
          throw const FormatException(
            'QuickJS extension network icon must use an absolute HTTPS URL',
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
          'QuickJS extension flow "${entry.key}" references missing route '
          '"${entry.value.route}"',
        );
      }
    }
    _requireUnique(permissions, 'permissions');
  }
}

/// 插件对宿主可选能力及最低版本的声明。
final class QuickjsExtensionCapabilityManifest {
  const QuickjsExtensionCapabilityManifest({
    this.required = const <String, int>{},
    this.optional = const <String, int>{},
  });

  factory QuickjsExtensionCapabilityManifest.fromMap(Map<String, Object?> map) {
    Map<String, int> parseVersions(String field) => Map.unmodifiable(
      _objectMap(map[field], 'capabilities.$field').map((name, value) {
        _requireIdentifier(name, 'capabilities.$field key');
        final version = _int(value, 'capabilities.$field.$name');
        if (version < 1) {
          throw FormatException(
            'QuickJS extension capability version must be positive: $name',
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
        'QuickJS extension capabilities cannot be both required and optional: '
        '${duplicated.join(', ')}',
      );
    }
    return QuickjsExtensionCapabilityManifest(
      required: required,
      optional: optional,
    );
  }

  final Map<String, int> required;
  final Map<String, int> optional;

  bool get isNotEmpty => required.isNotEmpty || optional.isNotEmpty;

  Map<String, Object?> toMap() => <String, Object?>{
    if (required.isNotEmpty) 'required': required,
    if (optional.isNotEmpty) 'optional': optional,
  };
}

/// UI-only 小程序或可视扩展的默认启动入口。
final class QuickjsExtensionEntry {
  const QuickjsExtensionEntry({
    required this.route,
    this.display = 'standalone',
  });

  factory QuickjsExtensionEntry.fromMap(Map<String, Object?> map) =>
      QuickjsExtensionEntry(
        route: _string(map['route'], 'entry.route'),
        display: _entryDisplay(map['display']),
      );

  final String route;
  final String display;

  Map<String, Object?> toMap() => <String, Object?>{
    'route': route,
    'display': display,
  };
}

String _entryDisplay(Object? value) {
  final display = _optionalString(value, 'entry.display') ?? 'standalone';
  if (display != 'standalone') {
    throw FormatException(
      'QuickJS extension entry.display currently supports only "standalone"',
    );
  }
  return display;
}

/// Core 服务组件的清单。
final class QuickjsServiceManifest {
  QuickjsServiceManifest({
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
        'QuickJS extension service entry and contract must not be empty',
      );
    }
    _requirePackagePath(entry, 'service.entry');
    _requireUnique(publicExports, 'service.publicExports');
    _requireUnique(uiExports, 'service.uiExports');
    final overlap = publicExports.toSet().intersection(uiExports.toSet());
    if (overlap.isNotEmpty) {
      throw FormatException(
        'QuickJS extension service exports cannot be both public and UI-only: '
        '${overlap.join(', ')}',
      );
    }
    final migrationExport = storageMigrationExport;
    if (migrationExport != null) {
      _requireIdentifier(migrationExport, 'service.storageMigrationExport');
      if (publicExports.contains(migrationExport) ||
          uiExports.contains(migrationExport)) {
        throw const FormatException(
          'QuickJS extension storage migration export must be internal',
        );
      }
    }
  }

  factory QuickjsServiceManifest.fromMap(Map<String, Object?> map) =>
      QuickjsServiceManifest(
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

  final String entry;
  final String contract;
  final List<String> publicExports;
  final List<String> uiExports;
  final String? storageMigrationExport;
  final Map<String, Object?> metadata;

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
final class QuickjsUiExtensionManifest {
  QuickjsUiExtensionManifest({
    required Map<String, QuickjsExtensionRoute> routes,
    Map<String, Object?> metadata = const <String, Object?>{},
  }) : routes = Map<String, QuickjsExtensionRoute>.unmodifiable(routes),
       metadata = Map<String, Object?>.unmodifiable(metadata) {
    if (routes.isEmpty) {
      throw const FormatException(
        'QuickJS extension ui.routes must not be empty',
      );
    }
    for (final entry in routes.entries) {
      _requireIdentifier(entry.key, 'ui.routes key');
      if (entry.value.entry.trim().isEmpty) {
        throw FormatException(
          'QuickJS extension ui route "${entry.key}" entry is empty',
        );
      }
      _requirePackagePath(entry.value.entry, 'ui.routes.${entry.key}.entry');
      _requireUnique(
        entry.value.permissions,
        'ui.routes.${entry.key}.permissions',
      );
    }
  }

  factory QuickjsUiExtensionManifest.fromMap(Map<String, Object?> map) =>
      QuickjsUiExtensionManifest(
        routes: _objectMap(map['routes'], 'ui.routes').map(
          (key, value) => MapEntry(
            key,
            QuickjsExtensionRoute.fromMap(_map(value, 'ui.routes.$key')),
          ),
        ),
        metadata: _objectMap(map['metadata'], 'ui.metadata'),
      );

  final Map<String, QuickjsExtensionRoute> routes;
  final Map<String, Object?> metadata;

  Map<String, Object?> toMap() => <String, Object?>{
    'routes': <String, Object?>{
      for (final entry in routes.entries) entry.key: entry.value.toMap(),
    },
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// 一个由扩展提供的 JSUI 页面入口。
final class QuickjsExtensionRoute {
  const QuickjsExtensionRoute({
    required this.entry,
    this.title,
    this.permissions = const <String>[],
    this.metadata = const <String, Object?>{},
  });

  factory QuickjsExtensionRoute.fromMap(Map<String, Object?> map) {
    final entry = _string(map['entry'], 'route.entry');
    if (entry.trim().isEmpty) {
      throw const FormatException('QuickJS extension route entry is empty');
    }
    return QuickjsExtensionRoute(
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

  final String entry;
  final String? title;
  final List<String> permissions;
  final Map<String, Object?> metadata;

  Map<String, Object?> toMap() => <String, Object?>{
    'entry': entry,
    if (title != null) 'title': title,
    if (permissions.isNotEmpty) 'permissions': permissions,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

/// 将业务交互名称映射到 JSUI 路由的清单项。
final class QuickjsExtensionFlowManifest {
  const QuickjsExtensionFlowManifest({
    required this.route,
    this.metadata = const <String, Object?>{},
  });

  factory QuickjsExtensionFlowManifest.fromMap(Map<String, Object?> map) =>
      QuickjsExtensionFlowManifest(
        route: _string(map['route'], 'flow.route'),
        metadata: Map<String, Object?>.unmodifiable(
          _objectMap(map['metadata'], 'flow.metadata'),
        ),
      );

  final String route;
  final Map<String, Object?> metadata;

  Map<String, Object?> toMap() => <String, Object?>{
    'route': route,
    if (metadata.isNotEmpty) 'metadata': metadata,
  };
}

String _string(Object? value, String name) {
  if (value is! String || value.trim().isEmpty) {
    throw FormatException('QuickJS extension $name must be a non-empty string');
  }
  return value;
}

String? _optionalString(Object? value, String name) {
  if (value == null) return null;
  return _string(value, name);
}

int _int(Object? value, String name) {
  if (value is! int) {
    throw FormatException('QuickJS extension $name must be an integer');
  }
  return value;
}

Uri? _optionalHttpsUri(Object? value, String name) {
  final source = _optionalString(value, name);
  if (source == null) return null;
  final uri = Uri.tryParse(source);
  if (uri == null || uri.scheme != 'https' || uri.host.isEmpty) {
    throw FormatException(
      'QuickJS extension $name must be an absolute HTTPS URL',
    );
  }
  return uri;
}

Map<String, Object?> _map(Object? value, String name) {
  if (value is! Map) {
    throw FormatException('QuickJS extension $name must be an object');
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
    throw FormatException('QuickJS extension $name must be a string list');
  }
  return value.cast<String>();
}

void _requireIdentifier(String value, String name) {
  if (!RegExp(r'^[a-zA-Z0-9][a-zA-Z0-9._-]*$').hasMatch(value)) {
    throw FormatException('QuickJS extension $name is invalid: $value');
  }
}

void _requireUnique(List<String> values, String name) {
  if (values.any((value) => value.trim().isEmpty)) {
    throw FormatException('QuickJS extension $name contains an empty value');
  }
  if (values.toSet().length != values.length) {
    throw FormatException('QuickJS extension $name contains duplicates');
  }
}

void _requirePackagePath(String value, String name) {
  if (value.startsWith('/') ||
      value.contains(r'\') ||
      value
          .split('/')
          .any((part) => part.isEmpty || part == '.' || part == '..')) {
    throw FormatException(
      'QuickJS extension $name must be a normalized package-relative path: '
      '$value',
    );
  }
}
