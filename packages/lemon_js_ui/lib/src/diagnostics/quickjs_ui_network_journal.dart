import 'dart:async';

import '../host/quickjs_ui_host_capabilities.dart';
import '../resource/quickjs_ui_network_loader.dart';
import 'quickjs_ui_network_record.dart';

/// Collects bundle loader and host API network activity into structured records.
final class JsUiNetworkJournal {
  /// Journal 保留的最大记录数，超出后移除最早记录。
  static const int maxRecords = 256;

  final List<JsUiNetworkRecord> _records = <JsUiNetworkRecord>[];
  final Map<String, JsUiNetworkRecord> _pending = <String, JsUiNetworkRecord>{};

  /// 当前网络记录的不可变快照。
  List<JsUiNetworkRecord> get records =>
      List<JsUiNetworkRecord>.unmodifiable(_records);

  /// 清空已完成和等待中的全部记录。
  void clear() {
    _records.clear();
    _pending.clear();
  }

  /// 将 Bundle Loader 的 [event] 合并进结构化记录。
  void handleLogEvent(JsUiNetworkLogEvent event) {
    final id = event.id;
    if (id == null || id.isEmpty) {
      _appendLegacyLog(event);
      return;
    }
    switch (event.type) {
      case 'network.request':
        final record = JsUiNetworkRecord(
          id: id,
          source: JsUiNetworkSource.bundle,
          method: event.method ?? 'GET',
          uri: event.uri,
          startedAt: event.timestamp ?? DateTime.now(),
          etag: event.etag,
          phase: JsUiNetworkRecordPhase.pending,
        );
        _pending[id] = record;
        _appendRecord(record);
      case 'network.response':
        _updateBundleResponse(id, event);
      case 'network.cacheHit':
        _completeBundleRecord(
          id: id,
          statusCode: event.statusCode,
          durationMs: event.durationMs,
          bodyBytes: event.bodyBytes,
          etag: event.etag,
          fromCache: true,
          phase: JsUiNetworkRecordPhase.cacheHit,
        );
      case 'network.cacheStore':
        _completeBundleRecord(
          id: id,
          statusCode: event.statusCode,
          durationMs: event.durationMs,
          bodyBytes: event.bodyBytes,
          etag: event.etag,
          fromCache: false,
          phase: JsUiNetworkRecordPhase.completed,
        );
      default:
        _appendLegacyLog(event);
    }
  }

  void _updateBundleResponse(String id, JsUiNetworkLogEvent event) {
    final pending = _pending[id];
    if (pending == null) {
      return;
    }
    if (event.error != null) {
      _completeBundleRecord(
        id: id,
        statusCode: event.statusCode,
        durationMs: event.durationMs,
        bodyBytes: event.bodyBytes,
        etag: event.etag,
        fromCache: false,
        phase: JsUiNetworkRecordPhase.failed,
        error: event.error,
      );
      return;
    }
    final updated = pending.copyWith(
      statusCode: event.statusCode,
      durationMs: event.durationMs,
      bodyBytes: event.bodyBytes,
      etag: event.etag ?? pending.etag,
    );
    _replaceRecord(updated);
    _pending[id] = updated;
    final statusCode = event.statusCode;
    if (statusCode != null &&
        statusCode != 304 &&
        (statusCode < 200 || statusCode >= 300)) {
      _completeBundleRecord(
        id: id,
        statusCode: statusCode,
        durationMs: event.durationMs,
        bodyBytes: event.bodyBytes,
        etag: event.etag,
        fromCache: false,
        phase: JsUiNetworkRecordPhase.failed,
        error: 'HTTP $statusCode',
      );
    }
  }

  /// 执行宿主网络 [action]，同时记录请求、结果、耗时与错误。
  Future<Object?> traceHostRequest(
    Map<String, Object?> request,
    FutureOr<Object?> Function() action,
  ) async {
    final id = _nextHostId();
    final uri = _uriFromHostRequest(request);
    final method = _methodFromHostRequest(request);
    final startedAt = DateTime.now();
    final pending = JsUiNetworkRecord(
      id: id,
      source: JsUiNetworkSource.host,
      method: method,
      uri: uri,
      startedAt: startedAt,
      phase: JsUiNetworkRecordPhase.pending,
    );
    _pending[id] = pending;
    _appendRecord(pending);
    final stopwatch = Stopwatch()..start();
    try {
      final result = await action();
      stopwatch.stop();
      _completeHostRecord(
        id: id,
        statusCode: _statusCodeFromResult(result) ?? 200,
        durationMs: stopwatch.elapsedMilliseconds,
        bodyBytes: _bodyBytesFromResult(result),
      );
      return result;
    } catch (error) {
      stopwatch.stop();
      _failHostRecord(
        id: id,
        durationMs: stopwatch.elapsedMilliseconds,
        error: '$error',
      );
      rethrow;
    }
  }

  void _completeBundleRecord({
    required String id,
    int? statusCode,
    int? durationMs,
    int? bodyBytes,
    String? etag,
    required bool fromCache,
    required JsUiNetworkRecordPhase phase,
    String? error,
  }) {
    final pending = _pending.remove(id);
    if (pending == null) {
      return;
    }
    final failed =
        error != null ||
        (statusCode != null &&
            statusCode != 304 &&
            (statusCode < 200 || statusCode >= 300));
    _replaceRecord(
      pending.copyWith(
        completedAt: DateTime.now(),
        statusCode: statusCode ?? pending.statusCode,
        durationMs: durationMs ?? pending.durationMs,
        bodyBytes: bodyBytes ?? pending.bodyBytes,
        etag: etag ?? pending.etag,
        fromCache: fromCache,
        phase: failed ? JsUiNetworkRecordPhase.failed : phase,
        error:
            error ??
            (failed ? 'HTTP ${statusCode ?? pending.statusCode}' : null),
      ),
    );
  }

  void _completeHostRecord({
    required String id,
    required int statusCode,
    required int durationMs,
    int? bodyBytes,
  }) {
    final pending = _pending.remove(id);
    if (pending == null) {
      return;
    }
    final failed = statusCode < 200 || statusCode >= 300;
    _replaceRecord(
      pending.copyWith(
        completedAt: DateTime.now(),
        statusCode: statusCode,
        durationMs: durationMs,
        bodyBytes: bodyBytes,
        phase: failed
            ? JsUiNetworkRecordPhase.failed
            : JsUiNetworkRecordPhase.completed,
        error: failed ? 'HTTP $statusCode' : null,
      ),
    );
  }

  void _failHostRecord({
    required String id,
    required int durationMs,
    required String error,
  }) {
    final pending = _pending.remove(id);
    if (pending == null) {
      return;
    }
    _replaceRecord(
      pending.copyWith(
        completedAt: DateTime.now(),
        durationMs: durationMs,
        phase: JsUiNetworkRecordPhase.failed,
        error: error,
      ),
    );
  }

  void _appendLegacyLog(JsUiNetworkLogEvent event) {
    _appendRecord(
      JsUiNetworkRecord(
        id: 'legacy-${_records.length + 1}',
        source: JsUiNetworkSource.bundle,
        method: event.method ?? 'GET',
        uri: event.uri,
        startedAt: event.timestamp ?? DateTime.now(),
        completedAt: event.timestamp ?? DateTime.now(),
        statusCode: event.statusCode,
        durationMs: event.durationMs,
        bodyBytes: event.bodyBytes,
        etag: event.etag,
        fromCache: event.fromCache,
        phase: event.fromCache
            ? JsUiNetworkRecordPhase.cacheHit
            : JsUiNetworkRecordPhase.completed,
      ),
    );
  }

  void _appendRecord(JsUiNetworkRecord record) {
    _records.add(record);
    _trimRecords();
  }

  void _replaceRecord(JsUiNetworkRecord record) {
    final index = _records.indexWhere((entry) => entry.id == record.id);
    if (index < 0) {
      _appendRecord(record);
      return;
    }
    _records[index] = record;
  }

  void _trimRecords() {
    if (_records.length <= maxRecords) {
      return;
    }
    _records.removeRange(0, _records.length - maxRecords);
  }

  String _nextHostId() => 'host-${_records.length + _pending.length + 1}';

  static Uri _uriFromHostRequest(Map<String, Object?> request) {
    final url = request['url'] ?? request['uri'];
    if (url is String && url.isNotEmpty) {
      return Uri.parse(url);
    }
    return Uri.parse('quickjs-ui://host/network');
  }

  static String _methodFromHostRequest(Map<String, Object?> request) {
    final method = request['method'];
    if (method is String && method.isNotEmpty) {
      return method.toUpperCase();
    }
    return 'GET';
  }

  static int? _statusCodeFromResult(Object? result) {
    if (result is Map) {
      final statusCode = result['statusCode'] ?? result['status'];
      if (statusCode is num) {
        return statusCode.toInt();
      }
    }
    return null;
  }

  static int? _bodyBytesFromResult(Object? result) {
    if (result is Map) {
      final body = result['body'];
      if (body is String) {
        return body.length;
      }
    }
    return null;
  }
}

/// Wraps [handlers.onNetworkRequest] so host HTTP calls appear in the journal.
JsUiHostApiHandlers instrumentHostNetworkLogging(
  JsUiHostApiHandlers handlers,
  JsUiNetworkJournal journal,
) {
  final onNetworkRequest = handlers.onNetworkRequest;
  if (onNetworkRequest == null) {
    return handlers;
  }
  return JsUiHostApiHandlers(
    onToast: handlers.onToast,
    onConfirm: handlers.onConfirm,
    onDialog: handlers.onDialog,
    onSnackbar: handlers.onSnackbar,
    onBottomSheet: handlers.onBottomSheet,
    onNavigationIntent: handlers.onNavigationIntent,
    onClipboardReadText: handlers.onClipboardReadText,
    onClipboardWriteText: handlers.onClipboardWriteText,
    onNetworkRequest: (request) {
      final map = Map<String, Object?>.from(request);
      return journal.traceHostRequest(map, () => onNetworkRequest(map));
    },
    onFileSystemOperation: handlers.onFileSystemOperation,
    onNativeCall: handlers.onNativeCall,
  );
}
