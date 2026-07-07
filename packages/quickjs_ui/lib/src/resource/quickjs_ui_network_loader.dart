import 'dart:convert';

import 'package:http/http.dart' as http;

import 'quickjs_ui_bundle.dart';
import 'quickjs_ui_manifest.dart';
import 'quickjs_ui_network_cache_store.dart';

// ignore_for_file: prefer_initializing_formals

typedef QuickjsUiNetworkFetch =
    Future<QuickjsUiNetworkResponse> Function(QuickjsUiNetworkRequest request);
typedef QuickjsUiNetworkLogHandler =
    void Function(QuickjsUiNetworkLogEvent event);
typedef QuickjsUiNetworkCacheBuster = String Function(Uri uri);

const _httpHeaderIfNoneMatch = 'if-none-match';
const _httpHeaderEtag = 'etag';
const _httpStatusNotModified = 304;

/// quickjs_ui 网络加载失败时抛出的异常。
final class QuickjsUiNetworkException implements Exception {
  const QuickjsUiNetworkException(this.message, {this.uri});

  final String message;
  final Uri? uri;

  @override
  String toString() {
    final uri = this.uri;
    if (uri == null) {
      return message;
    }
    return '$message ($uri)';
  }
}

enum QuickjsUiNetworkRefreshMode { conditional, force, staleWhileRevalidate }

final class QuickjsUiNetworkLogEvent {
  const QuickjsUiNetworkLogEvent({
    this.id,
    required this.type,
    required this.uri,
    this.method,
    this.statusCode,
    this.etag,
    this.fromCache = false,
    this.durationMs,
    this.bodyBytes,
    this.error,
    this.timestamp,
  });

  final String? id;
  final String type;
  final Uri uri;
  final String? method;
  final int? statusCode;
  final String? etag;
  final bool fromCache;
  final int? durationMs;
  final int? bodyBytes;
  final String? error;
  final DateTime? timestamp;
}

final class QuickjsUiNetworkRequest {
  const QuickjsUiNetworkRequest({
    required this.uri,
    this.headers = const <String, String>{},
  });

  final Uri uri;
  final Map<String, String> headers;
}

final class QuickjsUiNetworkResponse {
  const QuickjsUiNetworkResponse({
    required this.body,
    this.statusCode = 200,
    this.headers = const <String, String>{},
  });

  final String body;
  final int statusCode;
  final Map<String, String> headers;
}

final class QuickjsUiNetworkLoader {
  QuickjsUiNetworkLoader({
    QuickjsUiNetworkFetch? fetch,
    Map<Uri, QuickjsUiNetworkCacheEntry>? cache,
    QuickjsUiNetworkCacheStore? cacheStore,
    QuickjsUiNetworkLogHandler? onLog,
    QuickjsUiNetworkCacheBuster? cacheBuster,
  }) : _fetch = fetch,
       _cache = cache ?? <Uri, QuickjsUiNetworkCacheEntry>{},
       _cacheStore = cacheStore,
       _onLog = onLog,
       _cacheBuster = cacheBuster;

  final QuickjsUiNetworkFetch? _fetch;
  final Map<Uri, QuickjsUiNetworkCacheEntry> _cache;
  final QuickjsUiNetworkCacheStore? _cacheStore;
  final QuickjsUiNetworkLogHandler? _onLog;
  final QuickjsUiNetworkCacheBuster? _cacheBuster;
  int _nextEventId = 0;

  Future<QuickjsUiBundle> load({
    required Uri url,
    String? id,
    String version = '0.2.0',
    Uri? bundleRoot,
  }) async {
    final root = bundleRoot ?? _inferNetworkRoot(url);
    final modules = <String, String>{};
    final visited = <Uri>{};

    Future<void> visit(Uri moduleUrl) async {
      final normalizedUrl = moduleUrl.normalizePath();
      if (!normalizedUrl.toString().startsWith(root.toString())) {
        throw FormatException(
          'quickjs_ui network import escapes bundle root: $normalizedUrl',
        );
      }
      if (!visited.add(normalizedUrl)) {
        return;
      }
      final cached = await _cachedEntry(normalizedUrl);
      final eventId = _nextLogId();
      final startedAt = DateTime.now();
      final stopwatch = Stopwatch()..start();
      final request = QuickjsUiNetworkRequest(
        uri: normalizedUrl,
        headers: <String, String>{
          if (cached?.etag != null)
            _httpHeaderIfNoneMatch: cached!.etag!,
        },
      );
      _log(
        QuickjsUiNetworkLogEvent(
          id: eventId,
          type: 'network.request',
          uri: normalizedUrl,
          method: 'GET',
          etag: cached?.etag,
          timestamp: startedAt,
        ),
      );
      try {
        final response = await (_fetch ?? _defaultFetch)(request);
        stopwatch.stop();
        final etag = _header(response.headers, _httpHeaderEtag);
        _log(
          QuickjsUiNetworkLogEvent(
            id: eventId,
            type: 'network.response',
            uri: normalizedUrl,
            method: 'GET',
            statusCode: response.statusCode,
            etag: etag,
            durationMs: stopwatch.elapsedMilliseconds,
            bodyBytes: utf8.encode(response.body).length,
            timestamp: DateTime.now(),
          ),
        );
        if (response.statusCode == _httpStatusNotModified) {
          if (cached == null) {
            throw QuickjsUiNetworkException(
              'quickjs_ui network resource returned 304 without cache',
              uri: normalizedUrl,
            );
          }
          _log(
            QuickjsUiNetworkLogEvent(
              id: eventId,
              type: 'network.cacheHit',
              uri: normalizedUrl,
              method: 'GET',
              statusCode: response.statusCode,
              etag: cached.etag,
              fromCache: true,
              durationMs: stopwatch.elapsedMilliseconds,
              bodyBytes: utf8.encode(cached.body).length,
              timestamp: DateTime.now(),
            ),
          );
          final path = _relativePath(root, normalizedUrl);
          modules[path] = cached.body;
          for (final importPath in quickjsUiStaticImports(cached.body)) {
            if (!quickjsUiIsRelativeImport(importPath)) {
              continue;
            }
            await visit(normalizedUrl.resolve(importPath));
          }
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw QuickjsUiNetworkException(
            'quickjs_ui network resource failed with ${response.statusCode}',
            uri: normalizedUrl,
          );
        }
        final path = _relativePath(root, normalizedUrl);
        modules[path] = response.body;
        await _storeEntry(
          normalizedUrl,
          QuickjsUiNetworkCacheEntry(body: response.body, etag: etag),
        );
        _log(
          QuickjsUiNetworkLogEvent(
            id: eventId,
            type: 'network.cacheStore',
            uri: normalizedUrl,
            method: 'GET',
            statusCode: response.statusCode,
            etag: etag,
            durationMs: stopwatch.elapsedMilliseconds,
            bodyBytes: utf8.encode(response.body).length,
            timestamp: DateTime.now(),
          ),
        );
        for (final importPath in quickjsUiStaticImports(response.body)) {
          if (!quickjsUiIsRelativeImport(importPath)) {
            continue;
          }
          await visit(normalizedUrl.resolve(importPath));
        }
      } catch (error) {
        stopwatch.stop();
        _log(
          QuickjsUiNetworkLogEvent(
            id: eventId,
            type: 'network.response',
            uri: normalizedUrl,
            method: 'GET',
            durationMs: stopwatch.elapsedMilliseconds,
            error: '$error',
            timestamp: DateTime.now(),
          ),
        );
        rethrow;
      }
    }

    await visit(url);
    return QuickjsUiBundle(
      id: id ?? _bundleIdFromUrl(url),
      version: version,
      entry: _relativePath(root, url.normalizePath()),
      modules: Map<String, String>.unmodifiable(modules),
    );
  }

  Future<QuickjsUiBundle> loadPackage({required Uri root}) async {
    return loadPackageWithRefresh(
      root: root,
      refreshMode: QuickjsUiNetworkRefreshMode.conditional,
    );
  }

  Future<QuickjsUiBundle> loadPackageWithRefresh({
    required Uri root,
    QuickjsUiNetworkRefreshMode refreshMode =
        QuickjsUiNetworkRefreshMode.conditional,
  }) async {
    final packageRoot = _normalizePackageRoot(root);
    final manifestUri = packageRoot.resolve(quickjsUiPackageManifest);
    final manifestSource = await _loadText(
      manifestUri,
      refreshMode: refreshMode,
    );
    final manifest = QuickjsUiManifest.parse(manifestSource)
      ..validatePackageRoot();
    final modules = <String, String>{};
    for (final module in manifest.modules.entries) {
      final moduleUri = packageRoot.resolve(module.value.loadPath);
      final moduleSource = await _loadText(moduleUri, refreshMode: refreshMode);
      module.value.verifySource(moduleSource);
      modules[module.key] = moduleSource;
    }
    manifest.validateImports(modules);
    return QuickjsUiBundle(
      id: manifest.id,
      version: manifest.version,
      entry: manifest.entry,
      modules: Map<String, String>.unmodifiable(modules),
      permissions: manifest.permissions,
      resources: manifest.resources,
    );
  }

  Future<String> _loadText(
    Uri uri, {
    QuickjsUiNetworkRefreshMode refreshMode =
        QuickjsUiNetworkRefreshMode.conditional,
  }) async {
    final normalizedUri = uri.normalizePath();
    final cached = await _cachedEntry(normalizedUri);
    if (refreshMode == QuickjsUiNetworkRefreshMode.staleWhileRevalidate &&
        cached != null) {
      _log(
        QuickjsUiNetworkLogEvent(
          id: _nextLogId(),
          type: 'network.stale',
          uri: normalizedUri,
          method: 'GET',
          etag: cached.etag,
          fromCache: true,
          bodyBytes: utf8.encode(cached.body).length,
          timestamp: DateTime.now(),
        ),
      );
      _refreshText(normalizedUri);
      return cached.body;
    }
    return _fetchText(normalizedUri, refreshMode: refreshMode);
  }

  void _refreshText(Uri normalizedUri) {
    _fetchText(
      normalizedUri,
      refreshMode: QuickjsUiNetworkRefreshMode.conditional,
    ).catchError((Object _) {
      return '';
    });
  }

  Future<String> _fetchText(
    Uri normalizedUri, {
    required QuickjsUiNetworkRefreshMode refreshMode,
  }) async {
    final cached = await _cachedEntry(normalizedUri);
    final eventId = _nextLogId();
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestUri = _requestUri(normalizedUri, refreshMode: refreshMode);
    final request = QuickjsUiNetworkRequest(
      uri: requestUri,
      headers: <String, String>{
        if (refreshMode != QuickjsUiNetworkRefreshMode.force &&
            cached?.etag != null)
          _httpHeaderIfNoneMatch: cached!.etag!,
      },
    );
    _log(
      QuickjsUiNetworkLogEvent(
        id: eventId,
        type: 'network.request',
        uri: requestUri,
        method: 'GET',
        etag: cached?.etag,
        timestamp: startedAt,
      ),
    );
    try {
      final response = await (_fetch ?? _defaultFetch)(request);
      stopwatch.stop();
      final etag = _header(response.headers, _httpHeaderEtag);
      _log(
        QuickjsUiNetworkLogEvent(
          id: eventId,
          type: 'network.response',
          uri: requestUri,
          method: 'GET',
          statusCode: response.statusCode,
          etag: etag,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyBytes: utf8.encode(response.body).length,
          timestamp: DateTime.now(),
        ),
      );
      if (response.statusCode == _httpStatusNotModified) {
        if (cached == null) {
          throw QuickjsUiNetworkException(
            'quickjs_ui network resource returned 304 without cache',
            uri: normalizedUri,
          );
        }
        _log(
          QuickjsUiNetworkLogEvent(
            id: eventId,
            type: 'network.cacheHit',
            uri: requestUri,
            method: 'GET',
            statusCode: response.statusCode,
            etag: cached.etag,
            fromCache: true,
            durationMs: stopwatch.elapsedMilliseconds,
            bodyBytes: utf8.encode(cached.body).length,
            timestamp: DateTime.now(),
          ),
        );
        return cached.body;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw QuickjsUiNetworkException(
          'quickjs_ui network resource failed with ${response.statusCode}',
          uri: normalizedUri,
        );
      }
      await _storeEntry(
        normalizedUri,
        QuickjsUiNetworkCacheEntry(body: response.body, etag: etag),
      );
      _log(
        QuickjsUiNetworkLogEvent(
          id: eventId,
          type: 'network.cacheStore',
          uri: requestUri,
          method: 'GET',
          statusCode: response.statusCode,
          etag: etag,
          durationMs: stopwatch.elapsedMilliseconds,
          bodyBytes: utf8.encode(response.body).length,
          timestamp: DateTime.now(),
        ),
      );
      return response.body;
    } catch (error) {
      stopwatch.stop();
      _log(
        QuickjsUiNetworkLogEvent(
          id: eventId,
          type: 'network.response',
          uri: requestUri,
          method: 'GET',
          durationMs: stopwatch.elapsedMilliseconds,
          error: '$error',
          timestamp: DateTime.now(),
        ),
      );
      rethrow;
    }
  }

  Future<QuickjsUiNetworkCacheEntry?> _cachedEntry(Uri uri) async {
    final memoryEntry = _cache[uri];
    if (memoryEntry != null) {
      return memoryEntry;
    }
    final storedEntry = await _cacheStore?.read(uri);
    if (storedEntry != null) {
      _cache[uri] = storedEntry;
    }
    return storedEntry;
  }

  Future<void> _storeEntry(Uri uri, QuickjsUiNetworkCacheEntry entry) async {
    _cache[uri] = entry;
    await _cacheStore?.write(uri, entry);
  }

  void _log(QuickjsUiNetworkLogEvent event) {
    _onLog?.call(event);
  }

  String _nextLogId() {
    _nextEventId += 1;
    return 'bundle-$_nextEventId';
  }

  Uri _requestUri(Uri uri, {required QuickjsUiNetworkRefreshMode refreshMode}) {
    if (refreshMode != QuickjsUiNetworkRefreshMode.force ||
        _cacheBuster == null) {
      return uri;
    }
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    queryParameters['_quickjs_ui_cache_bust'] = _cacheBuster(uri);
    return uri.replace(queryParameters: queryParameters);
  }
}

Future<QuickjsUiNetworkResponse> _defaultFetch(
  QuickjsUiNetworkRequest fetchRequest,
) async {
  final response = await http.get(
    fetchRequest.uri,
    headers: fetchRequest.headers,
  );
  return QuickjsUiNetworkResponse(
    body: response.body,
    statusCode: response.statusCode,
    headers: Map<String, String>.from(response.headers),
  );
}

String? _header(Map<String, String> headers, String name) {
  final lowerName = name.toLowerCase();
  for (final entry in headers.entries) {
    if (entry.key.toLowerCase() == lowerName) {
      return entry.value;
    }
  }
  return null;
}

Uri _inferNetworkRoot(Uri url) {
  final path = url.path;
  final pagesIndex = path.lastIndexOf('/pages/');
  if (pagesIndex > 0) {
    return url.replace(path: path.substring(0, pagesIndex + 1));
  }
  final index = path.lastIndexOf('/');
  if (index <= 0) {
    return url.replace(path: '/');
  }
  return url.replace(path: path.substring(0, index + 1));
}

Uri _normalizePackageRoot(Uri root) {
  final text = root.toString();
  if (text.endsWith('/')) {
    return root;
  }
  return Uri.parse('$text/');
}

String _relativePath(Uri root, Uri uri) {
  final rootText = root.toString();
  final uriText = uri.toString();
  if (!uriText.startsWith(rootText)) {
    throw FormatException(
      'quickjs_ui network URL is outside bundle root: $uri',
    );
  }
  final relative = uriText.substring(rootText.length);
  if (relative.isEmpty) {
    throw FormatException('quickjs_ui network entry must not be root: $uri');
  }
  return relative;
}

String _bundleIdFromUrl(Uri url) {
  final sanitized = url
      .toString()
      .replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_')
      .replaceAll(RegExp(r'_+'), '_')
      .replaceAll(RegExp(r'^_|_$'), '');
  return 'quickjs_ui_$sanitized';
}
