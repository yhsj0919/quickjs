import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
  /// Creates a store that writes hashed JSON entries below [directory].
  const JsUiFileNetworkCacheStore({required this.directory});

  /// Directory containing cached JSON response entries.
  final Directory directory;

  @override
  Future<JsUiNetworkCacheEntry?> read(Uri uri) async {
    final file = _fileFor(uri);
    if (!await file.exists()) {
      return null;
    }
    final decoded = jsonDecode(await file.readAsString());
    if (decoded is! Map) {
      return null;
    }
    final body = decoded['body'];
    if (body is! String) {
      return null;
    }
    final etag = decoded['etag'];
    final cachedAt = decoded['cachedAt'];
    return JsUiNetworkCacheEntry(
      body: body,
      etag: etag is String ? etag : null,
      cachedAt: cachedAt is String ? DateTime.tryParse(cachedAt) : null,
    );
  }

  @override
  Future<void> write(Uri uri, JsUiNetworkCacheEntry entry) async {
    await directory.create(recursive: true);
    final file = _fileFor(uri);
    await file.writeAsString(
      '${const JsonEncoder.withIndent('  ').convert(<String, Object?>{'uri': uri.toString(), 'etag': entry.etag, 'cachedAt': entry.cachedAt.toIso8601String(), 'body': entry.body})}\n',
    );
  }

  File _fileFor(Uri uri) {
    final key = sha256.convert(utf8.encode(uri.toString())).toString();
    return File('${directory.path}${Platform.pathSeparator}$key.json');
  }
}
