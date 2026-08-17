part of '../runtime/runtime_options.dart';

/// 提供轻量浏览器全局环境，不包含网络、Web Crypto 或 DOM。
final class WebFeatures extends JsFeatures {
  WebFeatures({
    String locationHref = 'about:blank',
    String userAgent = 'QuickJS',
    bool window = true,
    bool self = true,
    bool storage = true,
  }) : super(
         name: 'web',
         browserGlobals: JsGlobals(window: window, self: self),
         scripts: <JsScript>[
           JsScript(
             name: 'host:web-globals.js',
             globals: <String>[
               'location',
               'navigator',
               'URL',
               if (storage) 'localStorage',
               if (storage) 'sessionStorage',
             ],
             source: _webHostScriptSource(
               locationHref: locationHref,
               userAgent: userAgent,
               storage: storage,
             ),
           ),
         ],
       );
}

String _webHostScriptSource({
  required String locationHref,
  required String userAgent,
  required bool storage,
}) {
  final href = jsonEncode(locationHref);
  final encodedUserAgent = jsonEncode(userAgent);
  final installStorage = storage ? 'true' : 'false';
  return '''
(() => {
  const parseUrl = (value) => {
    const href = String(value || 'about:blank');
    const match = /^([a-zA-Z][a-zA-Z0-9+.-]*:)(?:\\/\\/([^\\/?#]*))?([^?#]*)(\\?[^#]*)?(#.*)?\$/.exec(href);
    const protocol = match ? match[1] : '';
    const host = match && match[2] ? match[2] : '';
    const path = match && match[3] ? match[3] : '';
    const search = match && match[4] ? match[4] : '';
    const hash = match && match[5] ? match[5] : '';
    const portIndex = host.lastIndexOf(':');
    const hostname = portIndex > -1 ? host.slice(0, portIndex) : host;
    const port = portIndex > -1 ? host.slice(portIndex + 1) : '';
    const pathname = path || (host ? '/' : '');
    const origin = protocol && host ? protocol + '//' + host : 'null';
    return { href, protocol, host, hostname, port, pathname, search, hash, origin };
  };

  const define = (name, value) => Object.defineProperty(globalThis, name, {
    value,
    configurable: true,
    enumerable: false,
    writable: true,
  });

  const createLocation = (href) => {
    const state = parseUrl(href);
    return Object.freeze({
      href: state.href,
      protocol: state.protocol,
      host: state.host,
      hostname: state.hostname,
      port: state.port,
      pathname: state.pathname,
      search: state.search,
      hash: state.hash,
      origin: state.origin,
      toString() { return state.href; },
    });
  };

  class HostURL {
    constructor(value) {
      Object.assign(this, parseUrl(value));
    }
    toString() {
      return this.href;
    }
  }

  const createStorage = () => {
    const data = new Map();
    return {
      get length() { return data.size; },
      key(index) { return Array.from(data.keys())[index] ?? null; },
      getItem(key) {
        key = String(key);
        return data.has(key) ? data.get(key) : null;
      },
      setItem(key, value) { data.set(String(key), String(value)); },
      removeItem(key) { data.delete(String(key)); },
      clear() { data.clear(); },
    };
  };

  define('location', createLocation($href));
  define('navigator', Object.freeze({ userAgent: $encodedUserAgent }));
  if (typeof globalThis.URL === 'undefined') {
    define('URL', HostURL);
  }
  if ($installStorage) {
    define('localStorage', createStorage());
    define('sessionStorage', createStorage());
  }
})()
''';
}
// ignore_for_file: public_member_api_docs
