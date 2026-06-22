import 'dart:async';
import 'dart:convert';

/// Loads an ES module source by its normalized module name.
///
/// Relative specifiers are normalized by [Quickjs] before the loader is called,
/// so a loader can use the incoming [moduleName] as its cache key. Returning
/// `null` means the module cannot be resolved.
typedef QuickjsModuleLoader = FutureOr<String?> Function(String moduleName);

/// Browser-like global aliases that can be explicitly installed into a runtime.
final class QuickjsBrowserGlobals {
  const QuickjsBrowserGlobals({this.window = false, this.self = false});

  /// Installs `globalThis.window = globalThis` when true.
  final bool window;

  /// Installs `globalThis.self = globalThis` when true.
  final bool self;

  bool get isEmpty => !window && !self;
}

/// Optional host capabilities exposed to JavaScript.
///
/// Capabilities are opt-in so a runtime does not expose browser or platform
/// objects unless the caller explicitly asks for them.
final class QuickjsHostCapabilities {
  const QuickjsHostCapabilities({
    this.browserGlobals = const QuickjsBrowserGlobals(),
  });

  /// No extra host capabilities.
  static const none = QuickjsHostCapabilities();

  /// Browser-like aliases for code that checks `window` or `self`.
  final QuickjsBrowserGlobals browserGlobals;

  bool get isEmpty => browserGlobals.isEmpty;
}

/// Startup/bootstrap JavaScript installed into every freshly-created runtime.
///
/// Host scripts are evaluated after the built-in console and explicit host
/// capabilities are installed. They are also re-evaluated if the runtime is
/// rebuilt after `stop()`. Use them for opt-in globals or polyfills such as
/// `crypto`, `Buffer`, `location`, or other application-specific objects.
final class QuickjsHostScript {
  const QuickjsHostScript({required this.name, required this.source});

  /// Source name used in QuickJS stack traces.
  final String name;

  /// JavaScript source to evaluate in the runtime.
  final String source;
}

/// JavaScript module source explicitly registered with a runtime.
///
/// ES modules are loaded when JavaScript imports [specifier]. CommonJS modules
/// are loaded when JavaScript requires [specifier] through [Quickjs.evalCommonJs].
final class QuickjsHostModule {
  const QuickjsHostModule({
    required this.specifier,
    required this.source,
    this.format = QuickjsHostModuleFormat.esModule,
  });

  /// Creates an ES module host module.
  const QuickjsHostModule.esModule({
    required String specifier,
    required String source,
  }) : this(
         specifier: specifier,
         source: source,
         format: QuickjsHostModuleFormat.esModule,
       );

  /// Creates a CommonJS host module.
  const QuickjsHostModule.commonJs({
    required String specifier,
    required String source,
  }) : this(
         specifier: specifier,
         source: source,
         format: QuickjsHostModuleFormat.commonJs,
       );

  /// Module specifier used by `import` or `require`.
  final String specifier;

  /// JavaScript source for the module.
  final String source;

  /// Module format.
  final QuickjsHostModuleFormat format;
}

/// Supported host module source formats.
enum QuickjsHostModuleFormat {
  /// ES module source for `import` / dynamic `import()`.
  esModule,

  /// CommonJS source for `require()`.
  commonJs,
}

/// Explicit host environment bundle.
///
/// This is a composable container for opt-in globals, startup scripts, and host
/// modules. It does not expose any browser, Node, network, or filesystem API by
/// itself; callers must pass concrete capabilities and sources explicitly.
final class QuickjsHostEnvironment {
  const QuickjsHostEnvironment({
    this.hostCapabilities = QuickjsHostCapabilities.none,
    this.hostScripts = const <QuickjsHostScript>[],
    this.hostModules = const <QuickjsHostModule>[],
  });

  /// Creates a minimal browser-like global environment.
  ///
  /// This installs `window` / `self` aliases by default plus small
  /// startup-script implementations for `location`, `navigator`, `URL`,
  /// `localStorage`, and `sessionStorage`. It does not install `fetch`, Web
  /// Crypto, DOM APIs, networking, or platform storage.
  factory QuickjsHostEnvironment.web({
    String locationHref = 'about:blank',
    String userAgent = 'QuickJS',
    bool window = true,
    bool self = true,
    bool storage = true,
  }) {
    return QuickjsHostEnvironment(
      hostCapabilities: QuickjsHostCapabilities(
        browserGlobals: QuickjsBrowserGlobals(window: window, self: self),
      ),
      hostScripts: <QuickjsHostScript>[
        QuickjsHostScript(
          name: 'host:web-globals.js',
          source: _webHostScriptSource(
            locationHref: locationHref,
            userAgent: userAgent,
            storage: storage,
          ),
        ),
      ],
    );
  }

  /// Creates a minimal Web Crypto-like global environment.
  ///
  /// This installs `globalThis.crypto` with synchronous compatibility helpers
  /// for `randomUUID()` and `getRandomValues()`. It does not install
  /// `crypto.subtle` and does not expose platform-native random sources yet.
  factory QuickjsHostEnvironment.webCrypto({
    bool randomUUID = true,
    bool getRandomValues = true,
  }) {
    return QuickjsHostEnvironment(
      hostScripts: <QuickjsHostScript>[
        QuickjsHostScript(
          name: 'host:web-crypto.js',
          source: _webCryptoHostScriptSource(
            randomUUID: randomUUID,
            getRandomValues: getRandomValues,
          ),
        ),
      ],
    );
  }

  /// Creates a small low-risk host environment for common utility APIs.
  ///
  /// The current essential preset installs `buffer` / `node:buffer` as both an
  /// ES module and a CommonJS module. Set [globalBuffer] to true to also install
  /// `globalThis.Buffer` as a startup global.
  factory QuickjsHostEnvironment.essential({bool globalBuffer = false}) {
    return QuickjsHostEnvironment(
      hostScripts: <QuickjsHostScript>[
        if (globalBuffer)
          const QuickjsHostScript(
            name: 'host:essential-buffer-global.js',
            source: _essentialBufferGlobalScript,
          ),
      ],
      hostModules: const <QuickjsHostModule>[
        QuickjsHostModule.esModule(
          specifier: 'buffer',
          source: _essentialBufferEsModuleSource,
        ),
        QuickjsHostModule.commonJs(
          specifier: 'buffer',
          source: _essentialBufferCommonJsSource,
        ),
      ],
    );
  }

  /// Creates a minimal Node-like module environment.
  ///
  /// This preset installs pure-JS host modules for `buffer`, `path`, `process`,
  /// and `timers`, all available through both bare and `node:` specifiers.
  /// `Buffer` and `process` are not installed as globals unless explicitly
  /// requested. It does not install Node `crypto`, `fs`, networking, or a full
  /// npm resolver.
  factory QuickjsHostEnvironment.node({
    bool globalBuffer = false,
    bool globalProcess = false,
    Map<String, String> env = const <String, String>{},
    String platform = 'quickjs',
    String cwd = '/',
  }) {
    final processCoreSource = _nodeProcessCoreSource(
      env: env,
      platform: platform,
      cwd: cwd,
    );
    return QuickjsHostEnvironment(
      hostScripts: <QuickjsHostScript>[
        if (globalBuffer)
          const QuickjsHostScript(
            name: 'host:node-buffer-global.js',
            source: _essentialBufferGlobalScript,
          ),
        if (globalProcess)
          QuickjsHostScript(
            name: 'host:node-process-global.js',
            source:
                '$processCoreSource\nObject.defineProperty(globalThis, "process", { value: process, configurable: true, enumerable: false, writable: true });\n',
          ),
      ],
      hostModules: <QuickjsHostModule>[
        const QuickjsHostModule.esModule(
          specifier: 'buffer',
          source: _essentialBufferEsModuleSource,
        ),
        const QuickjsHostModule.commonJs(
          specifier: 'buffer',
          source: _essentialBufferCommonJsSource,
        ),
        const QuickjsHostModule.esModule(
          specifier: 'path',
          source: _nodePathEsModuleSource,
        ),
        const QuickjsHostModule.commonJs(
          specifier: 'path',
          source: _nodePathCommonJsSource,
        ),
        QuickjsHostModule.esModule(
          specifier: 'process',
          source:
              '$processCoreSource\nexport const env = process.env;\nexport const platform = process.platform;\nexport const versions = process.versions;\nexport const cwd = process.cwd;\nexport default process;\n',
        ),
        QuickjsHostModule.commonJs(
          specifier: 'process',
          source: '$processCoreSource\nmodule.exports = process;\n',
        ),
        const QuickjsHostModule.esModule(
          specifier: 'timers',
          source: _nodeTimersEsModuleSource,
        ),
        const QuickjsHostModule.commonJs(
          specifier: 'timers',
          source: _nodeTimersCommonJsSource,
        ),
      ],
    );
  }

  /// Empty host environment bundle.
  static const empty = QuickjsHostEnvironment();

  /// Host capabilities installed before [hostScripts].
  final QuickjsHostCapabilities hostCapabilities;

  /// Startup/bootstrap scripts installed in list order.
  final List<QuickjsHostScript> hostScripts;

  /// Host modules available to `import` and `require`.
  final List<QuickjsHostModule> hostModules;
}

const _essentialBufferCoreSource = r'''
const textEncoder = typeof TextEncoder !== 'undefined' ? new TextEncoder() : null;
const textDecoder = typeof TextDecoder !== 'undefined' ? new TextDecoder() : null;

const encodeUtf8 = (value) => {
  const text = String(value);
  if (textEncoder) {
    return Array.from(textEncoder.encode(text));
  }
  const bytes = [];
  for (let i = 0; i < text.length; i++) {
    const code = text.charCodeAt(i);
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    }
  }
  return bytes;
};

const decodeUtf8 = (bytes) => {
  if (textDecoder) {
    return textDecoder.decode(new Uint8Array(bytes));
  }
  let text = '';
  for (const byte of bytes) {
    text += String.fromCharCode(byte);
  }
  return text;
};

class QuickjsBuffer extends Uint8Array {
  static from(value) {
    if (value instanceof ArrayBuffer) {
      return new QuickjsBuffer(value);
    }
    if (ArrayBuffer.isView(value) || Array.isArray(value)) {
      return new QuickjsBuffer(value);
    }
    return new QuickjsBuffer(encodeUtf8(value));
  }

  static alloc(length, fill = 0) {
    const buffer = new QuickjsBuffer(Number(length) || 0);
    buffer.fill(fill);
    return buffer;
  }

  static isBuffer(value) {
    return value instanceof QuickjsBuffer;
  }

  static byteLength(value) {
    return QuickjsBuffer.from(value).length;
  }

  toString(encoding = 'utf8') {
    if (encoding !== 'utf8' && encoding !== 'utf-8') {
      throw new Error('QuickJS Buffer only supports utf8 encoding');
    }
    return decodeUtf8(this);
  }
}

const Buffer = QuickjsBuffer;
''';

const _essentialBufferEsModuleSource =
    '$_essentialBufferCoreSource\nexport { Buffer };\nexport default Buffer;\n';

const _essentialBufferCommonJsSource =
    '$_essentialBufferCoreSource\nmodule.exports = { Buffer };\n';

const _essentialBufferGlobalScript =
    '$_essentialBufferCoreSource\nObject.defineProperty(globalThis, "Buffer", { value: Buffer, configurable: true, enumerable: false, writable: true });\n';

const _nodePathCoreSource = r'''
const normalizeParts = (parts, allowAboveRoot) => {
  const result = [];
  for (const part of parts) {
    if (!part || part === '.') {
      continue;
    }
    if (part === '..') {
      if (result.length && result[result.length - 1] !== '..') {
        result.pop();
      } else if (allowAboveRoot) {
        result.push('..');
      }
      continue;
    }
    result.push(part);
  }
  return result;
};

const normalize = (path) => {
  path = String(path);
  if (path.length === 0) {
    return '.';
  }
  const absolute = path.charCodeAt(0) === 47;
  const trailingSlash = path.length > 1 && path.endsWith('/');
  path = normalizeParts(path.split('/'), !absolute).join('/');
  if (!path && !absolute) {
    path = '.';
  }
  if (path && trailingSlash) {
    path += '/';
  }
  return (absolute ? '/' : '') + path;
};

const join = (...segments) => normalize(segments.filter((part) => part !== '').join('/'));

const dirname = (path) => {
  path = normalize(String(path));
  if (path === '/') {
    return '/';
  }
  const index = path.lastIndexOf('/');
  if (index < 0) {
    return '.';
  }
  if (index === 0) {
    return '/';
  }
  return path.slice(0, index);
};

const basename = (path, ext = '') => {
  path = normalize(String(path));
  const index = path.lastIndexOf('/');
  let base = index < 0 ? path : path.slice(index + 1);
  ext = String(ext || '');
  if (ext && base.endsWith(ext)) {
    base = base.slice(0, -ext.length);
  }
  return base;
};

const extname = (path) => {
  const base = basename(path);
  const index = base.lastIndexOf('.');
  return index > 0 ? base.slice(index) : '';
};

const path = {
  sep: '/',
  delimiter: ':',
  normalize,
  join,
  dirname,
  basename,
  extname,
  posix: null,
};
path.posix = path;
Object.freeze(path);
''';

const _nodePathEsModuleSource =
    '$_nodePathCoreSource\nexport const sep = path.sep;\nexport const delimiter = path.delimiter;\nexport { normalize, join, dirname, basename, extname };\nexport const posix = path;\nexport default path;\n';

const _nodePathCommonJsSource =
    '$_nodePathCoreSource\nmodule.exports = path;\n';

String _nodeProcessCoreSource({
  required Map<String, String> env,
  required String platform,
  required String cwd,
}) {
  final encodedEnv = jsonEncode(env);
  final encodedPlatform = jsonEncode(platform);
  final encodedCwd = jsonEncode(cwd);
  return '''
const process = Object.freeze({
  env: Object.assign(Object.create(null), $encodedEnv),
  platform: $encodedPlatform,
  versions: Object.freeze({ quickjs: '0.15.1' }),
  cwd() { return $encodedCwd; },
});
''';
}

const _nodeTimersEsModuleSource = r'''
export const setTimeout = globalThis.setTimeout;
export const clearTimeout = globalThis.clearTimeout;
export const setInterval = globalThis.setInterval;
export const clearInterval = globalThis.clearInterval;
export default { setTimeout, clearTimeout, setInterval, clearInterval };
''';

const _nodeTimersCommonJsSource = r'''
module.exports = {
  setTimeout: globalThis.setTimeout,
  clearTimeout: globalThis.clearTimeout,
  setInterval: globalThis.setInterval,
  clearInterval: globalThis.clearInterval,
};
''';

String _webCryptoHostScriptSource({
  required bool randomUUID,
  required bool getRandomValues,
}) {
  final installRandomUuid = randomUUID ? 'true' : 'false';
  final installGetRandomValues = getRandomValues ? 'true' : 'false';
  return '''
(() => {
  const crypto = (globalThis.crypto && typeof globalThis.crypto === 'object')
    ? globalThis.crypto
    : {};
  const define = (name, value) => Object.defineProperty(crypto, name, {
    value,
    configurable: true,
    enumerable: true,
    writable: true,
  });
  const randomByte = () => Math.floor(Math.random() * 256) & 0xff;
  const fillRandomBytes = (view) => {
    for (let i = 0; i < view.length; i++) {
      view[i] = randomByte();
    }
  };
  const assertIntegerTypedArray = (value) => {
    if (
      !value ||
      typeof value !== 'object' ||
      !ArrayBuffer.isView(value) ||
      value instanceof DataView ||
      value instanceof Float32Array ||
      value instanceof Float64Array
    ) {
      throw new TypeError('crypto.getRandomValues() requires an integer TypedArray');
    }
    if (value.byteLength > 65536) {
      throw new Error('crypto.getRandomValues() quota exceeded');
    }
    return value;
  };
  if ($installGetRandomValues) {
    define('getRandomValues', (array) => {
      const target = assertIntegerTypedArray(array);
      fillRandomBytes(new Uint8Array(target.buffer, target.byteOffset, target.byteLength));
      return target;
    });
  }
  if ($installRandomUuid) {
    const hex = [];
    for (let i = 0; i < 256; i++) {
      hex[i] = (i + 0x100).toString(16).slice(1);
    }
    define('randomUUID', () => {
      const bytes = new Uint8Array(16);
      fillRandomBytes(bytes);
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      return hex[bytes[0]] + hex[bytes[1]] + hex[bytes[2]] + hex[bytes[3]] + '-' +
        hex[bytes[4]] + hex[bytes[5]] + '-' +
        hex[bytes[6]] + hex[bytes[7]] + '-' +
        hex[bytes[8]] + hex[bytes[9]] + '-' +
        hex[bytes[10]] + hex[bytes[11]] + hex[bytes[12]] +
        hex[bytes[13]] + hex[bytes[14]] + hex[bytes[15]];
    });
  }
  Object.defineProperty(globalThis, 'crypto', {
    value: crypto,
    configurable: true,
    enumerable: false,
    writable: true,
  });
})()
''';
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

/// Resource and module-loading options used when creating a QuickJS runtime.
final class QuickjsRuntimeOptions {
  const QuickjsRuntimeOptions({
    this.memoryLimitBytes,
    this.stackLimitBytes,
    this.moduleLoader,
    this.hostCapabilities = QuickjsHostCapabilities.none,
    this.hostScripts = const <QuickjsHostScript>[],
    this.hostModules = const <QuickjsHostModule>[],
    this.hostEnvironments = const <QuickjsHostEnvironment>[],
  });

  /// Maximum memory for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Exceeding the limit is reported as
  /// `JsOutOfMemoryException` by the public API.
  final int? memoryLimitBytes;

  /// Maximum native call stack for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Native uses `JS_SetMaxStackSize`; the
  /// current web backend does not expose an equivalent WASM option yet.
  final int? stackLimitBytes;

  /// Runtime-scoped ES module source loader.
  ///
  /// [Quickjs.evalModule] uses this loader to prebuild the dependency graph
  /// before sending a module evaluation request to the native isolate or web
  /// worker.
  final QuickjsModuleLoader? moduleLoader;

  /// Explicit host capabilities installed into this runtime.
  ///
  /// Defaults to [QuickjsHostCapabilities.none].
  final QuickjsHostCapabilities hostCapabilities;

  /// User-provided JavaScript installed into this runtime at creation time.
  ///
  /// Defaults to an empty list. Scripts are installed in list order.
  final List<QuickjsHostScript> hostScripts;

  /// User-provided modules available to `import` and `require`.
  ///
  /// Defaults to an empty list. Host module specifiers are runtime-scoped.
  final List<QuickjsHostModule> hostModules;

  /// User-provided host environment bundles.
  ///
  /// Bundles are expanded before direct [hostScripts] and [hostModules]. Direct
  /// [hostCapabilities] are merged with bundle capabilities.
  final List<QuickjsHostEnvironment> hostEnvironments;
}
