import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../diagnostics/quickjs_exception.dart';
import '../runtime/quickjs_runtime_options.dart';

const _fetchProviderName = 'fetch.request';

/// Opt-in Fetch API mount backed by the platform HTTP client.
///
/// Native platforms use `dart:io`'s `HttpClient` through `package:http`.
/// Web uses the browser's native `fetch`. Requests are restricted to the
/// explicit [allowedOrigins] set and redirects are rejected.
final class QuickjsFetchMount extends QuickjsHostMount {
  factory QuickjsFetchMount({
    required Set<String> allowedOrigins,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 1024 * 1024,
    int maxResponseBytes = 10 * 1024 * 1024,
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
      ),
    );
    return QuickjsFetchMount._(
      allowedOrigins: origins,
      timeout: timeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      provider: provider,
    );
  }

  QuickjsFetchMount._({
    required this.allowedOrigins,
    required this.timeout,
    required this.maxRequestBytes,
    required this.maxResponseBytes,
    required QuickjsHostProvider provider,
  }) : super(
         name: 'fetch',
         environmentPatches: <QuickjsHostScript>[
           QuickjsHostScript(
             name: 'host:fetch.js',
             globals: const <String>['fetch', 'Headers', 'Response'],
             source: _fetchHostScript(_fetchProviderName),
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
}

Future<Object?> _sendFetchRequest(
  List<Object?> args,
  QuickjsHostProviderContext context, {
  required Set<String> allowedOrigins,
  required Duration timeout,
  required int maxRequestBytes,
  required int maxResponseBytes,
}) async {
  if (args.length != 1 || args.single is! Map) {
    throw const JsValueConversionException(
      'QuickJS fetch provider expects one request object',
    );
  }
  final payload = Map<Object?, Object?>.from(args.single! as Map);
  final uri = Uri.tryParse('${payload['url'] ?? ''}');
  if (uri == null ||
      (uri.scheme != 'http' && uri.scheme != 'https') ||
      uri.host.isEmpty ||
      uri.userInfo.isNotEmpty) {
    throw JsValueConversionException(
      'QuickJS fetch URL must be an absolute HTTP(S) URL',
    );
  }
  if (!allowedOrigins.contains(uri.origin)) {
    throw JsValueConversionException(
      'QuickJS fetch origin is not allowed: ${uri.origin}',
    );
  }

  final method = '${payload['method'] ?? 'GET'}'.toUpperCase();
  if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Z-]+$").hasMatch(method)) {
    throw JsValueConversionException('QuickJS fetch method is invalid');
  }
  final headers = _normalizeRequestHeaders(payload['headers']);
  final body = _normalizeRequestBody(payload['body']);
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
    context.throwIfCancelled();
    final request = http.Request(method, uri)
      ..followRedirects = false
      ..persistentConnection = false
      ..headers.addAll(headers);
    if (body.isNotEmpty) {
      request.bodyBytes = body;
    }
    final response = await client.send(request).timeout(timeout);
    if (response.statusCode >= 300 && response.statusCode < 400) {
      throw StateError('QuickJS fetch redirects are disabled');
    }
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
        client.close();
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
      'url': response.request?.url.toString() ?? uri.toString(),
      'headers': response.headers,
      'body': builder.takeBytes(),
    };
  } on TimeoutException {
    client.close();
    throw StateError('QuickJS fetch timed out after $timeout');
  } finally {
    client.close();
  }
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

String _fetchHostScript(String providerName) {
  final encodedProviderName = jsonEncode(providerName);
  return '''
(() => {
  const provider = globalThis.__quickjsHostProviders[$encodedProviderName];

  const decodeUtf8 = (bytes) => {
    let result = '';
    for (let i = 0; i < bytes.length;) {
      const first = bytes[i++];
      if (first < 0x80) {
        result += String.fromCharCode(first);
        continue;
      }
      let needed;
      let code;
      if ((first & 0xe0) === 0xc0) { needed = 1; code = first & 0x1f; }
      else if ((first & 0xf0) === 0xe0) { needed = 2; code = first & 0x0f; }
      else if ((first & 0xf8) === 0xf0) { needed = 3; code = first & 0x07; }
      else { result += '\\ufffd'; continue; }
      if (i + needed > bytes.length) { result += '\\ufffd'; break; }
      let valid = true;
      for (let offset = 0; offset < needed; offset++) {
        const next = bytes[i++];
        if ((next & 0xc0) !== 0x80) { valid = false; break; }
        code = (code << 6) | (next & 0x3f);
      }
      if (!valid || code > 0x10ffff) { result += '\\ufffd'; continue; }
      if (code <= 0xffff) result += String.fromCharCode(code);
      else {
        code -= 0x10000;
        result += String.fromCharCode(0xd800 + (code >> 10), 0xdc00 + (code & 0x3ff));
      }
    }
    return result;
  };

  class QuickjsHeaders {
    constructor(init = {}) {
      this._values = Object.create(null);
      if (init instanceof QuickjsHeaders) init = Array.from(init.entries());
      if (Array.isArray(init)) {
        for (const pair of init) this.set(pair[0], pair[1]);
      } else if (init && typeof init === 'object') {
        for (const [name, value] of Object.entries(init)) this.set(name, value);
      }
    }
    set(name, value) { this._values[String(name).toLowerCase()] = String(value); }
    append(name, value) {
      name = String(name).toLowerCase();
      const current = this._values[name];
      this._values[name] = current === undefined ? String(value) : current + ', ' + value;
    }
    get(name) { return this._values[String(name).toLowerCase()] ?? null; }
    has(name) { return Object.prototype.hasOwnProperty.call(this._values, String(name).toLowerCase()); }
    delete(name) { delete this._values[String(name).toLowerCase()]; }
    entries() { return Object.entries(this._values)[Symbol.iterator](); }
    keys() { return Object.keys(this._values)[Symbol.iterator](); }
    values() { return Object.values(this._values)[Symbol.iterator](); }
    forEach(callback, thisArg) {
      for (const [name, value] of Object.entries(this._values)) callback.call(thisArg, value, name, this);
    }
    [Symbol.iterator]() { return this.entries(); }
    _toObject() { return { ...this._values }; }
  }

  class QuickjsResponse {
    constructor(payload) {
      this.status = payload.status;
      this.statusText = payload.statusText;
      this.url = payload.url;
      this.headers = new QuickjsHeaders(payload.headers);
      this.ok = this.status >= 200 && this.status < 300;
      this.redirected = false;
      this.type = 'basic';
      this.bodyUsed = false;
      this._bytes = new Uint8Array(payload.body);
    }
    _consume() {
      if (this.bodyUsed) throw new TypeError('Response body is already used');
      this.bodyUsed = true;
      return this._bytes;
    }
    async arrayBuffer() {
      const bytes = this._consume();
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }
    async text() { return decodeUtf8(this._consume()); }
    async json() { return JSON.parse(await this.text()); }
    clone() {
      if (this.bodyUsed) throw new TypeError('Response body is already used');
      return new QuickjsResponse({
        status: this.status,
        statusText: this.statusText,
        url: this.url,
        headers: this.headers._toObject(),
        body: new Uint8Array(this._bytes),
      });
    }
  }

  const normalizeBody = (body) => {
    if (body == null || typeof body === 'string' || body instanceof Uint8Array) return body;
    if (body instanceof ArrayBuffer) return new Uint8Array(body);
    if (ArrayBuffer.isView(body)) {
      return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    }
    throw new TypeError('fetch body must be a string, ArrayBuffer, or Uint8Array');
  };

  const fetch = async (input, init = {}) => {
    const url = typeof input === 'string' ? input : String(input && (input.href || input.url || input));
    const headers = new QuickjsHeaders(init.headers || {});
    const payload = await provider({
      url,
      method: String(init.method || 'GET').toUpperCase(),
      headers: headers._toObject(),
      body: normalizeBody(init.body),
    });
    return new QuickjsResponse(payload);
  };

  Object.defineProperties(globalThis, {
    fetch: { value: fetch, configurable: true, enumerable: false, writable: true },
    Headers: { value: QuickjsHeaders, configurable: true, enumerable: false, writable: true },
    Response: { value: QuickjsResponse, configurable: true, enumerable: false, writable: true },
  });
})();
''';
}
