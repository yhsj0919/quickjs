import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';

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
  const QuickjsUiFileNetworkCacheStore({required this.directory});

  final Directory directory;

  @override
  Future<QuickjsUiNetworkCacheEntry?> read(Uri uri) async {
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
    return QuickjsUiNetworkCacheEntry(
      body: body,
      etag: etag is String ? etag : null,
      cachedAt: cachedAt is String ? DateTime.tryParse(cachedAt) : null,
    );
  }

  @override
  Future<void> write(Uri uri, QuickjsUiNetworkCacheEntry entry) async {
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
