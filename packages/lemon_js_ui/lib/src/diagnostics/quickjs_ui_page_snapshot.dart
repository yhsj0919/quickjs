import 'package:lemon_js/lemon_js.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_diff_stats.dart';
import 'quickjs_ui_lifecycle_event.dart';
import '../performance/quickjs_ui_effect_quality.dart';

/// Serializable page snapshot for debugging and issue reproduction.
final class JsUiPageSnapshot {
  /// Creates a diagnostic snapshot from captured page subsystems.
  const JsUiPageSnapshot({
    required this.exportedAt,
    this.pageId,
    this.pageVersion,
    this.pageName,
    this.props = const <String, Object?>{},
    this.state,
    this.schema,
    this.manifest,
    this.lastAction,
    this.lifecycle = const <JsUiLifecycleEvent>[],
    this.hostApis = const <String>[],
    this.resources = const <String>[],
    this.network = const <Map<String, Object?>>[],
    this.diff,
    this.performance,
    this.error,
  });

  /// Time at which the snapshot was exported.
  final DateTime exportedAt;

  /// Optional page or plugin identifier.
  final String? pageId;

  /// Optional page or plugin version.
  final String? pageVersion;

  /// Optional user-visible page name.
  final String? pageName;

  /// Initial or current page properties.
  final Map<String, Object?> props;

  /// Current JavaScript page state, when serializable.
  final Object? state;

  /// Serialized JSUI node schema.
  final Map<String, Object?>? schema;

  /// Serialized plugin manifest.
  final Map<String, Object?>? manifest;

  /// Most recently dispatched action.
  final Map<String, Object?>? lastAction;

  /// Captured lifecycle history.
  final List<JsUiLifecycleEvent> lifecycle;

  /// Names of installed host feature groups.
  final List<String> hostApis;

  /// Module or resource names declared by the plugin.
  final List<String> resources;

  /// Serialized network journal records.
  final List<Map<String, Object?>> network;

  /// Latest renderer diff statistics.
  final JsUiDiffStats? diff;

  /// Latest performance-controller snapshot.
  final JsUiPerformanceSnapshot? performance;

  /// Latest page error, if any.
  final Object? error;

  /// Serializes this snapshot to JSON-compatible structured data.
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
      if (performance != null) 'performance': performance!.toMap(),
      if (error != null) 'error': '$error',
    };
  }

  /// Serializes the manifest of [plugin], or returns `null` when absent.
  static Map<String, Object?>? manifestFor(JsPlugin? plugin) {
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

  /// Serializes a JSUI schema [node], or returns `null` when absent.
  static Map<String, Object?>? schemaFor(JsUiNode? node) {
    return node?.toMap();
  }

  /// Returns module names declared by [plugin].
  static List<String> resourcesFor(JsPlugin? plugin) {
    if (plugin == null) {
      return const <String>[];
    }
    return <String>[for (final module in plugin.modules) module.name];
  }

  /// Returns the names of installed host [features].
  static List<String> hostApisFor(List<JsFeatures> features) {
    return <String>[for (final features in features) features.name];
  }
}
