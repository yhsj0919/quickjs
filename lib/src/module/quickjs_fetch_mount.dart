import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../diagnostics/quickjs_exception.dart';
import '../runtime/quickjs_runtime_options.dart';
import 'quickjs_fetch_host_script.dart';

const _fetchProviderName = 'fetch.request';

/// Opt-in Fetch API mount backed by the platform HTTP client.
///
/// Native platforms use `dart:io`'s `HttpClient` through `package:http`.
/// Web uses the browser's native `fetch`. Requests are restricted to the
/// explicit [allowedOrigins] set. Redirects follow the Fetch `redirect`
/// option (`follow` by default) and each hop must stay within
/// [allowedOrigins].
///
/// The embedded host script installs `fetch`, `Request`, `Response`,
/// `Headers`, `AbortController`, `FormData`, `URLSearchParams`, `Blob`,
/// `ReadableStream`, and a fetch-backed `XMLHttpRequest` compatibility
/// layer. XHR uses `onload` / `onerror` property callbacks; it does not
/// implement `addEventListener`.
final class QuickjsFetchMount extends QuickjsHostMount {
  factory QuickjsFetchMount({
    required Set<String> allowedOrigins,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 1024 * 1024,
    int maxResponseBytes = 10 * 1024 * 1024,
    int maxRedirects = 20,
  }) {
    if (allowedOrigins.isEmpty) {
      throw ArgumentError.value(
        allowedOrigins,
        'allowedOrigins',
        'QuickjsFetchMount requires at least one allowed HTTP(S) origin',
      );
    }
    if (timeout <= Duration.zero) {
      throw ArgumentError.value(timeout, 'timeout', 'must be positive');
    }
    if (maxRequestBytes < 0) {
      throw ArgumentError.value(
        maxRequestBytes,
        'maxRequestBytes',
        'must not be negative',
      );
    }
    if (maxResponseBytes < 0) {
      throw ArgumentError.value(
        maxResponseBytes,
        'maxResponseBytes',
        'must not be negative',
      );
    }
    if (maxRedirects < 0) {
      throw ArgumentError.value(
        maxRedirects,
        'maxRedirects',
        'must not be negative',
      );
    }

    final origins = Set<String>.unmodifiable(
      allowedOrigins.map(_normalizeAllowedOrigin),
    );
    final provider = QuickjsHostProvider.async(
      name: _fetchProviderName,
      debugName: 'host:fetch.request',
      implementation: QuickjsHostProviderImplementation.platform,
      callback: (args, context) => _sendFetchRequest(
        args,
        context,
        allowedOrigins: origins,
        timeout: timeout,
        maxRequestBytes: maxRequestBytes,
        maxResponseBytes: maxResponseBytes,
        maxRedirects: maxRedirects,
      ),
    );
    return QuickjsFetchMount._(
      allowedOrigins: origins,
      timeout: timeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      maxRedirects: maxRedirects,
      provider: provider,
    );
  }

  QuickjsFetchMount._({
    required this.allowedOrigins,
    required this.timeout,
    required this.maxRequestBytes,
    required this.maxResponseBytes,
    required this.maxRedirects,
    required QuickjsHostProvider provider,
  }) : super(
         name: 'fetch',
         environmentPatches: <QuickjsHostScript>[
           QuickjsHostScript(
             name: 'host:fetch.js',
             globals: const <String>[
               'fetch',
               'Headers',
               'Request',
               'Response',
               'AbortController',
               'AbortSignal',
               'FormData',
               'URLSearchParams',
               'Blob',
               'ReadableStream',
               'XMLHttpRequest',
             ],
             source: quickjsFetchHostScript(_fetchProviderName),
           ),
         ],
         providers: <QuickjsHostProvider>[provider],
       );

  /// Exact normalized HTTP(S) origins this mount may access.
  final Set<String> allowedOrigins;

  /// Maximum duration for request headers and response body consumption.
  final Duration timeout;

  /// Maximum encoded request body size.
  final int maxRequestBytes;

  /// Maximum streamed response body size.
  final int maxResponseBytes;

  /// Maximum redirect hops when `redirect` is `follow`.
  final int maxRedirects;
}

Future<Object?> _sendFetchRequest(
  List<Object?> args,
  QuickjsHostProviderContext context, {
  required Set<String> allowedOrigins,
  required Duration timeout,
  required int maxRequestBytes,
  required int maxResponseBytes,
  required int maxRedirects,
}) async {
  if (args.length != 1 || args.single is! Map) {
    throw const JsValueConversionException(
      'QuickJS fetch provider expects one request object',
    );
  }
  final payload = Map<Object?, Object?>.from(args.single! as Map);
  final redirectMode = _normalizeRedirectMode(payload['redirect']);
  var uri = _parseRequestUri('${payload['url'] ?? ''}');
  _ensureOriginAllowed(uri, allowedOrigins);

  var method = '${payload['method'] ?? 'GET'}'.toUpperCase();
  if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Z-]+$").hasMatch(method)) {
    throw JsValueConversionException('QuickJS fetch method is invalid');
  }
  var headers = _normalizeRequestHeaders(payload['headers']);
  var body = _normalizeRequestBody(payload['body']);
  if (body.length > maxRequestBytes) {
    throw JsValueConversionException(
      'QuickJS fetch request body exceeds $maxRequestBytes bytes',
    );
  }
  if (body.isNotEmpty && (method == 'GET' || method == 'HEAD')) {
    throw JsValueConversionException(
      'QuickJS fetch $method request cannot have a body',
    );
  }

  final client = http.Client();
  unawaited(context.cancelled.then((_) => client.close()));
  try {
    var redirected = false;
    var redirectCount = 0;
    while (true) {
      context.throwIfCancelled();
      final request = http.Request(method, uri)
        // Keep package:http from auto-following redirects. Redirect hops are
        // handled manually so each target can be checked against
        // [allowedOrigins] and Fetch redirect semantics can be applied.
        ..followRedirects = false
        ..persistentConnection = false
        ..headers.addAll(headers);
      if (body.isNotEmpty) {
        request.bodyBytes = body;
      }
      final response = await client.send(request).timeout(timeout);
      final statusCode = response.statusCode;
      if (statusCode >= 300 && statusCode < 400) {
        if (redirectMode == 'manual') {
          return await _readFetchResponse(
            response,
            uri,
            redirected: redirected,
            maxResponseBytes: maxResponseBytes,
            timeout: timeout,
            context: context,
          );
        }
        if (redirectMode == 'error') {
          await response.stream.drain();
          throw StateError(
            'QuickJS fetch redirect encountered with redirect=error',
          );
        }
        if (redirectCount >= maxRedirects) {
          await response.stream.drain();
          throw StateError(
            'QuickJS fetch exceeded max redirects ($maxRedirects)',
          );
        }
        final location = response.headers['location'];
        if (location == null || location.trim().isEmpty) {
          await response.stream.drain();
          throw StateError(
            'QuickJS fetch redirect response missing Location header',
          );
        }
        await response.stream.drain();
        uri = _resolveRedirectUri(uri, location.trim());
        _ensureOriginAllowed(uri, allowedOrigins);
        if (statusCode == 301 || statusCode == 302 || statusCode == 303) {
          method = 'GET';
          body = Uint8List(0);
          headers = Map<String, String>.from(headers)
            ..remove('content-length')
            ..remove('content-type');
        }
        redirected = true;
        redirectCount++;
        continue;
      }

      return await _readFetchResponse(
        response,
        uri,
        redirected: redirected,
        maxResponseBytes: maxResponseBytes,
        timeout: timeout,
        context: context,
      );
    }
  } on TimeoutException {
    throw StateError('QuickJS fetch timed out after $timeout');
  } finally {
    client.close();
  }
}

Future<Map<String, Object?>> _readFetchResponse(
  http.StreamedResponse response,
  Uri url, {
  required bool redirected,
  required int maxResponseBytes,
  required Duration timeout,
  required QuickjsHostProviderContext context,
}) async {
  final contentLength = response.contentLength;
  if (contentLength != null && contentLength > maxResponseBytes) {
    throw StateError(
      'QuickJS fetch response exceeds $maxResponseBytes bytes',
    );
  }

  final builder = BytesBuilder(copy: false);
  await response.stream.timeout(timeout).forEach((chunk) {
    context.throwIfCancelled();
    if (builder.length + chunk.length > maxResponseBytes) {
      throw StateError(
        'QuickJS fetch response exceeds $maxResponseBytes bytes',
      );
    }
    builder.add(chunk);
  });
  context.throwIfCancelled();
  return <String, Object?>{
    'status': response.statusCode,
    'statusText': response.reasonPhrase ?? '',
    'url': response.request?.url.toString() ?? url.toString(),
    'headers': response.headers,
    'body': builder.takeBytes(),
    'redirected': redirected,
  };
}

Uri _parseRequestUri(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw JsValueConversionException(
      'QuickJS fetch URL must be an absolute HTTP(S) URL',
    );
  }
  return uri;
}

void _ensureOriginAllowed(Uri uri, Set<String> allowedOrigins) {
  if (!allowedOrigins.contains(uri.origin)) {
    throw JsValueConversionException(
      'QuickJS fetch origin is not allowed: ${uri.origin}',
    );
  }
}

String _normalizeRedirectMode(Object? value) {
  return switch ('$value'.toLowerCase()) {
    'error' => 'error',
    'manual' => 'manual',
    _ => 'follow',
  };
}

Uri _resolveRedirectUri(Uri base, String location) {
  final target = Uri.tryParse(location);
  if (target == null) {
    throw JsValueConversionException(
      'QuickJS fetch redirect Location header is invalid',
    );
  }
  final resolved = target.hasScheme ? target : base.resolveUri(target);
  if ((resolved.scheme != 'http' && resolved.scheme != 'https') ||
      resolved.host.isEmpty ||
      resolved.userInfo.isNotEmpty) {
    throw JsValueConversionException(
      'QuickJS fetch redirect URL must be an absolute HTTP(S) URL',
    );
  }
  return resolved;
}

Map<String, String> _normalizeRequestHeaders(Object? value) {
  if (value == null) {
    return <String, String>{};
  }
  if (value is! Map) {
    throw const JsValueConversionException(
      'QuickJS fetch headers must be an object',
    );
  }
  const forbidden = <String>{
    'connection',
    'content-length',
    'host',
    'transfer-encoding',
  };
  final headers = <String, String>{};
  for (final entry in value.entries) {
    final name = '${entry.key}'.trim().toLowerCase();
    if (name.isEmpty || forbidden.contains(name)) {
      throw JsValueConversionException(
        'QuickJS fetch header is not allowed: $name',
      );
    }
    headers[name] = '${entry.value}';
  }
  return headers;
}

Uint8List _normalizeRequestBody(Object? value) {
  return switch (value) {
    null => Uint8List(0),
    String text => Uint8List.fromList(utf8.encode(text)),
    Uint8List bytes => bytes,
    _ => throw const JsValueConversionException(
      'QuickJS fetch body must be a string, ArrayBuffer, or Uint8Array',
    ),
  };
}

String _normalizeAllowedOrigin(String value) {
  final uri = Uri.tryParse(value);
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty ||
      (uri.path.isNotEmpty && uri.path != '/') ||
      uri.hasQuery ||
      uri.hasFragment) {
    throw ArgumentError.value(
      value,
      'allowedOrigins',
      'must contain exact HTTP(S) origins such as https://api.example.com',
    );
  }
  return uri.origin;
}
