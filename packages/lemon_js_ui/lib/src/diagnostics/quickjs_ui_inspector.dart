import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';
import 'package:lemon_js/lemon_js.dart';

import '../schema/quickjs_ui_node.dart';
import '../performance/quickjs_ui_effect_quality.dart';
import 'quickjs_ui_diff_stats.dart';
import 'quickjs_ui_lifecycle_event.dart';
import 'quickjs_ui_network_journal.dart';
import 'quickjs_ui_network_record.dart';
import 'quickjs_ui_page_snapshot.dart';
import '../resource/quickjs_ui_network_loader.dart';

/// Collects quickjs_ui runtime diagnostics for development and debugging.
///
/// Listener notifications are deferred to the next frame so renderer diff/schema
/// updates never rebuild inspector panels during [JsUiView.build].
final class JsUiInspector extends ChangeNotifier {
  /// The max lifecycle events value.
  /// The max lifecycle events value.
  static const int maxLifecycleEvents = 256;

  final List<JsUiLifecycleEvent> _lifecycle = <JsUiLifecycleEvent>[];
  Map<String, Object?>? _lastAction;
  JsUiDiffStats? _lastDiff;
  Map<String, Object?>? _lastSchema;
  final List<String> _resourceLog = <String>[];

  /// The network journal value.
  /// The network journal value.
  final JsUiNetworkJournal networkJournal = JsUiNetworkJournal();
  Object? _lastError;
  JsUiPerformanceSnapshot? _performance;
  bool _notifyScheduled = false;
  bool _disposed = false;

  /// Returns the current lifecycle timeline.
  /// Returns the current lifecycle timeline.
  List<JsUiLifecycleEvent> get lifecycleTimeline =>
      List<JsUiLifecycleEvent>.unmodifiable(_lifecycle);

  /// Returns the current last action.
  /// Returns the current last action.
  Map<String, Object?>? get lastAction => _lastAction;

  /// Returns the current last diff.
  /// Returns the current last diff.
  JsUiDiffStats? get lastDiff => _lastDiff;

  /// Returns the current last schema.
  /// Returns the current last schema.
  Map<String, Object?>? get lastSchema => _lastSchema;

  /// Returns the current resource log.
  /// Returns the current resource log.
  List<String> get resourceLog => List<String>.unmodifiable(_resourceLog);

  /// Returns the current network records.
  /// Returns the current network records.
  List<JsUiNetworkRecord> get networkRecords => networkJournal.records;

  /// Returns the current last error.
  /// Returns the current last error.
  Object? get lastError => _lastError;

  /// Returns the current performance.
  /// Returns the current performance.
  JsUiPerformanceSnapshot? get performance => _performance;

  /// Performs the record performance operation.
  /// Performs the record performance operation.
  void recordPerformance(JsUiPerformanceSnapshot snapshot) {
    _performance = snapshot;
    _scheduleNotify();
  }

  /// Performs the record lifecycle operation.
  /// Performs the record lifecycle operation.
  void recordLifecycle(String phase, String type, {Object? payload}) {
    _lifecycle.add(
      JsUiLifecycleEvent(
        phase: phase,
        type: type,
        payload: payload,
        timestamp: DateTime.now(),
      ),
    );
    if (_lifecycle.length > maxLifecycleEvents) {
      _lifecycle.removeRange(0, _lifecycle.length - maxLifecycleEvents);
    }
    _scheduleNotify();
  }

  /// Performs the record action operation.
  /// Performs the record action operation.
  void recordAction(Map<String, Object?> event) {
    _lastAction = Map<String, Object?>.unmodifiable(event);
    _lifecycle.add(
      JsUiLifecycleEvent(
        phase: 'action',
        type: _actionType(event),
        payload: event,
        timestamp: DateTime.now(),
      ),
    );
    if (_lifecycle.length > maxLifecycleEvents) {
      _lifecycle.removeRange(0, _lifecycle.length - maxLifecycleEvents);
    }
    _scheduleNotify();
  }

  /// Performs the record diff operation.
  /// Performs the record diff operation.
  void recordDiff(JsUiDiffStats stats) {
    _lastDiff = stats;
    _scheduleNotify();
  }

  /// Performs the record schema operation.
  /// Performs the record schema operation.
  void recordSchema(Map<String, Object?> schema) {
    _lastSchema = schema;
    _scheduleNotify();
  }

  /// Performs the record resource operation.
  /// Performs the record resource operation.
  void recordResource(String message) {
    _resourceLog.add(message);
    if (_resourceLog.length > maxLifecycleEvents) {
      _resourceLog.removeRange(0, _resourceLog.length - maxLifecycleEvents);
    }
    _scheduleNotify();
  }

  /// Performs the record network event operation.
  /// Performs the record network event operation.
  void recordNetworkEvent(JsUiNetworkLogEvent event) {
    networkJournal.handleLogEvent(event);
    _scheduleNotify();
  }

  /// Performs the record error operation.
  /// Performs the record error operation.
  void recordError(Object? error) {
    _lastError = error;
    _scheduleNotify();
  }

  /// Performs the clear operation.
  /// Performs the clear operation.
  void clear() {
    _lifecycle.clear();
    _lastAction = null;
    _lastDiff = null;
    _lastSchema = null;
    _resourceLog.clear();
    networkJournal.clear();
    _lastError = null;
    _performance = null;
    _scheduleNotify();
  }

  @override
  void dispose() {
    _disposed = true;
    _notifyScheduled = false;
    super.dispose();
  }

  void _scheduleNotify() {
    if (_disposed || _notifyScheduled) {
      return;
    }
    _notifyScheduled = true;
    SchedulerBinding.instance.addPostFrameCallback((_) {
      _notifyScheduled = false;
      if (_disposed) {
        return;
      }
      notifyListeners();
    });
  }

  /// Performs the build snapshot operation.
  /// Performs the build snapshot operation.
  JsUiPageSnapshot buildSnapshot({
    required Map<String, Object?> props,
    required Object? state,
    required JsUiNode? node,
    required JsPlugin? plugin,
    required List<JsFeatures> features,
    Object? error,
  }) {
    final pageName = plugin?.manifest.metadata['name'];
    return JsUiPageSnapshot(
      exportedAt: DateTime.now(),
      pageId: plugin?.manifest.id,
      pageVersion: plugin?.manifest.version,
      pageName: pageName is String ? pageName : null,
      props: props,
      state: state,
      schema: JsUiPageSnapshot.schemaFor(node),
      manifest: JsUiPageSnapshot.manifestFor(plugin),
      lastAction: _lastAction,
      lifecycle: lifecycleTimeline,
      hostApis: JsUiPageSnapshot.hostApisFor(features),
      resources: JsUiPageSnapshot.resourcesFor(plugin),
      network: networkRecords.map((record) => record.toMap()).toList(),
      diff: _lastDiff,
      performance: _performance,
      error: error ?? _lastError,
    );
  }

  String _actionType(Map<String, Object?> event) {
    final method = event['method'] ?? event['action'];
    if (method is String && method.isNotEmpty) {
      return method;
    }
    final type = event['type'];
    if (type is String && type.isNotEmpty) {
      return type;
    }
    return 'dispatch';
  }
}
