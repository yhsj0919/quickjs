import 'dart:convert';

/// Embedded Fetch API host script installed by [QuickjsFetchMount].
String quickjsFetchHostScript(String providerName) {
  final encodedProviderName = jsonEncode(providerName);
  return '''
(() => {
  const provider = globalThis.__quickjsHostProviders[$encodedProviderName];

  const encodeUtf8 = (text) => {
    const input = String(text);
    const bytes = [];
    for (let i = 0; i < input.length; i++) {
      let code = input.charCodeAt(i);
      if (code >= 0xd800 && code <= 0xdbff) {
        const next = input.charCodeAt(i + 1);
        if (next >= 0xdc00 && next <= 0xdfff) {
          code = 0x10000 + ((code - 0xd800) << 10) + (next - 0xdc00);
          i++;
        }
      }
      if (code < 0x80) {
        bytes.push(code);
      } else if (code < 0x800) {
        bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
      } else if (code < 0x10000) {
        bytes.push(
          0xe0 | (code >> 12),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f),
        );
      } else {
        bytes.push(
          0xf0 | (code >> 18),
          0x80 | ((code >> 12) & 0x3f),
          0x80 | ((code >> 6) & 0x3f),
          0x80 | (code & 0x3f),
        );
      }
    }
    return new Uint8Array(bytes);
  };
  const createAbortError = (message = 'The operation was aborted.') => {
    try {
      return new DOMException(message, 'AbortError');
    } catch (_) {
      const error = new Error(message);
      error.name = 'AbortError';
      return error;
    }
  };
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

  const concatBytes = (chunks) => {
    let total = 0;
    for (const chunk of chunks) total += chunk.length;
    const merged = new Uint8Array(total);
    let offset = 0;
    for (const chunk of chunks) {
      merged.set(chunk, offset);
      offset += chunk.length;
    }
    return merged;
  };

  const toUint8Array = (value) => {
    if (value == null) return new Uint8Array(0);
    if (typeof value === 'string') return encodeUtf8(value);
    if (value instanceof Uint8Array) return value;
    if (value instanceof ArrayBuffer) return new Uint8Array(value);
    if (ArrayBuffer.isView(value)) {
      return new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    }
    throw new TypeError('Unsupported body type');
  };

  class ReadableStream {
    constructor(underlyingSource = {}) {
      this._state = 'readable';
      this._queue = [];
      this._reader = null;
      const controller = {
        enqueue: (chunk) => {
          if (this._state !== 'readable') return;
          if (this._reader) {
            this._reader._resolveRead({ value: chunk, done: false });
            this._reader = null;
          } else {
            this._queue.push(chunk);
          }
        },
        close: () => {
          if (this._state !== 'readable') return;
          this._state = 'closed';
          if (this._reader) {
            this._reader._resolveRead({ value: undefined, done: true });
            this._reader = null;
          }
        },
        error: (reason) => {
          this._state = 'errored';
          this._storedError = reason;
          if (this._reader) {
            this._reader._rejectRead(reason);
            this._reader = null;
          }
        },
      };
      if (typeof underlyingSource.start === 'function') {
        underlyingSource.start(controller);
      }
      if (typeof underlyingSource.pull === 'function') {
        this._pull = underlyingSource.pull.bind(underlyingSource, controller);
      }
    }
    getReader() {
      if (this._state === 'errored') throw this._storedError;
      return new ReadableStreamDefaultReader(this);
    }
    _read() {
      if (this._queue.length > 0) {
        return Promise.resolve({ value: this._queue.shift(), done: false });
      }
      if (this._state === 'closed') {
        return Promise.resolve({ value: undefined, done: true });
      }
      if (this._state === 'errored') {
        return Promise.reject(this._storedError);
      }
      return new Promise((resolve, reject) => {
        this._reader = { _resolveRead: resolve, _rejectRead: reject };
      });
    }
    tee() {
      const left = [];
      const right = [];
      const reader = this.getReader();
      const pump = async () => {
        while (true) {
          const { value, done } = await reader.read();
          if (done) break;
          left.push(value);
          right.push(value);
        }
      };
      pump();
      const makeStream = (buffer) => new ReadableStream({
        start(controller) {
          for (const chunk of buffer) controller.enqueue(chunk);
          controller.close();
        },
      });
      return [makeStream(left), makeStream(right)];
    }
  }

  class ReadableStreamDefaultReader {
    constructor(stream) {
      this._stream = stream;
    }
    read() {
      return this._stream._read();
    }
    cancel() {
      this._stream._state = 'closed';
      return Promise.resolve();
    }
  }

  const bytesToReadableStream = (bytes) => new ReadableStream({
    start(controller) {
      if (bytes.length > 0) controller.enqueue(bytes);
      controller.close();
    },
  });

  const readStreamToBytes = async (stream) => {
    const reader = stream.getReader();
    const chunks = [];
    while (true) {
      const { value, done } = await reader.read();
      if (done) break;
      chunks.push(toUint8Array(value));
    }
    return concatBytes(chunks);
  };

  class AbortSignal {
    constructor() {
      this.aborted = false;
      this.reason = undefined;
      this._listeners = [];
    }
    throwIfAborted() {
      if (this.aborted) throw createAbortError();
    }
    addEventListener(type, listener) {
      if (type !== 'abort' || typeof listener !== 'function') return;
      this._listeners.push(listener);
    }
    removeEventListener(type, listener) {
      if (type !== 'abort') return;
      this._listeners = this._listeners.filter((entry) => entry !== listener);
    }
    _abort(reason) {
      if (this.aborted) return;
      this.aborted = true;
      this.reason = reason;
      for (const listener of this._listeners.slice()) listener();
    }
    static abort(reason) {
      const signal = new AbortSignal();
      signal._abort(reason);
      return signal;
    }
    static timeout(delay) {
      const controller = new AbortController();
      setTimeout(() => controller.abort(createAbortError('Signal timed out.')), delay);
      return controller.signal;
    }
  }

  class AbortController {
    constructor() {
      this.signal = new AbortSignal();
    }
    abort(reason) {
      this.signal._abort(reason);
    }
  }

  class Blob {
    constructor(blobParts = [], options = {}) {
      const parts = [];
      for (const part of blobParts) {
        if (typeof part === 'string') parts.push(encodeUtf8(part));
        else if (part instanceof Blob) parts.push(...part._parts);
        else parts.push(toUint8Array(part));
      }
      this._parts = parts;
      this.size = parts.reduce((sum, part) => sum + part.length, 0);
      this.type = options.type == null ? '' : String(options.type);
    }
    async arrayBuffer() {
      return concatBytes(this._parts).buffer;
    }
    async text() {
      return decodeUtf8(await this.arrayBuffer().then((buffer) => new Uint8Array(buffer)));
    }
    slice(start = 0, end = this.size, contentType = '') {
      const bytes = concatBytes(this._parts);
      const normalizedStart = start < 0 ? Math.max(bytes.length + start, 0) : Math.min(start, bytes.length);
      const normalizedEnd = end < 0 ? Math.max(bytes.length + end, 0) : Math.min(end, bytes.length);
      return new Blob([bytes.subarray(normalizedStart, normalizedEnd)], {
        type: contentType || this.type,
      });
    }
    stream() {
      return bytesToReadableStream(concatBytes(this._parts));
    }
  }

  class URLSearchParams {
    constructor(init = '') {
      this._entries = [];
      if (init instanceof URLSearchParams) {
        this._entries = init._entries.map((entry) => entry.slice());
      } else if (typeof init === 'string') {
        if (init.length > 0 && init.startsWith('?')) init = init.slice(1);
        for (const pair of init.split('&')) {
          if (!pair) continue;
          const index = pair.indexOf('=');
          const name = decodeURIComponent(index < 0 ? pair : pair.slice(0, index));
          const value = decodeURIComponent(index < 0 ? '' : pair.slice(index + 1));
          this._entries.push([name, value]);
        }
      } else if (Array.isArray(init)) {
        for (const pair of init) this.append(pair[0], pair[1]);
      } else if (init && typeof init === 'object') {
        for (const [name, value] of Object.entries(init)) this.append(name, value);
      }
    }
    append(name, value) { this._entries.push([String(name), String(value)]); }
    set(name, value) {
      name = String(name);
      const filtered = this._entries.filter((entry) => entry[0] !== name);
      filtered.push([name, String(value)]);
      this._entries = filtered;
    }
    get(name) {
      const match = this._entries.find((entry) => entry[0] === String(name));
      return match ? match[1] : null;
    }
    getAll(name) {
      return this._entries.filter((entry) => entry[0] === String(name)).map((entry) => entry[1]);
    }
    has(name) { return this._entries.some((entry) => entry[0] === String(name)); }
    delete(name) {
      name = String(name);
      this._entries = this._entries.filter((entry) => entry[0] !== name);
    }
    toString() {
      return this._entries
        .map(([name, value]) => encodeURIComponent(name) + '=' + encodeURIComponent(value))
        .join('&');
    }
    entries() { return this._entries[Symbol.iterator](); }
    keys() { return this._entries.map((entry) => entry[0])[Symbol.iterator](); }
    values() { return this._entries.map((entry) => entry[1])[Symbol.iterator](); }
    forEach(callback, thisArg) {
      for (const [name, value] of this._entries) callback.call(thisArg, value, name, this);
    }
    [Symbol.iterator]() { return this.entries(); }
  }

  class FormData {
    constructor() {
      this._entries = [];
    }
    append(name, value, filename) {
      this._entries.push({ name: String(name), value, filename: filename == null ? null : String(filename) });
    }
    set(name, value, filename) {
      name = String(name);
      this._entries = this._entries.filter((entry) => entry.name !== name);
      this.append(name, value, filename);
    }
    get(name) {
      const match = this._entries.find((entry) => entry.name === String(name));
      return match ? match.value : null;
    }
    getAll(name) {
      return this._entries.filter((entry) => entry.name === String(name)).map((entry) => entry.value);
    }
    has(name) { return this._entries.some((entry) => entry.name === String(name)); }
    delete(name) {
      name = String(name);
      this._entries = this._entries.filter((entry) => entry.name !== name);
    }
    entries() { return this._entries.map((entry) => [entry.name, entry.value])[Symbol.iterator](); }
    keys() { return this._entries.map((entry) => entry.name)[Symbol.iterator](); }
    values() { return this._entries.map((entry) => entry.value)[Symbol.iterator](); }
    forEach(callback, thisArg) {
      for (const entry of this._entries) callback.call(thisArg, entry.value, entry.name, this);
    }
    [Symbol.iterator]() { return this.entries(); }
  }

  class Headers {
    constructor(init = {}) {
      this._values = Object.create(null);
      if (init instanceof Headers) init = Array.from(init.entries());
      if (Array.isArray(init)) {
        for (const pair of init) this.append(pair[0], pair[1]);
      } else if (init && typeof init === 'object') {
        for (const [name, value] of Object.entries(init)) this.append(name, value);
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
    getSetCookie() {
      const value = this.get('set-cookie');
      return value == null ? [] : [value];
    }
    entries() { return Object.entries(this._values)[Symbol.iterator](); }
    keys() { return Object.keys(this._values)[Symbol.iterator](); }
    values() { return Object.values(this._values)[Symbol.iterator](); }
    forEach(callback, thisArg) {
      for (const [name, value] of Object.entries(this._values)) callback.call(thisArg, value, name, this);
    }
    [Symbol.iterator]() { return this.entries(); }
    _toObject() { return { ...this._values }; }
  }

  const randomBoundary = () => '----quickjsFormBoundary' + Math.random().toString(16).slice(2);

  const encodeFormData = (formData) => {
    const boundary = randomBoundary();
    const chunks = [];
    const pushText = (text) => chunks.push(encodeUtf8(text));
    for (const entry of formData._entries) {
      pushText('--' + boundary + '\\r\\n');
      if (entry.value instanceof Blob) {
        const filename = entry.filename || 'blob';
        pushText('Content-Disposition: form-data; name="' + entry.name + '"; filename="' + filename + '"\\r\\n');
        pushText('Content-Type: ' + (entry.value.type || 'application/octet-stream') + '\\r\\n\\r\\n');
        chunks.push(concatBytes(entry.value._parts));
      } else {
        pushText('Content-Disposition: form-data; name="' + entry.name + '"\\r\\n\\r\\n');
        pushText(String(entry.value));
      }
      pushText('\\r\\n');
    }
    pushText('--' + boundary + '--\\r\\n');
    return {
      body: concatBytes(chunks),
      contentType: 'multipart/form-data; boundary=' + boundary,
    };
  };

  const serializeBody = async (body, headers, method) => {
    if (body == null) return new Uint8Array(0);
    if (typeof body === 'string') {
      if (!headers.has('content-type')) {
        headers.set('content-type', 'text/plain;charset=UTF-8');
      }
      return encodeUtf8(body);
    }
    if (body instanceof Uint8Array) return body;
    if (body instanceof ArrayBuffer) return new Uint8Array(body);
    if (ArrayBuffer.isView(body)) return new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
    if (body instanceof Blob) {
      if (!headers.has('content-type') && body.type) headers.set('content-type', body.type);
      return concatBytes(body._parts);
    }
    if (body instanceof URLSearchParams) {
      if (!headers.has('content-type')) {
        headers.set('content-type', 'application/x-www-form-urlencoded;charset=UTF-8');
      }
      return encodeUtf8(body.toString());
    }
    if (body instanceof FormData) {
      const encoded = encodeFormData(body);
      headers.set('content-type', encoded.contentType);
      return encoded.body;
    }
    if (body instanceof ReadableStream) {
      return readStreamToBytes(body);
    }
    throw new TypeError('Unsupported request body type');
  };

  class Request {
    constructor(input, init = {}) {
      const base = input instanceof Request ? input : null;
      this.method = String(init.method ?? base?.method ?? 'GET').toUpperCase();
      this.url = typeof input === 'string'
        ? input
        : (base ? base.url : String(input && (input.href || input.url || input)));
      this.headers = new Headers(init.headers ?? base?.headers);
      this.mode = init.mode ?? base?.mode ?? 'cors';
      this.credentials = init.credentials ?? base?.credentials ?? 'same-origin';
      this.cache = init.cache ?? base?.cache ?? 'default';
      this.redirect = init.redirect ?? base?.redirect ?? 'follow';
      this.referrer = init.referrer ?? base?.referrer ?? 'about:client';
      this.referrerPolicy = init.referrerPolicy ?? base?.referrerPolicy ?? '';
      this.integrity = init.integrity ?? base?.integrity ?? '';
      this.keepalive = init.keepalive ?? base?.keepalive ?? false;
      this.signal = init.signal ?? base?.signal ?? new AbortController().signal;
      this.destination = 'document';
      this.bodyUsed = false;
      if (init.body !== undefined) {
        this.body = init.body;
        this._bodyBytes = null;
      } else if (base) {
        this.body = base.body;
        this.bodyUsed = base.bodyUsed;
        this._bodyBytes = base._bodyBytes ? new Uint8Array(base._bodyBytes) : null;
      } else {
        this.body = null;
        this._bodyBytes = null;
      }
    }
    clone() {
      if (this.bodyUsed) throw new TypeError('Request body is already used');
      const init = {
        method: this.method,
        headers: this.headers,
        mode: this.mode,
        credentials: this.credentials,
        cache: this.cache,
        redirect: this.redirect,
        referrer: this.referrer,
        referrerPolicy: this.referrerPolicy,
        integrity: this.integrity,
        keepalive: this.keepalive,
        signal: this.signal,
      };
      if (this._bodyBytes) {
        init.body = new Uint8Array(this._bodyBytes);
      } else if (this.body != null) {
        init.body = this.body;
      }
      return new Request(this.url, init);
    }
    async _consumeBody() {
      if (this.bodyUsed) throw new TypeError('Request body is already used');
      this.bodyUsed = true;
      if (this._bodyBytes) return this._bodyBytes;
      return serializeBody(this.body, this.headers, this.method);
    }
  }

  class Response {
    constructor(body = null, init = {}) {
      this.status = init.status == null ? 200 : init.status;
      this.statusText = init.statusText == null ? '' : String(init.statusText);
      this.headers = new Headers(init.headers);
      this.ok = this.status >= 200 && this.status < 300;
      this.redirected = init.redirected === true;
      this.type = init.type == null ? 'default' : String(init.type);
      this.url = init.url == null ? '' : String(init.url);
      this.bodyUsed = false;
      this._assignBody(body);
    }
    static json(data, init = {}) {
      const headers = new Headers(init.headers);
      if (!headers.has('content-type')) {
        headers.set('content-type', 'application/json');
      }
      return new Response(JSON.stringify(data), { ...init, headers });
    }
    static error() {
      return new Response(null, { status: 0, statusText: '', type: 'error' });
    }
    static redirect(url, status = 302) {
      const headers = new Headers();
      headers.set('Location', String(url));
      return new Response(null, { status, headers, type: 'default' });
    }
    static _fromPayload(payload) {
      return new Response(payload.body, {
        status: payload.status,
        statusText: payload.statusText,
        url: payload.url,
        headers: payload.headers,
        type: 'basic',
        redirected: payload.redirected === true,
      });
    }
    get body() {
      if (this.bodyUsed) return null;
      return this._bodyStream;
    }
    _assignBody(body) {
      if (body == null) {
        this._bytes = new Uint8Array(0);
      } else if (typeof body === 'string') {
        this._bytes = encodeUtf8(body);
      } else if (body instanceof Uint8Array) {
        this._bytes = body;
      } else if (body instanceof ArrayBuffer) {
        this._bytes = new Uint8Array(body);
      } else if (ArrayBuffer.isView(body)) {
        this._bytes = new Uint8Array(body.buffer, body.byteOffset, body.byteLength);
      } else if (body instanceof Blob) {
        this._bytes = concatBytes(body._parts);
      } else if (body instanceof ReadableStream) {
        this._bodyStream = body;
        this._bytes = null;
        return;
      } else {
        throw new TypeError('Invalid response body');
      }
      this._bodyStream = bytesToReadableStream(this._bytes);
    }
    async _ensureBytes() {
      if (this._bytes) return this._bytes;
      if (!this._bodyStream) return new Uint8Array(0);
      this._bytes = await readStreamToBytes(this._bodyStream);
      this._bodyStream = bytesToReadableStream(this._bytes);
      return this._bytes;
    }
    async _takeBytes() {
      if (this.bodyUsed) {
        if (!this._bytes) {
          throw new TypeError('Response body is already used');
        }
        return this._bytes;
      }
      const bytes = await this._ensureBytes();
      this.bodyUsed = true;
      return bytes;
    }
    async arrayBuffer() {
      const bytes = await this._takeBytes();
      return bytes.buffer.slice(bytes.byteOffset, bytes.byteOffset + bytes.byteLength);
    }
    async text() {
      return decodeUtf8(await this._takeBytes());
    }
    async json() {
      return JSON.parse(await this.text());
    }
    async blob() {
      const bytes = await this._takeBytes();
      const type = this.headers.get('content-type') || '';
      return new Blob([bytes], { type });
    }
    async bytes() {
      const bytes = await this._takeBytes();
      return new Uint8Array(bytes);
    }
    async formData() {
      const bytes = await this._takeBytes();
      const contentType = this.headers.get('content-type') || '';
      const formData = new FormData();
      if (contentType.includes('application/x-www-form-urlencoded')) {
        const params = new URLSearchParams(decodeUtf8(bytes));
        for (const [name, value] of params.entries()) formData.append(name, value);
        return formData;
      }
      throw new TypeError('Response is not form data');
    }
    clone() {
      if (this.bodyUsed) throw new TypeError('Response body is already used');
      const bytes = this._bytes ? new Uint8Array(this._bytes) : new Uint8Array(0);
      return new Response(bytes, {
        status: this.status,
        statusText: this.statusText,
        headers: this.headers,
        url: this.url,
        redirected: this.redirected,
        type: this.type,
      });
    }
  }

  const createFetchLikeResponse = (request) => ({
    ok: ((request.status / 100) | 0) === 2,
    status: request.status,
    statusText: request.statusText,
    url: request.responseURL,
    headers: request._responseHeaders || new Headers(),
    redirected: request._redirected === true,
    text: () => Promise.resolve(request.responseText),
    json: () => Promise.resolve(JSON.parse(request.responseText)),
    arrayBuffer: () => {
      const value = request.response;
      if (value instanceof ArrayBuffer) return Promise.resolve(value);
      if (ArrayBuffer.isView(value)) {
        return Promise.resolve(
          value.buffer.slice(value.byteOffset, value.byteOffset + value.byteLength),
        );
      }
      return Promise.resolve(encodeUtf8(request.responseText).buffer);
    },
    blob: () => {
      const value = request.response;
      if (value instanceof Blob) return Promise.resolve(value);
      const type = request._responseHeaders?.get('content-type') || '';
      return Promise.resolve(new Blob([request.responseText], { type }));
    },
  });

  class XMLHttpRequest {
    constructor() {
      this.UNSENT = 0;
      this.OPENED = 1;
      this.HEADERS_RECEIVED = 2;
      this.LOADING = 3;
      this.DONE = 4;
      this.readyState = this.UNSENT;
      this.status = 0;
      this.statusText = '';
      this.responseURL = '';
      this.response = '';
      this.responseText = '';
      this.responseType = '';
      this.timeout = 0;
      this.withCredentials = false;
      this._method = 'GET';
      this._url = '';
      this._async = true;
      this._headers = new Headers();
      this._responseHeaders = null;
      this._redirected = false;
      this._abortController = null;
      this._timeoutId = 0;
      this.onload = null;
      this.onerror = null;
      this.onabort = null;
      this.ontimeout = null;
      this.onloadend = null;
    }
    open(method, url, async = true) {
      if (this.readyState !== this.UNSENT && this.readyState !== this.DONE) {
        throw new Error('XMLHttpRequest state error');
      }
      this._method = String(method || 'GET').toUpperCase();
      this._url = String(url);
      this._async = async !== false;
      if (!this._async) {
        throw new Error('Synchronous XMLHttpRequest is not supported');
      }
      this.readyState = this.OPENED;
      this.status = 0;
      this.statusText = '';
      this.responseURL = '';
      this.response = '';
      this.responseText = '';
      this._responseHeaders = null;
      this._redirected = false;
    }
    setRequestHeader(name, value) {
      if (this.readyState !== this.OPENED) {
        throw new Error('XMLHttpRequest is not opened');
      }
      this._headers.set(name, value);
    }
    getResponseHeader(name) {
      if (!this._responseHeaders || this.readyState < this.HEADERS_RECEIVED) {
        return null;
      }
      return this._responseHeaders.get(name);
    }
    getAllResponseHeaders() {
      if (!this._responseHeaders || this.readyState < this.HEADERS_RECEIVED) {
        return null;
      }
      const lines = [];
      for (const [name, value] of this._responseHeaders.entries()) {
        lines.push(name + ': ' + value);
      }
      return lines.join('\\r\\n');
    }
    abort() {
      if (this._timeoutId) {
        clearTimeout(this._timeoutId);
        this._timeoutId = 0;
      }
      this._abortController?.abort();
    }
    send(body = null) {
      if (this.readyState !== this.OPENED) {
        throw new Error('XMLHttpRequest is not opened');
      }
      this._abortController = new AbortController();
      const init = {
        method: this._method,
        headers: this._headers,
        signal: this._abortController.signal,
      };
      if (body != null) init.body = body;
      if (this.timeout > 0) {
        this._timeoutId = setTimeout(() => {
          this.abort();
          if (this.ontimeout) this.ontimeout({ type: 'timeout' });
        }, this.timeout);
      }
      this.readyState = this.HEADERS_RECEIVED;
      fetch(this._url, init)
        .then(async (response) => {
          if (this._timeoutId) {
            clearTimeout(this._timeoutId);
            this._timeoutId = 0;
          }
          this.status = response.status;
          this.statusText = response.statusText;
          this.responseURL = response.url;
          this._responseHeaders = response.headers;
          this._redirected = response.redirected === true;
          this.readyState = this.LOADING;
          if (this.responseType === 'json') {
            this.response = await response.json();
            this.responseText =
              typeof this.response === 'string'
                ? this.response
                : JSON.stringify(this.response);
          } else if (this.responseType === 'arraybuffer') {
            this.response = await response.arrayBuffer();
            this.responseText = '';
          } else if (this.responseType === 'blob') {
            this.response = await response.blob();
            this.responseText = '';
          } else {
            this.responseText = await response.text();
            this.response = this.responseText;
          }
          this.readyState = this.DONE;
          if (this.onload) this.onload({ type: 'load' });
          if (this.onloadend) this.onloadend({ type: 'loadend' });
        })
        .catch((error) => {
          if (this._timeoutId) {
            clearTimeout(this._timeoutId);
            this._timeoutId = 0;
          }
          this.readyState = this.DONE;
          if (this._abortController?.signal.aborted) {
            if (this.onabort) this.onabort({ type: 'abort' });
          } else if (this.onerror) {
            this.onerror({ type: 'error' });
          }
          if (this.onloadend) this.onloadend({ type: 'loadend' });
        });
    }
    toFetchResponse() {
      return createFetchLikeResponse(this);
    }
  }

  const fetch = async (input, init = {}) => {
    const request = input instanceof Request
      ? (init && Object.keys(init).length > 0 ? new Request(input, init) : input)
      : new Request(input, init);
    if (request.signal.aborted) throw createAbortError();
    let onAbort;
    const abortPromise = new Promise((_, reject) => {
      onAbort = () => reject(createAbortError());
      request.signal.addEventListener('abort', onAbort);
    });
    const run = async () => {
      const body = await request._consumeBody();
      const headers = new Headers(request.headers);
      if (body.length > 0 && (request.method === 'GET' || request.method === 'HEAD')) {
        throw new TypeError('Request with GET/HEAD method cannot have body');
      }
      try {
        const payload = await provider({
          url: request.url,
          method: request.method,
          headers: headers._toObject(),
          body,
          redirect: request.redirect,
        });
        return Response._fromPayload(payload);
      } catch (error) {
        const message = String(error && (error.message || error));
        if (message.includes('redirect=error')) {
          throw new TypeError(message);
        }
        throw error;
      }
    };
    try {
      return await Promise.race([run(), abortPromise]);
    } finally {
      if (onAbort) request.signal.removeEventListener('abort', onAbort);
    }
  };

  Object.defineProperties(globalThis, {
    fetch: { value: fetch, configurable: true, enumerable: false, writable: true },
    Headers: { value: Headers, configurable: true, enumerable: false, writable: true },
    Request: { value: Request, configurable: true, enumerable: false, writable: true },
    Response: { value: Response, configurable: true, enumerable: false, writable: true },
    AbortController: { value: AbortController, configurable: true, enumerable: false, writable: true },
    AbortSignal: { value: AbortSignal, configurable: true, enumerable: false, writable: true },
    FormData: { value: FormData, configurable: true, enumerable: false, writable: true },
    URLSearchParams: { value: URLSearchParams, configurable: true, enumerable: false, writable: true },
    Blob: { value: Blob, configurable: true, enumerable: false, writable: true },
    ReadableStream: { value: ReadableStream, configurable: true, enumerable: false, writable: true },
    XMLHttpRequest: { value: XMLHttpRequest, configurable: true, enumerable: false, writable: true },
  });
})();
''';
}
