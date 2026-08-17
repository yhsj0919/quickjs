/// Persists text responses used by the JSUI network loader.
abstract interface class JsUiNetworkCacheStore {
  /// Reads the cached response for [uri], or returns `null`.
  Future<JsUiNetworkCacheEntry?> read(Uri uri);

  /// Stores [entry] under its normalized [uri].
  Future<void> write(Uri uri, JsUiNetworkCacheEntry entry);
}

/// A cached network response body and its validation metadata.
final class JsUiNetworkCacheEntry {
  /// Creates a cache entry, defaulting [cachedAt] to the current time.
  JsUiNetworkCacheEntry({required this.body, this.etag, DateTime? cachedAt})
    : cachedAt = cachedAt ?? DateTime.now();

  /// Decoded response body.
  final String body;

  /// Entity tag used for conditional revalidation.
  final String? etag;

  /// Time at which the entry was stored.
  final DateTime cachedAt;
}

/// An in-memory network cache store.
final class JsUiMemoryNetworkCacheStore implements JsUiNetworkCacheStore {
  /// Creates a store optionally backed by an existing [entries] map.
  JsUiMemoryNetworkCacheStore([Map<Uri, JsUiNetworkCacheEntry>? entries])
    : _entries = entries ?? <Uri, JsUiNetworkCacheEntry>{};

  final Map<Uri, JsUiNetworkCacheEntry> _entries;

  @override
  Future<JsUiNetworkCacheEntry?> read(Uri uri) async {
    return _entries[uri];
  }

  @override
  Future<void> write(Uri uri, JsUiNetworkCacheEntry entry) async {
    _entries[uri] = entry;
  }
}

/// A persistent file-backed cache store where file I/O is supported.
final class JsUiFileNetworkCacheStore implements JsUiNetworkCacheStore {
  /// Creates a placeholder that reports file caching as unsupported.
  const JsUiFileNetworkCacheStore({required Object directory})
    // ignore: prefer_initializing_formals
    : _directory = directory;

  final Object _directory;

  @override
  Future<JsUiNetworkCacheEntry?> read(Uri uri) async {
    throw UnsupportedError(
      'quickjs_ui file network cache is not supported on this platform: '
      '$_directory',
    );
  }

  @override
  Future<void> write(Uri uri, JsUiNetworkCacheEntry entry) async {
    throw UnsupportedError(
      'quickjs_ui file network cache is not supported on this platform: '
      '$_directory',
    );
  }
}
