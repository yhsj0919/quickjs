import 'dart:convert';
import 'dart:io';

import 'quickjs_ui_bundle.dart';

// ignore_for_file: prefer_initializing_formals

typedef QuickjsUiNetworkFetch =
    Future<QuickjsUiNetworkResponse> Function(QuickjsUiNetworkRequest request);
typedef QuickjsUiNetworkLogHandler =
    void Function(QuickjsUiNetworkLogEvent event);

final class QuickjsUiNetworkLogEvent {
  const QuickjsUiNetworkLogEvent({
    required this.type,
    required this.uri,
    this.statusCode,
    this.etag,
    this.fromCache = false,
  });

  final String type;
  final Uri uri;
  final int? statusCode;
  final String? etag;
  final bool fromCache;
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
    QuickjsUiNetworkLogHandler? onLog,
  }) : _fetch = fetch,
       _cache = cache ?? <Uri, QuickjsUiNetworkCacheEntry>{},
       _onLog = onLog;

  final QuickjsUiNetworkFetch? _fetch;
  final Map<Uri, QuickjsUiNetworkCacheEntry> _cache;
  final QuickjsUiNetworkLogHandler? _onLog;

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
      final cached = _cache[normalizedUrl];
      final request = QuickjsUiNetworkRequest(
        uri: normalizedUrl,
        headers: <String, String>{
          if (cached?.etag != null)
            HttpHeaders.ifNoneMatchHeader: cached!.etag!,
        },
      );
      _log(
        QuickjsUiNetworkLogEvent(
          type: 'network.request',
          uri: normalizedUrl,
          etag: cached?.etag,
        ),
      );
      final response = await (_fetch ?? _defaultFetch)(request);
      final etag = _header(response.headers, HttpHeaders.etagHeader);
      _log(
        QuickjsUiNetworkLogEvent(
          type: 'network.response',
          uri: normalizedUrl,
          statusCode: response.statusCode,
          etag: etag,
        ),
      );
      if (response.statusCode == HttpStatus.notModified) {
        if (cached == null) {
          throw HttpException(
            'quickjs_ui network resource returned 304 without cache',
            uri: normalizedUrl,
          );
        }
        _log(
          QuickjsUiNetworkLogEvent(
            type: 'network.cacheHit',
            uri: normalizedUrl,
            statusCode: response.statusCode,
            etag: cached.etag,
            fromCache: true,
          ),
        );
        final path = _relativePath(root, normalizedUrl);
        modules[path] = cached.body;
        for (final importPath in _staticImports(cached.body)) {
          if (!_isRelativeImport(importPath)) {
            continue;
          }
          await visit(normalizedUrl.resolve(importPath));
        }
        return;
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw HttpException(
          'quickjs_ui network resource failed with ${response.statusCode}',
          uri: normalizedUrl,
        );
      }
      final path = _relativePath(root, normalizedUrl);
      modules[path] = response.body;
      _cache[normalizedUrl] = QuickjsUiNetworkCacheEntry(
        body: response.body,
        etag: etag,
      );
      _log(
        QuickjsUiNetworkLogEvent(
          type: 'network.cacheStore',
          uri: normalizedUrl,
          statusCode: response.statusCode,
          etag: etag,
        ),
      );
      for (final importPath in _staticImports(response.body)) {
        if (!_isRelativeImport(importPath)) {
          continue;
        }
        await visit(normalizedUrl.resolve(importPath));
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

  void _log(QuickjsUiNetworkLogEvent event) {
    _onLog?.call(event);
  }
}

final class QuickjsUiNetworkCacheEntry {
  const QuickjsUiNetworkCacheEntry({required this.body, this.etag});

  final String body;
  final String? etag;
}

Future<QuickjsUiNetworkResponse> _defaultFetch(
  QuickjsUiNetworkRequest fetchRequest,
) async {
  final client = HttpClient();
  try {
    final request = await client.getUrl(fetchRequest.uri);
    for (final header in fetchRequest.headers.entries) {
      request.headers.set(header.key, header.value);
    }
    final response = await request.close();
    final body = await response.transform(utf8.decoder).join();
    final headers = <String, String>{};
    response.headers.forEach((name, values) {
      headers[name] = values.join(',');
    });
    return QuickjsUiNetworkResponse(
      body: body,
      statusCode: response.statusCode,
      headers: headers,
    );
  } finally {
    client.close(force: true);
  }
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

Iterable<String> _staticImports(String source) sync* {
  final patterns = <RegExp>[
    RegExp(
      r'''import\s+(?:[^'"]*?\s+from\s+)?["']([^"']+)["']''',
      multiLine: true,
    ),
    RegExp(r'''export\s+[^'"]*?\s+from\s+["']([^"']+)["']''', multiLine: true),
  ];
  for (final pattern in patterns) {
    for (final match in pattern.allMatches(source)) {
      final specifier = match.group(1);
      if (specifier != null && specifier.isNotEmpty) {
        yield specifier;
      }
    }
  }
}

bool _isRelativeImport(String specifier) {
  return specifier.startsWith('./') || specifier.startsWith('../');
}
