import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:http/http.dart' as http;

import '../diagnostics/quickjs_exception.dart';
import '../runtime/quickjs_runtime_options.dart';

const _fetchProviderName = 'fetch.request';

/// Opt-in Fetch API mount backed by the platform HTTP client.
///
/// Native platforms use `dart:io`'s `HttpClient` through `package:http`.
/// Web uses the browser's native `fetch`. Pass a non-empty [allowedOrigins]
/// set to restrict requests and redirects to exact HTTP(S) origins. Leave it
/// null or empty to allow every HTTP(S) origin.
final class QuickjsFetchMount extends QuickjsHostMount {
  factory QuickjsFetchMount({
    Set<String>? allowedOrigins,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 1024 * 1024,
    int maxResponseBytes = 10 * 1024 * 1024,
    int maxRedirects = 5,
    Map<String, String> defaultHeaders = const <String, String>{},
  }) {
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

    final origins = allowedOrigins == null || allowedOrigins.isEmpty
        ? null
        : Set<String>.unmodifiable(allowedOrigins.map(_normalizeAllowedOrigin));
    final normalizedDefaultHeaders = Map<String, String>.unmodifiable(
      _normalizeRequestHeaders(defaultHeaders),
    );
    final provider = QuickjsHostProvider.dart(
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
        defaultHeaders: normalizedDefaultHeaders,
      ),
    );
    return QuickjsFetchMount._(
      allowedOrigins: origins,
      timeout: timeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      maxRedirects: maxRedirects,
      defaultHeaders: normalizedDefaultHeaders,
      provider: provider,
    );
  }

  QuickjsFetchMount._({
    required this.allowedOrigins,
    required this.timeout,
    required this.maxRequestBytes,
    required this.maxResponseBytes,
    required this.maxRedirects,
    required this.defaultHeaders,
    required QuickjsHostProvider provider,
  }) : super(
         name: 'fetch',
         environmentPatches: <QuickjsHostScript>[
           QuickjsHostScript.js(
             name: 'host:fetch.js',
             globals: const <String>[
               'fetch',
               'Headers',
               'Request',
               'Response',
               'AbortController',
               'AbortSignal',
               'XMLHttpRequest',
             ],
             source: _fetchHostScript(_fetchProviderName),
           ),
         ],
         providers: <QuickjsHostProvider>[provider],
       );

  /// Exact normalized HTTP(S) origins this mount may access.
  ///
  /// Null means every HTTP(S) origin is allowed by this mount. On Flutter Web,
  /// browser CORS rules still apply.
  final Set<String>? allowedOrigins;

  /// Maximum duration for request headers and response body consumption.
  final Duration timeout;

  /// Maximum encoded request body size.
  final int maxRequestBytes;

  /// Maximum streamed response body size.
  final int maxResponseBytes;

  /// Maximum number of redirects followed by one request.
  final int maxRedirects;

  /// Headers merged into every request unless overridden by JavaScript.
  final Map<String, String> defaultHeaders;
}

Future<Object?> _sendFetchRequest(
  List<Object?> args,
  QuickjsHostProviderContext context, {
  required Set<String>? allowedOrigins,
  required Duration timeout,
  required int maxRequestBytes,
  required int maxResponseBytes,
  required int maxRedirects,
  required Map<String, String> defaultHeaders,
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
  if (!_isAllowedOrigin(allowedOrigins, uri)) {
    throw JsValueConversionException(
      'QuickJS fetch origin is not allowed: ${uri.origin}',
    );
  }

  final method = '${payload['method'] ?? 'GET'}'.toUpperCase();
  if (!RegExp(r"^[!#$%&'*+.^_`|~0-9A-Z-]+$").hasMatch(method)) {
    throw JsValueConversionException('QuickJS fetch method is invalid');
  }
  final headers = <String, String>{
    ...defaultHeaders,
    ..._normalizeRequestHeaders(payload['headers']),
  };
  final body = _normalizeRequestBody(payload['body']);
  final redirectMode = '${payload['redirect'] ?? 'follow'}';
  if (redirectMode != 'follow' &&
      redirectMode != 'error' &&
      redirectMode != 'manual') {
    throw JsValueConversionException('QuickJS fetch redirect mode is invalid');
  }
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
    var currentUri = uri;
    var currentMethod = method;
    var currentBody = body;
    var redirectCount = 0;
    http.StreamedResponse response;
    while (true) {
      final request = http.Request(currentMethod, currentUri)
        ..followRedirects = kIsWeb ? redirectMode == 'follow' : false
        ..persistentConnection = false
        ..headers.addAll(headers);
      if (currentBody.isNotEmpty) request.bodyBytes = currentBody;
      try {
        response = await client.send(request).timeout(timeout);
      } on http.ClientException {
        if (kIsWeb && redirectMode == 'manual') {
          return <String, Object?>{
            'status': 0,
            'statusText': '',
            'url': currentUri.toString(),
            'redirected': false,
            'type': 'opaqueredirect',
            'headers': const <String, String>{},
            'body': Uint8List(0),
          };
        }
        rethrow;
      }
      if (kIsWeb) break;
      final location = response.headers['location'];
      final isRedirect =
          response.statusCode >= 300 &&
          response.statusCode < 400 &&
          location != null;
      if (!isRedirect || redirectMode == 'manual') break;
      if (redirectMode == 'error') {
        throw StateError(
          'QuickJS fetch redirect is not allowed by redirect:error',
        );
      }
      if (redirectCount >= maxRedirects) {
        throw StateError('QuickJS fetch exceeded $maxRedirects redirects');
      }
      final nextUri = currentUri.resolve(location);
      if ((nextUri.scheme != 'http' && nextUri.scheme != 'https') ||
          nextUri.host.isEmpty ||
          nextUri.userInfo.isNotEmpty ||
          !_isAllowedOrigin(allowedOrigins, nextUri)) {
        throw StateError(
          'QuickJS fetch redirect origin is not allowed: ${nextUri.origin}',
        );
      }
      await response.stream.drain<void>();
      redirectCount++;
      if (nextUri.origin != currentUri.origin) {
        headers.remove('authorization');
        headers.remove('cookie');
        headers.remove('proxy-authorization');
      }
      if (response.statusCode == 303 ||
          ((response.statusCode == 301 || response.statusCode == 302) &&
              currentMethod == 'POST')) {
        currentMethod = 'GET';
        currentBody = Uint8List(0);
        headers.remove('content-type');
      }
      currentUri = nextUri;
    }
    final responseUri = switch (response) {
      http.BaseResponseWithUrl(:final url) => url,
      _ => response.request?.url ?? uri,
    };
    if (!_isAllowedOrigin(allowedOrigins, responseUri)) {
      throw StateError(
        'QuickJS fetch redirect origin is not allowed: ${responseUri.origin}',
      );
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
      'url': responseUri.toString(),
      'redirected': redirectCount > 0 || responseUri != uri,
      'type': 'basic',
      'headers': response.headers,
      'body': builder.takeBytes(),
    };
  } on TimeoutException {
    client.close();
    throw StateError('QuickJS fetch timed out after $timeout');
  } on http.ClientException catch (error) {
    throw StateError('QuickJS fetch network error: ${error.message}');
  } finally {
    client.close();
  }
}

bool _isAllowedOrigin(Set<String>? allowedOrigins, Uri uri) {
  return allowedOrigins == null || allowedOrigins.contains(uri.origin);
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
      this.redirected = Boolean(payload.redirected);
      this.type = payload.type || 'basic';
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
        redirected: this.redirected,
        type: this.type,
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

  class QuickjsRequest {
    constructor(input, init = {}) {
      const source = input instanceof QuickjsRequest ? input : null;
      this.url = source ? source.url : String(input && (input.href || input.url || input));
      this.method = String(init.method || (source && source.method) || 'GET').toUpperCase();
      this.headers = new QuickjsHeaders(init.headers || (source && source.headers) || {});
      this.body = normalizeBody(init.body !== undefined ? init.body : source && source.body);
      this.redirect = String(init.redirect || (source && source.redirect) || 'follow');
      this.credentials = String(init.credentials || (source && source.credentials) || 'same-origin');
    }
    clone() { return new QuickjsRequest(this); }
  }

  const fetch = async (input, init = {}) => {
    const request = new QuickjsRequest(input, init);
    const payload = await provider({
      url: request.url,
      method: request.method,
      headers: request.headers._toObject(),
      body: request.body,
      redirect: request.redirect,
    });
    return new QuickjsResponse(payload);
  };

  class QuickjsAbortSignal {
    constructor() {
      this.aborted = false;
      this.reason = undefined;
      this.onabort = null;
      this._listeners = [];
    }
    addEventListener(type, callback, options) {
      if (type !== 'abort' || typeof callback !== 'function') return;
      this._listeners.push({ callback, once: Boolean(options && options.once) });
    }
    removeEventListener(type, callback) {
      if (type === 'abort') {
        this._listeners = this._listeners.filter((entry) => entry.callback !== callback);
      }
    }
    throwIfAborted() {
      if (this.aborted) throw this.reason || new Error('This operation was aborted');
    }
    _abort(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason === undefined ? new Error('This operation was aborted') : reason;
      const event = { type: 'abort', target: this, currentTarget: this };
      if (typeof this.onabort === 'function') this.onabort.call(this, event);
      const listeners = this._listeners.slice();
      this._listeners = this._listeners.filter((entry) => !entry.once);
      for (const entry of listeners) entry.callback.call(this, event);
    }
    static abort(reason) {
      const controller = new QuickjsAbortController();
      controller.abort(reason);
      return controller.signal;
    }
  }

  class QuickjsAbortController {
    constructor() { this.signal = new QuickjsAbortSignal(); }
    abort(reason) { this.signal._abort(reason); }
  }

  class QuickjsXMLHttpRequest {
    constructor() {
      this.readyState = 0;
      this.status = 0;
      this.statusText = '';
      this.responseType = '';
      this.response = null;
      this.responseText = '';
      this.responseURL = '';
      this.timeout = 0;
      this.withCredentials = false;
      this.onreadystatechange = null;
      this.onloadstart = null;
      this.onload = null;
      this.onloadend = null;
      this.onerror = null;
      this.ontimeout = null;
      this.onabort = null;
      this.onprogress = null;
      this.upload = { addEventListener() {}, removeEventListener() {} };
      this._listeners = Object.create(null);
      this._headers = new QuickjsHeaders();
      this._responseHeaders = new QuickjsHeaders();
      this._aborted = false;
      this._sent = false;
    }
    open(method, url, async = true, username, password) {
      if (async === false) throw new Error('Synchronous XMLHttpRequest is not supported');
      this._method = String(method).toUpperCase();
      this._url = String(url);
      this._headers = new QuickjsHeaders();
      this._aborted = false;
      this._sent = false;
      this._setReadyState(1);
    }
    setRequestHeader(name, value) {
      if (this.readyState !== 1 || this._sent) throw new Error('InvalidStateError');
      this._headers.append(name, value);
    }
    getResponseHeader(name) {
      return this.readyState < 2 ? null : this._responseHeaders.get(name);
    }
    getAllResponseHeaders() {
      if (this.readyState < 2) return '';
      return Array.from(this._responseHeaders.entries()).map(([k, v]) => k + ': ' + v).join('\\r\\n');
    }
    overrideMimeType() {}
    addEventListener(type, callback) {
      if (typeof callback !== 'function') return;
      (this._listeners[type] || (this._listeners[type] = [])).push(callback);
    }
    removeEventListener(type, callback) {
      const list = this._listeners[type];
      if (list) this._listeners[type] = list.filter((item) => item !== callback);
    }
    _dispatch(type) {
      const event = { type, target: this, currentTarget: this, lengthComputable: false, loaded: 0, total: 0 };
      const handler = this['on' + type];
      if (typeof handler === 'function') handler.call(this, event);
      for (const listener of this._listeners[type] || []) listener.call(this, event);
    }
    _setReadyState(value) {
      this.readyState = value;
      this._dispatch('readystatechange');
    }
    abort() {
      if (this.readyState === 0 || this.readyState === 4) return;
      this._aborted = true;
      this.status = 0;
      this._setReadyState(4);
      this._dispatch('abort');
      this._dispatch('loadend');
    }
    async send(body = null) {
      if (this.readyState !== 1 || this._sent) throw new Error('InvalidStateError');
      this._sent = true;
      this._dispatch('loadstart');
      let timer = null;
      try {
        const request = provider({
          url: this._url,
          method: this._method,
          headers: this._headers._toObject(),
          body: normalizeBody(body),
          redirect: 'follow',
        });
        const payload = this.timeout > 0
          ? await Promise.race([
              request,
              new Promise((_, reject) => { timer = setTimeout(() => reject({ __xhrTimeout: true }), this.timeout); }),
            ])
          : await request;
        if (timer !== null) clearTimeout(timer);
        if (this._aborted) return;
        this.status = payload.status;
        this.statusText = payload.statusText;
        this.responseURL = payload.url;
        this._responseHeaders = new QuickjsHeaders(payload.headers);
        this._setReadyState(2);
        this._setReadyState(3);
        const bytes = new Uint8Array(payload.body);
        const text = decodeUtf8(bytes);
        if (this.responseType === 'arraybuffer') {
          this.response = bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
        } else if (this.responseType === 'json') {
          this.response = text === '' ? null : JSON.parse(text);
        } else {
          this.responseText = text;
          this.response = text;
        }
        this._setReadyState(4);
        this._dispatch('load');
        this._dispatch('loadend');
      } catch (error) {
        if (timer !== null) clearTimeout(timer);
        if (this._aborted) return;
        this.status = 0;
        this._setReadyState(4);
        this._dispatch(error && error.__xhrTimeout ? 'timeout' : 'error');
        this._dispatch('loadend');
      }
    }
  }
  Object.assign(QuickjsXMLHttpRequest, { UNSENT: 0, OPENED: 1, HEADERS_RECEIVED: 2, LOADING: 3, DONE: 4 });
  Object.assign(QuickjsXMLHttpRequest.prototype, { UNSENT: 0, OPENED: 1, HEADERS_RECEIVED: 2, LOADING: 3, DONE: 4 });

  Object.defineProperties(globalThis, {
    fetch: { value: fetch, configurable: true, enumerable: false, writable: true },
    Headers: { value: QuickjsHeaders, configurable: true, enumerable: false, writable: true },
    Request: { value: QuickjsRequest, configurable: true, enumerable: false, writable: true },
    Response: { value: QuickjsResponse, configurable: true, enumerable: false, writable: true },
    AbortController: { value: QuickjsAbortController, configurable: true, enumerable: false, writable: true },
    AbortSignal: { value: QuickjsAbortSignal, configurable: true, enumerable: false, writable: true },
    XMLHttpRequest: { value: QuickjsXMLHttpRequest, configurable: true, enumerable: false, writable: true },
  });
})();
''';
}
