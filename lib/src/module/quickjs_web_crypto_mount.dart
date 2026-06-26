import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;

import '../runtime/quickjs_runtime_options.dart';

const _digestProviderName = 'webcrypto.subtle.digest';
const _hmacProviderName = 'webcrypto.subtle.hmac';

/// Optional Web Crypto compatibility mount.
///
/// This preset is separate from the runtime core. `randomUUID()` and
/// `getRandomValues()` prefer a native Web Crypto random source, while
/// `subtle.digest()` and HMAC use Dart's `package:crypto` through async
/// providers.
final class QuickjsWebCryptoMount extends QuickjsHostMount {
  QuickjsWebCryptoMount({
    bool randomUUID = true,
    bool getRandomValues = true,
    bool allowInsecureRandomFallback = false,
    bool subtleDigest = false,
    bool subtleHmac = false,
  }) : super(
         name: 'web-crypto',
         environmentPatches: <QuickjsHostScript>[
           QuickjsHostScript(
             name: 'host:web-crypto.js',
             globals: const <String>['crypto'],
             source: _webCryptoHostScriptSource(
               randomUUID: randomUUID,
               getRandomValues: getRandomValues,
               allowInsecureRandomFallback: allowInsecureRandomFallback,
               subtleDigest: subtleDigest,
               subtleHmac: subtleHmac,
               digestProviderName: subtleDigest ? _digestProviderName : null,
               hmacProviderName: subtleHmac ? _hmacProviderName : null,
             ),
           ),
         ],
         providers: <QuickjsHostProvider>[
           if (subtleDigest) _digestProvider,
           if (subtleHmac) _hmacProvider,
         ],
       );
}

final QuickjsHostProvider _digestProvider = QuickjsHostProvider.async(
  name: _digestProviderName,
  debugName: 'host:webcrypto.subtle.digest',
  implementation: QuickjsHostProviderImplementation.dart,
  callback: (args, context) async {
    context.throwIfCancelled();
    final algorithm = args.isNotEmpty ? '${args[0]}' : '';
    final data = args.length > 1 ? args[1] : null;
    if (data is! Uint8List) {
      throw ArgumentError('crypto.subtle.digest() data must be bytes');
    }
    final digest = _digestBytes(algorithm, data);
    return Uint8List.fromList(digest.bytes);
  },
);

final QuickjsHostProvider _hmacProvider = QuickjsHostProvider.async(
  name: _hmacProviderName,
  debugName: 'host:webcrypto.subtle.hmac',
  implementation: QuickjsHostProviderImplementation.dart,
  callback: (args, context) async {
    context.throwIfCancelled();
    final algorithm = args.isNotEmpty ? '${args[0]}' : '';
    final key = args.length > 1 ? args[1] : null;
    final data = args.length > 2 ? args[2] : null;
    if (key is! Uint8List || data is! Uint8List) {
      throw ArgumentError('crypto.subtle HMAC requires byte key and data');
    }
    final hmac = _hmacBytes(algorithm, key, data);
    return Uint8List.fromList(hmac.bytes);
  },
);

dart_crypto.Digest _digestBytes(String algorithm, Uint8List data) {
  final normalized = algorithm.toUpperCase().replaceAll('_', '-');
  return switch (normalized) {
    'SHA-1' || 'SHA1' => dart_crypto.sha1.convert(data),
    'SHA-256' || 'SHA256' => dart_crypto.sha256.convert(data),
    'SHA-384' || 'SHA384' => dart_crypto.sha384.convert(data),
    'SHA-512' || 'SHA512' => dart_crypto.sha512.convert(data),
    _ => throw ArgumentError(
      'Unsupported crypto.subtle.digest() algorithm: $algorithm',
    ),
  };
}

dart_crypto.Digest _hmacBytes(String algorithm, Uint8List key, Uint8List data) {
  final normalized = algorithm.toUpperCase().replaceAll('_', '-');
  final digest = switch (normalized) {
    'SHA-1' || 'SHA1' => dart_crypto.sha1,
    'SHA-256' || 'SHA256' => dart_crypto.sha256,
    _ => throw ArgumentError(
      'Unsupported crypto.subtle HMAC hash algorithm: $algorithm',
    ),
  };
  return dart_crypto.Hmac(digest, key).convert(data);
}

String _webCryptoHostScriptSource({
  required bool randomUUID,
  required bool getRandomValues,
  required bool allowInsecureRandomFallback,
  required bool subtleDigest,
  required bool subtleHmac,
  required String? digestProviderName,
  required String? hmacProviderName,
}) {
  final installRandomUuid = randomUUID ? 'true' : 'false';
  final installGetRandomValues = getRandomValues ? 'true' : 'false';
  final useInsecureRandomFallback = allowInsecureRandomFallback
      ? 'true'
      : 'false';
  final installSubtleDigest = subtleDigest ? 'true' : 'false';
  final installSubtleHmac = subtleHmac ? 'true' : 'false';
  final encodedDigestProviderName = jsonEncode(digestProviderName);
  final encodedHmacProviderName = jsonEncode(hmacProviderName);
  return '''
(() => {
  const nativeCrypto = (globalThis.crypto && typeof globalThis.crypto === 'object')
    ? globalThis.crypto
    : null;
  const nativeGetRandomValues = nativeCrypto && typeof nativeCrypto.getRandomValues === 'function'
    ? nativeCrypto.getRandomValues.bind(nativeCrypto)
    : null;
  const crypto = nativeCrypto
    ? nativeCrypto
    : {};
  const define = (name, value) => Object.defineProperty(crypto, name, {
    value,
    configurable: true,
    enumerable: true,
    writable: true,
  });
  const randomByte = () => Math.floor(Math.random() * 256) & 0xff;
  const fillRandomBytes = (view) => {
    if (nativeGetRandomValues) {
      nativeGetRandomValues(view);
      return;
    }
    if (!$useInsecureRandomFallback) {
      throw new Error('crypto secure random source is not available');
    }
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
  if ($installSubtleDigest) {
    const providers = globalThis.__quickjsHostProviders;
    const digestProviderName = $encodedDigestProviderName;
    const digestProvider = providers && digestProviderName ? providers[digestProviderName] : null;
    if (typeof digestProvider !== 'function') {
      throw new Error('crypto.subtle.digest() requires a Flutter crypto backend');
    }
    const subtle = (crypto.subtle && typeof crypto.subtle === 'object')
      ? crypto.subtle
      : {};
    Object.defineProperty(subtle, 'digest', {
      value: (algorithm, data) => {
        const name = typeof algorithm === 'string'
          ? algorithm
          : algorithm && typeof algorithm.name === 'string'
            ? algorithm.name
            : '';
        if (!data || (typeof data !== 'object') || !ArrayBuffer.isView(data) && !(data instanceof ArrayBuffer)) {
          return Promise.reject(new TypeError('crypto.subtle.digest() requires BufferSource data'));
        }
        const bytes = data instanceof ArrayBuffer
          ? new Uint8Array(data)
          : new Uint8Array(data.buffer, data.byteOffset, data.byteLength);
        return digestProvider(name, bytes).then((result) => {
          const out = result instanceof Uint8Array
            ? result
            : new Uint8Array(result.buffer, result.byteOffset, result.byteLength);
          return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength);
        });
      },
      configurable: true,
      enumerable: true,
      writable: true,
    });
    Object.defineProperty(crypto, 'subtle', {
      value: subtle,
      configurable: true,
      enumerable: true,
      writable: true,
    });
  }
  if ($installSubtleHmac) {
    const providers = globalThis.__quickjsHostProviders;
    const hmacProviderName = $encodedHmacProviderName;
    const hmacProvider = providers && hmacProviderName ? providers[hmacProviderName] : null;
    if (typeof hmacProvider !== 'function') {
      throw new Error('crypto.subtle HMAC requires a Flutter crypto backend');
    }
    const subtle = (crypto.subtle && typeof crypto.subtle === 'object')
      ? crypto.subtle
      : {};
    const toBytes = (value, label) => {
      if (!value || (typeof value !== 'object') || !ArrayBuffer.isView(value) && !(value instanceof ArrayBuffer)) {
        throw new TypeError(label + ' must be BufferSource data');
      }
      return value instanceof ArrayBuffer
        ? new Uint8Array(value)
        : new Uint8Array(value.buffer, value.byteOffset, value.byteLength);
    };
    const normalizeHashName = (hash) => typeof hash === 'string'
      ? hash
      : hash && typeof hash.name === 'string'
        ? hash.name
        : '';
    const normalizeHmacAlgorithm = (algorithm) => {
      if (!algorithm || typeof algorithm !== 'object' || String(algorithm.name || '').toUpperCase() !== 'HMAC') {
        throw new Error('crypto.subtle only supports HMAC keys in this mount');
      }
      const hash = normalizeHashName(algorithm.hash);
      if (!hash) {
        throw new Error('crypto.subtle HMAC requires a hash algorithm');
      }
      return { name: 'HMAC', hash: { name: hash } };
    };
    const timingSafeEqual = (left, right) => {
      if (left.byteLength !== right.byteLength) return false;
      let diff = 0;
      for (let i = 0; i < left.byteLength; i++) diff |= left[i] ^ right[i];
      return diff === 0;
    };
    const previousImportKey = subtle.importKey;
    const previousSign = subtle.sign;
    const previousVerify = subtle.verify;
    Object.defineProperty(subtle, 'importKey', {
      value: (format, keyData, algorithm, extractable, keyUsages = []) => {
        if (String(format) !== 'raw') {
          if (typeof previousImportKey === 'function') {
            return previousImportKey.call(subtle, format, keyData, algorithm, extractable, keyUsages);
          }
          return Promise.reject(new Error('crypto.subtle.importKey() only supports raw HMAC keys'));
        }
        let normalized;
        try {
          normalized = normalizeHmacAlgorithm(algorithm);
          const keyBytes = toBytes(keyData, 'crypto.subtle.importKey() keyData');
          return Promise.resolve(Object.freeze({
            type: 'secret',
            extractable: Boolean(extractable),
            algorithm: normalized,
            usages: Array.from(keyUsages),
            __quickjsHmacKeyBytes: new Uint8Array(keyBytes),
          }));
        } catch (error) {
          return Promise.reject(error);
        }
      },
      configurable: true,
      enumerable: true,
      writable: true,
    });
    Object.defineProperty(subtle, 'sign', {
      value: (algorithm, key, data) => {
        if (!key || !key.__quickjsHmacKeyBytes) {
          if (typeof previousSign === 'function') return previousSign.call(subtle, algorithm, key, data);
          return Promise.reject(new Error('crypto.subtle.sign() requires an HMAC CryptoKey'));
        }
        const hash = normalizeHashName((algorithm && algorithm.hash) || key.algorithm.hash);
        let bytes;
        try {
          bytes = toBytes(data, 'crypto.subtle.sign() data');
        } catch (error) {
          return Promise.reject(error);
        }
        return hmacProvider(hash, key.__quickjsHmacKeyBytes, bytes).then((result) => {
          const out = result instanceof Uint8Array
            ? result
            : new Uint8Array(result.buffer, result.byteOffset, result.byteLength);
          return out.buffer.slice(out.byteOffset, out.byteOffset + out.byteLength);
        });
      },
      configurable: true,
      enumerable: true,
      writable: true,
    });
    Object.defineProperty(subtle, 'verify', {
      value: async (algorithm, key, signature, data) => {
        if (!key || !key.__quickjsHmacKeyBytes) {
          if (typeof previousVerify === 'function') return previousVerify.call(subtle, algorithm, key, signature, data);
          throw new Error('crypto.subtle.verify() requires an HMAC CryptoKey');
        }
        const expected = new Uint8Array(await subtle.sign(algorithm, key, data));
        const actual = toBytes(signature, 'crypto.subtle.verify() signature');
        return timingSafeEqual(expected, actual);
      },
      configurable: true,
      enumerable: true,
      writable: true,
    });
    Object.defineProperty(crypto, 'subtle', {
      value: subtle,
      configurable: true,
      enumerable: true,
      writable: true,
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
