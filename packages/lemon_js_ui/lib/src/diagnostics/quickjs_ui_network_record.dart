/// One network request observed by quickjs_ui development tooling.
final class JsUiNetworkRecord {
  /// Creates a snapshot of one observed request.
  const JsUiNetworkRecord({
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
    this.phase = JsUiNetworkRecordPhase.pending,
  });

  /// Correlation identifier assigned by the network journal.
  final String id;

  /// Subsystem that issued the request.
  final JsUiNetworkSource source;

  /// HTTP or host request method.
  final String method;

  /// Requested URI.
  final Uri uri;

  /// Time at which the request began.
  final DateTime startedAt;

  /// Time at which the final event was observed.
  final DateTime? completedAt;

  /// Response status code, when available.
  final int? statusCode;

  /// Reported request duration in milliseconds.
  final int? durationMs;

  /// Reported response body size in bytes.
  final int? bodyBytes;

  /// Entity tag sent or received by the request.
  final String? etag;

  /// Whether the response body was served from a cache.
  final bool fromCache;

  /// Failure description, when the request failed.
  final String? error;

  /// Current request lifecycle phase.
  final JsUiNetworkRecordPhase phase;

  /// Whether the record has a successful 2xx response and no [error].
  bool get succeeded =>
      error == null &&
      statusCode != null &&
      statusCode! >= 200 &&
      statusCode! < 300;

  /// Returns a copy with the supplied completion fields replaced.
  JsUiNetworkRecord copyWith({
    DateTime? completedAt,
    int? statusCode,
    int? durationMs,
    int? bodyBytes,
    String? etag,
    bool? fromCache,
    String? error,
    JsUiNetworkRecordPhase? phase,
  }) {
    return JsUiNetworkRecord(
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

  /// Serializes this record to JSON-compatible structured data.
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

/// Identifies the subsystem that produced a network record.
enum JsUiNetworkSource {
  /// The JSUI bundle or package loader.
  bundle,

  /// A page request delegated through a host network capability.
  host,
}

/// The observed lifecycle state of a network request.
enum JsUiNetworkRecordPhase {
  /// A request event was observed without a final response.
  pending,

  /// A non-cache response completed.
  completed,

  /// The resource was served from a cache.
  cacheHit,

  /// The request completed with an error.
  failed,
}
