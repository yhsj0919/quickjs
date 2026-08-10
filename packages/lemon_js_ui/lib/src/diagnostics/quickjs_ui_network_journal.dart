import 'dart:async';

import '../host/quickjs_ui_host_capabilities.dart';
import '../resource/quickjs_ui_network_loader.dart';
import 'quickjs_ui_network_record.dart';

/// Collects bundle loader and host API network activity into structured records.
final class QuickjsUiNetworkJournal {
  static const int maxRecords = 256;

  final List<QuickjsUiNetworkRecord> _records = <QuickjsUiNetworkRecord>[];
  final Map<String, QuickjsUiNetworkRecord> _pending =
      <String, QuickjsUiNetworkRecord>{};

  List<QuickjsUiNetworkRecord> get records =>
      List<QuickjsUiNetworkRecord>.unmodifiable(_records);

  void clear() {
    _records.clear();
    _pending.clear();
  }

  void handleLogEvent(QuickjsUiNetworkLogEvent event) {
    final id = event.id;
    if (id == null || id.isEmpty) {
      _appendLegacyLog(event);
      return;
    }
    switch (event.type) {
      case 'network.request':
        final record = QuickjsUiNetworkRecord(
          id: id,
          source: QuickjsUiNetworkSource.bundle,
          method: event.method ?? 'GET',
          uri: event.uri,
          startedAt: event.timestamp ?? DateTime.now(),
          etag: event.etag,
          phase: QuickjsUiNetworkRecordPhase.pending,
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
          phase: QuickjsUiNetworkRecordPhase.cacheHit,
        );
      case 'network.cacheStore':
        _completeBundleRecord(
          id: id,
          statusCode: event.statusCode,
          durationMs: event.durationMs,
          bodyBytes: event.bodyBytes,
          etag: event.etag,
          fromCache: false,
          phase: QuickjsUiNetworkRecordPhase.completed,
        );
      default:
        _appendLegacyLog(event);
    }
  }

  void _updateBundleResponse(String id, QuickjsUiNetworkLogEvent event) {
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
        phase: QuickjsUiNetworkRecordPhase.failed,
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
        phase: QuickjsUiNetworkRecordPhase.failed,
        error: 'HTTP $statusCode',
      );
    }
  }

  Future<Object?> traceHostRequest(
    Map<String, Object?> request,
    FutureOr<Object?> Function() action,
  ) async {
    final id = _nextHostId();
    final uri = _uriFromHostRequest(request);
    final method = _methodFromHostRequest(request);
    final startedAt = DateTime.now();
    final pending = QuickjsUiNetworkRecord(
      id: id,
      source: QuickjsUiNetworkSource.host,
      method: method,
      uri: uri,
      startedAt: startedAt,
      phase: QuickjsUiNetworkRecordPhase.pending,
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
    required QuickjsUiNetworkRecordPhase phase,
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
        phase: failed ? QuickjsUiNetworkRecordPhase.failed : phase,
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
            ? QuickjsUiNetworkRecordPhase.failed
            : QuickjsUiNetworkRecordPhase.completed,
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
        phase: QuickjsUiNetworkRecordPhase.failed,
        error: error,
      ),
    );
  }

  void _appendLegacyLog(QuickjsUiNetworkLogEvent event) {
    _appendRecord(
      QuickjsUiNetworkRecord(
        id: 'legacy-${_records.length + 1}',
        source: QuickjsUiNetworkSource.bundle,
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
            ? QuickjsUiNetworkRecordPhase.cacheHit
            : QuickjsUiNetworkRecordPhase.completed,
      ),
    );
  }

  void _appendRecord(QuickjsUiNetworkRecord record) {
    _records.add(record);
    _trimRecords();
  }

  void _replaceRecord(QuickjsUiNetworkRecord record) {
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
QuickjsUiHostApiHandlers instrumentHostNetworkLogging(
  QuickjsUiHostApiHandlers handlers,
  QuickjsUiNetworkJournal journal,
) {
  final onNetworkRequest = handlers.onNetworkRequest;
  if (onNetworkRequest == null) {
    return handlers;
  }
  return QuickjsUiHostApiHandlers(
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
