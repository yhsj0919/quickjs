import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart' as dart_crypto;

import '../runtime/quickjs_runtime_options.dart';

const _digestProviderName = 'webcrypto.subtle.digest';

/// Optional Web Crypto compatibility mount.
///
/// This preset is separate from the runtime core. `randomUUID()` and
/// `getRandomValues()` are JavaScript compatibility implementations, while
/// `subtle.digest()` uses Dart's `package:crypto` through an async provider.
final class QuickjsWebCryptoMount extends QuickjsHostMount {
  QuickjsWebCryptoMount({
    bool randomUUID = true,
    bool getRandomValues = true,
    bool subtleDigest = false,
  }) : super(
         name: 'web-crypto',
         environmentPatches: <QuickjsHostScript>[
           QuickjsHostScript(
             name: 'host:web-crypto.js',
             globals: const <String>['crypto'],
             source: _webCryptoHostScriptSource(
               randomUUID: randomUUID,
               getRandomValues: getRandomValues,
               subtleDigest: subtleDigest,
               digestProviderName: subtleDigest ? _digestProviderName : null,
             ),
           ),
         ],
         providers: <QuickjsHostProvider>[if (subtleDigest) _digestProvider],
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

String _webCryptoHostScriptSource({
  required bool randomUUID,
  required bool getRandomValues,
  required bool subtleDigest,
  required String? digestProviderName,
}) {
  final installRandomUuid = randomUUID ? 'true' : 'false';
  final installGetRandomValues = getRandomValues ? 'true' : 'false';
  final installSubtleDigest = subtleDigest ? 'true' : 'false';
  final encodedDigestProviderName = jsonEncode(digestProviderName);
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
