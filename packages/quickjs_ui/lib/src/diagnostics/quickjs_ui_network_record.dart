/// One network request observed by quickjs_ui development tooling.
final class QuickjsUiNetworkRecord {
  const QuickjsUiNetworkRecord({
    required this.id,
    required this.source,
    required this.method,
    required this.uri,
    required this.startedAt,
    this.completedAt,
    this.statusCode,
    this.durationMs,
    this.bodyBytes,
    this.etag,
    this.fromCache = false,
    this.error,
    this.phase = QuickjsUiNetworkRecordPhase.pending,
  });

  final String id;
  final QuickjsUiNetworkSource source;
  final String method;
  final Uri uri;
  final DateTime startedAt;
  final DateTime? completedAt;
  final int? statusCode;
  final int? durationMs;
  final int? bodyBytes;
  final String? etag;
  final bool fromCache;
  final String? error;
  final QuickjsUiNetworkRecordPhase phase;

  bool get succeeded =>
      error == null &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 300;

  QuickjsUiNetworkRecord copyWith({
    DateTime? completedAt,
    int? statusCode,
    int? durationMs,
    int? bodyBytes,
    String? etag,
    bool? fromCache,
    String? error,
    QuickjsUiNetworkRecordPhase? phase,
  }) {
    return QuickjsUiNetworkRecord(
      id: id,
      source: source,
      method: method,
      uri: uri,
      startedAt: startedAt,
      completedAt: completedAt ?? this.completedAt,
      statusCode: statusCode ?? this.statusCode,
      durationMs: durationMs ?? this.durationMs,
      bodyBytes: bodyBytes ?? this.bodyBytes,
      etag: etag ?? this.etag,
      fromCache: fromCache ?? this.fromCache,
      error: error ?? this.error,
      phase: phase ?? this.phase,
    );
  }

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'id': id,
      'source': source.name,
      'method': method,
      'uri': uri.toString(),
      'startedAt': startedAt.toIso8601String(),
      if (completedAt != null) 'completedAt': completedAt!.toIso8601String(),
      if (statusCode != null) 'statusCode': statusCode,
      if (durationMs != null) 'durationMs': durationMs,
      if (bodyBytes != null) 'bodyBytes': bodyBytes,
      if (etag != null) 'etag': etag,
      'fromCache': fromCache,
      if (error != null) 'error': error,
      'phase': phase.name,
    };
  }
}

enum QuickjsUiNetworkSource { bundle, host }

enum QuickjsUiNetworkRecordPhase {
  pending,
  completed,
  cacheHit,
  failed,
}
