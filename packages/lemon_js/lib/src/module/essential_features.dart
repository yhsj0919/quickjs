part of '../runtime/runtime_options.dart';

/// 提供低风险常用模块，当前包含 ES Module 与 CommonJS 的 Buffer。
final class EssentialFeatures extends JsFeatures {
  EssentialFeatures({bool globalBuffer = false})
    : super(
        name: 'essential',
        scripts: <JsScript>[
          if (globalBuffer)
            const JsScript(
              name: 'host:essential-buffer-global.js',
              globals: <String>['Buffer'],
              source: _essentialBufferGlobalScript,
            ),
        ],
        modules: const <JsModule>[
          JsModule(name: 'buffer', source: _essentialBufferEsModuleSource),
          JsModule.commonJs(
            name: 'buffer',
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
    let code = text.codePointAt(i);
    if (code > 0xffff) i++;
    if (code >= 0xd800 && code <= 0xdfff) code = 0xfffd;
    if (code < 0x80) {
      bytes.push(code);
    } else if (code < 0x800) {
      bytes.push(0xc0 | (code >> 6), 0x80 | (code & 0x3f));
    } else if (code < 0x10000) {
      bytes.push(0xe0 | (code >> 12), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
    } else {
      bytes.push(0xf0 | (code >> 18), 0x80 | ((code >> 12) & 0x3f), 0x80 | ((code >> 6) & 0x3f), 0x80 | (code & 0x3f));
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

class JsBuffer extends Uint8Array {
  static from(value, encoding = 'utf8', length) {
    if (value instanceof ArrayBuffer) {
      return new JsBuffer(value, typeof encoding === 'number' ? encoding : 0, length);
    }
    if (ArrayBuffer.isView(value) || Array.isArray(value)) {
      return new JsBuffer(value);
    }
    encoding = String(encoding).toLowerCase();
    if (encoding === 'hex') {
      const pairs = String(value).match(/^[0-9a-f]*/i)[0].match(/../g) || [];
      return new JsBuffer(pairs.map(pair => parseInt(pair, 16)));
    }
    if (encoding === 'base64') {
      const alphabet = 'ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/';
      const text = String(value).split('=')[0].replace(/-/g, '+').replace(/_/g, '/');
      const bytes = [];
      let bits = 0, count = 0;
      for (const char of text) {
        const digit = alphabet.indexOf(char);
        if (digit < 0) continue;
        bits = (bits << 6) | digit;
        count += 6;
        if (count >= 8) { count -= 8; bytes.push((bits >>> count) & 255); }
      }
      return new JsBuffer(bytes);
    }
    if (encoding !== 'utf8' && encoding !== 'utf-8') throw new TypeError('Unknown encoding: ' + encoding);
    return new JsBuffer(encodeUtf8(value));
  }

  static alloc(length, fill = 0) {
    const buffer = new JsBuffer(Number(length) || 0);
    buffer.fill(fill);
    return buffer;
  }

  static isBuffer(value) {
    return value instanceof JsBuffer ||
      value instanceof Uint8Array && value.constructor && value.constructor.name === 'JsBuffer';
  }

  static byteLength(value, encoding = 'utf8') {
    if (value instanceof ArrayBuffer || ArrayBuffer.isView(value)) return value.byteLength;
    return JsBuffer.from(value, encoding).length;
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

const Buffer = JsBuffer;
''';

const _essentialBufferEsModuleSource =
    '$_essentialBufferCoreSource\nexport { Buffer };\nexport default Buffer;\n';

const _essentialBufferCommonJsSource =
    '$_essentialBufferCoreSource\nmodule.exports = { Buffer };\n';

const _essentialBufferGlobalScript =
    '$_essentialBufferCoreSource\nObject.defineProperty(globalThis, "Buffer", { value: Buffer, configurable: true, enumerable: false, writable: true });\n';
// ignore_for_file: public_member_api_docs
