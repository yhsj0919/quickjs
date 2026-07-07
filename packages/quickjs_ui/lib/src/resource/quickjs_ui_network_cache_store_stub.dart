abstract interface class QuickjsUiNetworkCacheStore {
  Future<QuickjsUiNetworkCacheEntry?> read(Uri uri);

  Future<void> write(Uri uri, QuickjsUiNetworkCacheEntry entry);
}

final class QuickjsUiNetworkCacheEntry {
  QuickjsUiNetworkCacheEntry({
    required this.body,
    this.etag,
    DateTime? cachedAt,
  }) : cachedAt = cachedAt ?? DateTime.now();

  final String body;
  final String? etag;
  final DateTime cachedAt;
}

final class QuickjsUiMemoryNetworkCacheStore
    implements QuickjsUiNetworkCacheStore {
  QuickjsUiMemoryNetworkCacheStore([
    Map<Uri, QuickjsUiNetworkCacheEntry>? entries,
  ]) : _entries = entries ?? <Uri, QuickjsUiNetworkCacheEntry>{};

  final Map<Uri, QuickjsUiNetworkCacheEntry> _entries;

  @override
  Future<QuickjsUiNetworkCacheEntry?> read(Uri uri) async {
    return _entries[uri];
  }

  @override
  Future<void> write(Uri uri, QuickjsUiNetworkCacheEntry entry) async {
    _entries[uri] = entry;
  }
}

final class QuickjsUiFileNetworkCacheStore
    implements QuickjsUiNetworkCacheStore {
  const QuickjsUiFileNetworkCacheStore({required Object directory})
    // Keep this constructor source-compatible with the IO implementation.
    // ignore: prefer_initializing_formals
    : _directory = directory;

  final Object _directory;

  @override
  Future<QuickjsUiNetworkCacheEntry?> read(Uri uri) async {
    throw UnsupportedError(
      'quickjs_ui file network cache is not supported on this platform: '
      '$_directory',
    );
  }

  @override
  Future<void> write(Uri uri, QuickjsUiNetworkCacheEntry entry) async {
    throw UnsupportedError(
      'quickjs_ui file network cache is not supported on this platform: '
      '$_directory',
    );
  }
}
