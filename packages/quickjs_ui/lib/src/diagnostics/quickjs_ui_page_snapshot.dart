import 'package:quickjs/quickjs.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_diff_stats.dart';
import 'quickjs_ui_lifecycle_event.dart';

/// Serializable page snapshot for debugging and issue reproduction.
final class QuickjsUiPageSnapshot {
  const QuickjsUiPageSnapshot({
    required this.exportedAt,
    this.pageId,
    this.pageVersion,
    this.pageName,
    this.props = const <String, Object?>{},
    this.state,
    this.schema,
    this.manifest,
    this.lastAction,
    this.lifecycle = const <QuickjsUiLifecycleEvent>[],
    this.hostApis = const <String>[],
    this.resources = const <String>[],
    this.network = const <Map<String, Object?>>[],
    this.diff,
    this.error,
  });

  final DateTime exportedAt;
  final String? pageId;
  final String? pageVersion;
  final String? pageName;
  final Map<String, Object?> props;
  final Object? state;
  final Map<String, Object?>? schema;
  final Map<String, Object?>? manifest;
  final Map<String, Object?>? lastAction;
  final List<QuickjsUiLifecycleEvent> lifecycle;
  final List<String> hostApis;
  final List<String> resources;
  final List<Map<String, Object?>> network;
  final QuickjsUiDiffStats? diff;
  final Object? error;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'exportedAt': exportedAt.toIso8601String(),
      if (pageId != null) 'pageId': pageId,
      if (pageVersion != null) 'pageVersion': pageVersion,
      if (pageName != null) 'pageName': pageName,
      'props': props,
      if (state != null) 'state': state,
      if (schema != null) 'schema': schema,
      if (manifest != null) 'manifest': manifest,
      if (lastAction != null) 'lastAction': lastAction,
      'lifecycle': <Map<String, Object?>>[
        for (final event in lifecycle) event.toMap(),
      ],
      if (hostApis.isNotEmpty) 'hostApis': hostApis,
      if (resources.isNotEmpty) 'resources': resources,
      if (network.isNotEmpty) 'network': network,
      if (diff != null) 'diff': diff!.toMap(),
      if (error != null) 'error': '$error',
    };
  }

  static Map<String, Object?>? manifestFor(QuickjsPlugin? plugin) {
    if (plugin == null) {
      return null;
    }
    final manifest = plugin.manifest;
    return <String, Object?>{
      'id': manifest.id,
      'version': manifest.version,
      'entry': manifest.entry,
      'exports': manifest.exports,
      if (manifest.init != null) 'init': manifest.init,
      if (manifest.dispose != null) 'dispose': manifest.dispose,
      if (manifest.permissions.isNotEmpty) 'permissions': manifest.permissions,
      if (manifest.metadata.isNotEmpty) 'metadata': manifest.metadata,
    };
  }

  static Map<String, Object?>? schemaFor(QuickjsUiNode? node) {
    return node?.toMap();
  }

  static List<String> resourcesFor(QuickjsPlugin? plugin) {
    if (plugin == null) {
      return const <String>[];
    }
    return <String>[
      for (final module in plugin.modules) module.specifier,
    ];
  }

  static List<String> hostApisFor(List<QuickjsHostMount> mounts) {
    return <String>[for (final mount in mounts) mount.name];
  }
}
