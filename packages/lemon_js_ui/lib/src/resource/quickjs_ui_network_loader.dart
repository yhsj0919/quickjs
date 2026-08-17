import 'dart:convert';

import 'package:http/http.dart' as http;

import 'quickjs_ui_bundle.dart';
import 'quickjs_ui_manifest.dart';
import 'quickjs_ui_network_cache_store.dart';

// ignore_for_file: prefer_initializing_formals

/// Fetches one text resource for a [JsUiNetworkLoader].
typedef JsUiNetworkFetch =
    Future<JsUiNetworkResponse> Function(JsUiNetworkRequest request);

/// Receives request, response, and cache diagnostic events.
typedef JsUiNetworkLogHandler = void Function(JsUiNetworkLogEvent event);

/// Produces the query value used to bypass caches during forced refresh.
typedef JsUiNetworkCacheBuster = String Function(Uri uri);

const _httpHeaderIfNoneMatch = 'if-none-match';
const _httpHeaderEtag = 'etag';
const _httpStatusNotModified = 304;

/// quickjs_ui 网络加载失败时抛出的异常。
final class JsUiNetworkException implements Exception {
  /// Creates a network loading failure, optionally associated with [uri].
  const JsUiNetworkException(this.message, {this.uri});

  /// Human-readable failure description.
  final String message;

  /// Resource URI associated with the failure.
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

/// Controls how package resources interact with the network cache.
enum JsUiNetworkRefreshMode {
  /// Revalidates cached resources with their ETag when available.
  conditional,

  /// Fetches from a cache-busted URI without conditional headers.
  force,

  /// Returns cached content immediately and refreshes it in the background.
  staleWhileRevalidate,
}

/// A structured network loader diagnostic event.
final class JsUiNetworkLogEvent {
  /// Creates a network diagnostic event.
  const JsUiNetworkLogEvent({
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

  /// Identifier correlating events from the same request.
  final String? id;

  /// Event type, such as `network.request` or `network.cacheHit`.
  final String type;

  /// Requested resource URI.
  final Uri uri;

  /// HTTP method when applicable.
  final String? method;

  /// HTTP response status when available.
  final int? statusCode;

  /// Entity tag sent or received by the request.
  final String? etag;

  /// Whether the reported body came from a cache.
  final bool fromCache;

  /// Elapsed request time in milliseconds.
  final int? durationMs;

  /// UTF-8 body size in bytes.
  final int? bodyBytes;

  /// Text of a request failure.
  final String? error;

  /// Time at which the event occurred.
  final DateTime? timestamp;
}

/// A text resource request issued by [JsUiNetworkLoader].
final class JsUiNetworkRequest {
  /// Creates a resource request.
  const JsUiNetworkRequest({
    required this.uri,
    this.headers = const <String, String>{},
  });

  /// URI passed to the fetch implementation.
  final Uri uri;

  /// Request headers, including conditional headers when applicable.
  final Map<String, String> headers;
}

/// A text response returned by [JsUiNetworkFetch].
final class JsUiNetworkResponse {
  /// Creates a text response.
  const JsUiNetworkResponse({
    required this.body,
    this.statusCode = 200,
    this.headers = const <String, String>{},
  });

  /// Decoded response body.
  final String body;

  /// HTTP-compatible status code.
  final int statusCode;

  /// Response headers.
  final Map<String, String> headers;
}

/// Loads JavaScript UI bundles and manifest packages over HTTP.
final class JsUiNetworkLoader {
  /// Creates a loader with optional fetching, caching, and logging hooks.
  JsUiNetworkLoader({
    JsUiNetworkFetch? fetch,
    Map<Uri, JsUiNetworkCacheEntry>? cache,
    JsUiNetworkCacheStore? cacheStore,
    JsUiNetworkLogHandler? onLog,
    JsUiNetworkCacheBuster? cacheBuster,
  }) : _fetch = fetch,
       _cache = cache ?? <Uri, JsUiNetworkCacheEntry>{},
       _cacheStore = cacheStore,
       _onLog = onLog,
       _cacheBuster = cacheBuster;

  final JsUiNetworkFetch? _fetch;
  final Map<Uri, JsUiNetworkCacheEntry> _cache;
  final JsUiNetworkCacheStore? _cacheStore;
  final JsUiNetworkLogHandler? _onLog;
  final JsUiNetworkCacheBuster? _cacheBuster;
  int _nextEventId = 0;

  /// Recursively loads an entry module and its relative static imports.
  ///
  /// Imports that escape [bundleRoot] are rejected. When [bundleRoot] is
  /// omitted, a root is inferred from [url].
  Future<JsUiBundle> load({
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
      final request = JsUiNetworkRequest(
        uri: normalizedUrl,
        headers: <String, String>{
          if (cached?.etag != null) _httpHeaderIfNoneMatch: cached!.etag!,
        },
      );
      _log(
        JsUiNetworkLogEvent(
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
          JsUiNetworkLogEvent(
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
            throw JsUiNetworkException(
              'quickjs_ui network resource returned 304 without cache',
              uri: normalizedUrl,
            );
          }
          _log(
            JsUiNetworkLogEvent(
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
          for (final importPath in jsUiStaticImports(cached.body)) {
            if (!jsUiIsRelativeImport(importPath)) {
              continue;
            }
            await visit(normalizedUrl.resolve(importPath));
          }
          return;
        }
        if (response.statusCode < 200 || response.statusCode >= 300) {
          throw JsUiNetworkException(
            'quickjs_ui network resource failed with ${response.statusCode}',
            uri: normalizedUrl,
          );
        }
        final path = _relativePath(root, normalizedUrl);
        modules[path] = response.body;
        await _storeEntry(
          normalizedUrl,
          JsUiNetworkCacheEntry(body: response.body, etag: etag),
        );
        _log(
          JsUiNetworkLogEvent(
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
        for (final importPath in jsUiStaticImports(response.body)) {
          if (!jsUiIsRelativeImport(importPath)) {
            continue;
          }
          await visit(normalizedUrl.resolve(importPath));
        }
      } catch (error) {
        stopwatch.stop();
        _log(
          JsUiNetworkLogEvent(
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
    return JsUiBundle(
      id: id ?? _bundleIdFromUrl(url),
      version: version,
      entry: _relativePath(root, url.normalizePath()),
      modules: Map<String, String>.unmodifiable(modules),
    );
  }

  /// Loads a manifest package using the selected cache refresh behavior.
  Future<JsUiBundle> loadPackage({
    required Uri root,
    JsUiNetworkRefreshMode refreshMode = JsUiNetworkRefreshMode.conditional,
  }) async {
    final packageRoot = _normalizePackageRoot(root);
    final manifestUri = packageRoot.resolve(jsUiPackageManifest);
    final manifestSource = await _loadText(
      manifestUri,
      refreshMode: refreshMode,
    );
    final manifest = JsUiManifest.parse(manifestSource)..validatePackageRoot();
    final modules = <String, String>{};
    for (final module in manifest.modules.entries) {
      final moduleUri = packageRoot.resolve(module.value.loadPath);
      final moduleSource = await _loadText(moduleUri, refreshMode: refreshMode);
      module.value.verifySource(moduleSource);
      modules[module.key] = moduleSource;
    }
    manifest.validateImports(modules);
    return JsUiBundle(
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
    JsUiNetworkRefreshMode refreshMode = JsUiNetworkRefreshMode.conditional,
  }) async {
    final normalizedUri = uri.normalizePath();
    final cached = await _cachedEntry(normalizedUri);
    if (refreshMode == JsUiNetworkRefreshMode.staleWhileRevalidate &&
        cached != null) {
      _log(
        JsUiNetworkLogEvent(
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
      refreshMode: JsUiNetworkRefreshMode.conditional,
    ).catchError((Object _) {
      return '';
    });
  }

  Future<String> _fetchText(
    Uri normalizedUri, {
    required JsUiNetworkRefreshMode refreshMode,
  }) async {
    final cached = await _cachedEntry(normalizedUri);
    final eventId = _nextLogId();
    final startedAt = DateTime.now();
    final stopwatch = Stopwatch()..start();
    final requestUri = _requestUri(normalizedUri, refreshMode: refreshMode);
    final request = JsUiNetworkRequest(
      uri: requestUri,
      headers: <String, String>{
        if (refreshMode != JsUiNetworkRefreshMode.force && cached?.etag != null)
          _httpHeaderIfNoneMatch: cached!.etag!,
      },
    );
    _log(
      JsUiNetworkLogEvent(
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
        JsUiNetworkLogEvent(
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
          throw JsUiNetworkException(
            'quickjs_ui network resource returned 304 without cache',
            uri: normalizedUri,
          );
        }
        _log(
          JsUiNetworkLogEvent(
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
        throw JsUiNetworkException(
          'quickjs_ui network resource failed with ${response.statusCode}',
          uri: normalizedUri,
        );
      }
      await _storeEntry(
        normalizedUri,
        JsUiNetworkCacheEntry(body: response.body, etag: etag),
      );
      _log(
        JsUiNetworkLogEvent(
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
        JsUiNetworkLogEvent(
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

  Future<JsUiNetworkCacheEntry?> _cachedEntry(Uri uri) async {
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

  Future<void> _storeEntry(Uri uri, JsUiNetworkCacheEntry entry) async {
    _cache[uri] = entry;
    await _cacheStore?.write(uri, entry);
  }

  void _log(JsUiNetworkLogEvent event) {
    _onLog?.call(event);
  }

  String _nextLogId() {
    _nextEventId += 1;
    return 'bundle-$_nextEventId';
  }

  Uri _requestUri(Uri uri, {required JsUiNetworkRefreshMode refreshMode}) {
    if (refreshMode != JsUiNetworkRefreshMode.force || _cacheBuster == null) {
      return uri;
    }
    final queryParameters = Map<String, String>.from(uri.queryParameters);
    queryParameters['_quickjs_ui_cache_bust'] = _cacheBuster(uri);
    return uri.replace(queryParameters: queryParameters);
  }
}

Future<JsUiNetworkResponse> _defaultFetch(
  JsUiNetworkRequest fetchRequest,
) async {
  final response = await http.get(
    fetchRequest.uri,
    headers: fetchRequest.headers,
  );
  return JsUiNetworkResponse(
    body: utf8.decode(response.bodyBytes),
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
