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
/// updates never rebuild inspector panels during [QuickjsUiView.build].
final class QuickjsUiInspector extends ChangeNotifier {
  static const int maxLifecycleEvents = 256;

  final List<QuickjsUiLifecycleEvent> _lifecycle = <QuickjsUiLifecycleEvent>[];
  Map<String, Object?>? _lastAction;
  QuickjsUiDiffStats? _lastDiff;
  Map<String, Object?>? _lastSchema;
  final List<String> _resourceLog = <String>[];
  final QuickjsUiNetworkJournal networkJournal = QuickjsUiNetworkJournal();
  Object? _lastError;
  QuickjsUiPerformanceSnapshot? _performance;
  bool _notifyScheduled = false;
  bool _disposed = false;

  List<QuickjsUiLifecycleEvent> get lifecycleTimeline =>
      List<QuickjsUiLifecycleEvent>.unmodifiable(_lifecycle);

  Map<String, Object?>? get lastAction => _lastAction;

  QuickjsUiDiffStats? get lastDiff => _lastDiff;

  Map<String, Object?>? get lastSchema => _lastSchema;

  List<String> get resourceLog => List<String>.unmodifiable(_resourceLog);

  List<QuickjsUiNetworkRecord> get networkRecords => networkJournal.records;

  Object? get lastError => _lastError;
  QuickjsUiPerformanceSnapshot? get performance => _performance;

  void recordPerformance(QuickjsUiPerformanceSnapshot snapshot) {
    _performance = snapshot;
    _scheduleNotify();
  }

  void recordLifecycle(String phase, String type, {Object? payload}) {
    _lifecycle.add(
      QuickjsUiLifecycleEvent(
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

  void recordAction(Map<String, Object?> event) {
    _lastAction = Map<String, Object?>.unmodifiable(event);
    _lifecycle.add(
      QuickjsUiLifecycleEvent(
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

  void recordDiff(QuickjsUiDiffStats stats) {
    _lastDiff = stats;
    _scheduleNotify();
  }

  void recordSchema(Map<String, Object?> schema) {
    _lastSchema = schema;
    _scheduleNotify();
  }

  void recordResource(String message) {
    _resourceLog.add(message);
    if (_resourceLog.length > maxLifecycleEvents) {
      _resourceLog.removeRange(0, _resourceLog.length - maxLifecycleEvents);
    }
    _scheduleNotify();
  }

  void recordNetworkEvent(QuickjsUiNetworkLogEvent event) {
    networkJournal.handleLogEvent(event);
    _scheduleNotify();
  }

  void recordError(Object? error) {
    _lastError = error;
    _scheduleNotify();
  }

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

  QuickjsUiPageSnapshot buildSnapshot({
    required Map<String, Object?> props,
    required Object? state,
    required QuickjsUiNode? node,
    required QuickjsPlugin? plugin,
    required List<QuickjsHostMount> mounts,
    Object? error,
  }) {
    final pageName = plugin?.manifest.metadata['name'];
    return QuickjsUiPageSnapshot(
      exportedAt: DateTime.now(),
      pageId: plugin?.manifest.id,
      pageVersion: plugin?.manifest.version,
      pageName: pageName is String ? pageName : null,
      props: props,
      state: state,
      schema: QuickjsUiPageSnapshot.schemaFor(node),
      manifest: QuickjsUiPageSnapshot.manifestFor(plugin),
      lastAction: _lastAction,
      lifecycle: lifecycleTimeline,
      hostApis: QuickjsUiPageSnapshot.hostApisFor(mounts),
      resources: QuickjsUiPageSnapshot.resourcesFor(plugin),
      network: networkRecords.map((record) => record.toMap()).toList(),
      diff: _lastDiff,
      performance: _performance,
      error: error ?? _lastError,
    );
  }

  Map<String, Object?> buildSnapshotMap({
    required Map<String, Object?> props,
    required Object? state,
    required QuickjsUiNode? node,
    required QuickjsPlugin? plugin,
    required List<QuickjsHostMount> mounts,
    Object? error,
  }) {
    return buildSnapshot(
      props: props,
      state: state,
      node: node,
      plugin: plugin,
      mounts: mounts,
      error: error,
    ).toMap();
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
