part of '../runtime/quickjs_runtime_options.dart';

QuickjsHostMount _quickjsEssentialHostMount({required bool globalBuffer}) {
  return QuickjsHostMount(
    name: 'essential',
    environmentPatches: <QuickjsHostScript>[
      if (globalBuffer)
        const QuickjsHostScript.js(
          name: 'host:essential-buffer-global.js',
          globals: <String>['Buffer'],
          source: _essentialBufferGlobalScript,
        ),
    ],
    modules: const <QuickjsHostModule>[
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
    return value instanceof QuickjsBuffer ||
      value instanceof Uint8Array && value.constructor && value.constructor.name === 'QuickjsBuffer';
  }

  static byteLength(value) {
    return QuickjsBuffer.from(value).length;
  }

  toString(encoding = 'utf8') {
    encoding = String(encoding || 'utf8').toLowerCase();
    if (encoding === 'hex') {
      let text = '';
      for (const byte of this) text += byte.toString(16).padStart(2, '0');
      return text;
    }
    if (encoding === 'base64') {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      let text = '';
      for (let i = 0; i < this.length; i += 3) {
        const a = this[i];
        const b = i + 1 < this.length ? this[i + 1] : 0;
        const c = i + 2 < this.length ? this[i + 2] : 0;
        const triple = (a << 16) | (b << 8) | c;
        text += alphabet[(triple >> 18) & 63];
        text += alphabet[(triple >> 12) & 63];
        text += i + 1 < this.length ? alphabet[(triple >> 6) & 63] : '=';
        text += i + 2 < this.length ? alphabet[triple & 63] : '=';
      }
      return text;
    }
    if (encoding !== 'utf8' && encoding !== 'utf-8') {
      throw new Error('QuickJS Buffer only supports utf8, hex, and base64 encoding');
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
