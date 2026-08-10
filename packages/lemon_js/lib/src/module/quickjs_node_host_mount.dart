part of '../runtime/quickjs_runtime_options.dart';

QuickjsHostMount _quickjsNodeHostMount({
  required bool globalBuffer,
  required bool globalProcess,
  required Map<String, String> env,
  required String platform,
  required String cwd,
}) {
  final processCoreSource = _nodeProcessCoreSource(
    env: env,
    platform: platform,
    cwd: cwd,
  );
  return QuickjsHostMount(
    name: 'node',
    environmentPatches: <QuickjsHostScript>[
      if (globalBuffer)
        const QuickjsHostScript.js(
          name: 'host:node-buffer-global.js',
          globals: <String>['Buffer'],
          source: _essentialBufferGlobalScript,
        ),
      if (globalProcess)
        QuickjsHostScript.js(
          name: 'host:node-process-global.js',
          globals: const <String>['process'],
          source:
              '$processCoreSource\nObject.defineProperty(globalThis, "process", { value: process, configurable: true, enumerable: false, writable: true });\n',
        ),
    ],
    modules: <QuickjsHostModule>[
      const QuickjsHostModule.esModule(
        specifier: 'buffer',
        source: _essentialBufferEsModuleSource,
      ),
      const QuickjsHostModule.commonJs(
        specifier: 'buffer',
        source: _essentialBufferCommonJsSource,
      ),
      const QuickjsHostModule.esModule(
        specifier: 'crypto',
        source: _nodeCryptoEsModuleSource,
      ),
      const QuickjsHostModule.commonJs(
        specifier: 'crypto',
        source: _nodeCryptoCommonJsSource,
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

const _nodeCryptoCoreSource =
    '''
$_essentialBufferCoreSource

const rotr = (value, bits) => (value >>> bits) | (value << (32 - bits));
const sha256Constants = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

const bytesFrom = (value) => {
  if (value instanceof QuickjsBuffer) return Array.from(value);
  if (typeof value === 'string') return encodeUtf8(value);
  if (value instanceof ArrayBuffer) return Array.from(new Uint8Array(value));
  if (ArrayBuffer.isView(value) || Array.isArray(value)) return Array.from(value);
  throw new TypeError('crypto input must be a string, Buffer, ArrayBuffer, or TypedArray');
};

const randomBytesArray = (size) => {
  size = Number(size);
  if (!Number.isFinite(size) || size < 0 || Math.floor(size) !== size) {
    throw new RangeError('crypto random byte size must be a non-negative integer');
  }
  const bytes = new Uint8Array(size);
  const webCrypto = globalThis.crypto;
  if (webCrypto && typeof webCrypto.getRandomValues === 'function') {
    webCrypto.getRandomValues(bytes);
  } else {
    for (let i = 0; i < bytes.length; i++) {
      bytes[i] = Math.floor(Math.random() * 256) & 0xff;
    }
  }
  return bytes;
};

const sha256 = (input) => {
  const bytes = bytesFrom(input);
  const bitLength = bytes.length * 8;
  bytes.push(0x80);
  while ((bytes.length % 64) !== 56) bytes.push(0);
  const high = Math.floor(bitLength / 0x100000000);
  const low = bitLength >>> 0;
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((high >>> shift) & 0xff);
  for (let shift = 24; shift >= 0; shift -= 8) bytes.push((low >>> shift) & 0xff);

  const hash = [
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a,
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  const words = new Array(64);
  for (let offset = 0; offset < bytes.length; offset += 64) {
    for (let i = 0; i < 16; i++) {
      const j = offset + i * 4;
      words[i] = ((bytes[j] << 24) | (bytes[j + 1] << 16) | (bytes[j + 2] << 8) | bytes[j + 3]) >>> 0;
    }
    for (let i = 16; i < 64; i++) {
      const s0 = (rotr(words[i - 15], 7) ^ rotr(words[i - 15], 18) ^ (words[i - 15] >>> 3)) >>> 0;
      const s1 = (rotr(words[i - 2], 17) ^ rotr(words[i - 2], 19) ^ (words[i - 2] >>> 10)) >>> 0;
      words[i] = (words[i - 16] + s0 + words[i - 7] + s1) >>> 0;
    }
    let [a, b, c, d, e, f, g, h] = hash;
    for (let i = 0; i < 64; i++) {
      const s1 = (rotr(e, 6) ^ rotr(e, 11) ^ rotr(e, 25)) >>> 0;
      const ch = ((e & f) ^ (~e & g)) >>> 0;
      const temp1 = (h + s1 + ch + sha256Constants[i] + words[i]) >>> 0;
      const s0 = (rotr(a, 2) ^ rotr(a, 13) ^ rotr(a, 22)) >>> 0;
      const maj = ((a & b) ^ (a & c) ^ (b & c)) >>> 0;
      const temp2 = (s0 + maj) >>> 0;
      h = g;
      g = f;
      f = e;
      e = (d + temp1) >>> 0;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) >>> 0;
    }
    hash[0] = (hash[0] + a) >>> 0;
    hash[1] = (hash[1] + b) >>> 0;
    hash[2] = (hash[2] + c) >>> 0;
    hash[3] = (hash[3] + d) >>> 0;
    hash[4] = (hash[4] + e) >>> 0;
    hash[5] = (hash[5] + f) >>> 0;
    hash[6] = (hash[6] + g) >>> 0;
    hash[7] = (hash[7] + h) >>> 0;
  }
  const out = [];
  for (const word of hash) {
    out.push((word >>> 24) & 0xff, (word >>> 16) & 0xff, (word >>> 8) & 0xff, word & 0xff);
  }
  return new QuickjsBuffer(out);
};

class QuickjsHash {
  constructor(algorithm) {
    this.algorithm = String(algorithm || '').toLowerCase().replace(/[-_]/g, '');
    if (this.algorithm !== 'sha256') {
      throw new Error('QuickJS node:crypto only supports sha256 hashes');
    }
    this._chunks = [];
    this._digested = false;
  }
  update(data) {
    if (this._digested) throw new Error('Hash digest already called');
    this._chunks.push(...bytesFrom(data));
    return this;
  }
  digest(encoding) {
    if (this._digested) throw new Error('Hash digest already called');
    this._digested = true;
    const result = sha256(this._chunks);
    return encoding ? result.toString(encoding) : result;
  }
}

const randomBytes = (size) => new QuickjsBuffer(randomBytesArray(size));
const createHash = (algorithm) => new QuickjsHash(algorithm);
const crypto = Object.freeze({ randomBytes, createHash });
''';

const _nodeCryptoEsModuleSource =
    '$_nodeCryptoCoreSource\nexport { randomBytes, createHash };\nexport default crypto;\n';

const _nodeCryptoCommonJsSource =
    '$_nodeCryptoCoreSource\nmodule.exports = crypto;\n';

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
