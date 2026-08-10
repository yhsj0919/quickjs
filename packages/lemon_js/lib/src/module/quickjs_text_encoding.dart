part of '../runtime/quickjs.dart';

String _wrapInstallTextEncoding() {
  return r'''
(() => {
  if (typeof globalThis.TextEncoder === 'undefined') {
    class QuickjsTextEncoder {
      get encoding() {
        return 'utf-8';
      }

      encode(input = '') {
        const text = String(input);
        const bytes = [];
        for (let i = 0; i < text.length; i++) {
          let codePoint = text.charCodeAt(i);
          if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
            const next = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
            if (next >= 0xdc00 && next <= 0xdfff) {
              codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (next - 0xdc00);
              i++;
            } else {
              codePoint = 0xfffd;
            }
          } else if (codePoint >= 0xdc00 && codePoint <= 0xdfff) {
            codePoint = 0xfffd;
          }
          if (codePoint <= 0x7f) {
            bytes.push(codePoint);
          } else if (codePoint <= 0x7ff) {
            bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
          } else if (codePoint <= 0xffff) {
            bytes.push(
              0xe0 | (codePoint >> 12),
              0x80 | ((codePoint >> 6) & 0x3f),
              0x80 | (codePoint & 0x3f),
            );
          } else {
            bytes.push(
              0xf0 | (codePoint >> 18),
              0x80 | ((codePoint >> 12) & 0x3f),
              0x80 | ((codePoint >> 6) & 0x3f),
              0x80 | (codePoint & 0x3f),
            );
          }
        }
        return new Uint8Array(bytes);
      }

      encodeInto(source, destination) {
        if (!(destination instanceof Uint8Array)) {
          throw new TypeError('TextEncoder.encodeInto() destination must be a Uint8Array');
        }
        const text = String(source);
        let read = 0;
        let written = 0;
        for (let i = 0; i < text.length; i++) {
          const before = i;
          let codePoint = text.charCodeAt(i);
          if (codePoint >= 0xd800 && codePoint <= 0xdbff) {
            const next = i + 1 < text.length ? text.charCodeAt(i + 1) : 0;
            if (next >= 0xdc00 && next <= 0xdfff) {
              codePoint = 0x10000 + ((codePoint - 0xd800) << 10) + (next - 0xdc00);
              i++;
            } else {
              codePoint = 0xfffd;
            }
          } else if (codePoint >= 0xdc00 && codePoint <= 0xdfff) {
            codePoint = 0xfffd;
          }
          const bytes = [];
          if (codePoint <= 0x7f) {
            bytes.push(codePoint);
          } else if (codePoint <= 0x7ff) {
            bytes.push(0xc0 | (codePoint >> 6), 0x80 | (codePoint & 0x3f));
          } else if (codePoint <= 0xffff) {
            bytes.push(
              0xe0 | (codePoint >> 12),
              0x80 | ((codePoint >> 6) & 0x3f),
              0x80 | (codePoint & 0x3f),
            );
          } else {
            bytes.push(
              0xf0 | (codePoint >> 18),
              0x80 | ((codePoint >> 12) & 0x3f),
              0x80 | ((codePoint >> 6) & 0x3f),
              0x80 | (codePoint & 0x3f),
            );
          }
          if (written + bytes.length > destination.length) {
            break;
          }
          destination.set(bytes, written);
          written += bytes.length;
          read += i - before + 1;
        }
        return { read, written };
      }
    }
    Object.defineProperty(globalThis, 'TextEncoder', {
      value: QuickjsTextEncoder,
      configurable: true,
      enumerable: false,
      writable: true,
    });
  }

  if (typeof globalThis.TextDecoder === 'undefined') {
    const normalizeInput = (input) => {
      if (input === undefined) return new Uint8Array(0);
      if (input instanceof ArrayBuffer) return new Uint8Array(input);
      if (ArrayBuffer.isView(input)) {
        return new Uint8Array(input.buffer, input.byteOffset, input.byteLength);
      }
      throw new TypeError('TextDecoder.decode() input must be an ArrayBuffer or typed array');
    };

    class QuickjsTextDecoder {
      constructor(label = 'utf-8', options = {}) {
        const normalized = String(label || 'utf-8').toLowerCase();
        if (normalized !== 'utf-8' && normalized !== 'utf8') {
          throw new RangeError('QuickJS TextDecoder only supports utf-8');
        }
        this._fatal = Boolean(options && options.fatal);
        this._ignoreBOM = Boolean(options && options.ignoreBOM);
      }

      get encoding() {
        return 'utf-8';
      }

      get fatal() {
        return this._fatal;
      }

      get ignoreBOM() {
        return this._ignoreBOM;
      }

      decode(input = undefined, options = {}) {
        if (options && options.stream) {
          throw new TypeError('QuickJS TextDecoder does not support streaming decode');
        }
        const bytes = normalizeInput(input);
        let index = 0;
        if (
          !this._ignoreBOM &&
          bytes.length >= 3 &&
          bytes[0] === 0xef &&
          bytes[1] === 0xbb &&
          bytes[2] === 0xbf
        ) {
          index = 3;
        }
        let text = '';
        const replacement = () => {
          if (this._fatal) {
            throw new TypeError('The encoded data was not valid utf-8');
          }
          return '\ufffd';
        };
        while (index < bytes.length) {
          const first = bytes[index++];
          let codePoint = 0;
          let needed = 0;
          let min = 0;
          if (first <= 0x7f) {
            codePoint = first;
          } else if (first >= 0xc2 && first <= 0xdf) {
            codePoint = first & 0x1f;
            needed = 1;
            min = 0x80;
          } else if (first >= 0xe0 && first <= 0xef) {
            codePoint = first & 0x0f;
            needed = 2;
            min = 0x800;
          } else if (first >= 0xf0 && first <= 0xf4) {
            codePoint = first & 0x07;
            needed = 3;
            min = 0x10000;
          } else {
            text += replacement();
            continue;
          }
          if (index + needed > bytes.length) {
            text += replacement();
            break;
          }
          let valid = true;
          for (let i = 0; i < needed; i++) {
            const next = bytes[index++];
            if ((next & 0xc0) !== 0x80) {
              valid = false;
              index--;
              break;
            }
            codePoint = (codePoint << 6) | (next & 0x3f);
          }
          if (
            !valid ||
            codePoint < min ||
            codePoint > 0x10ffff ||
            (codePoint >= 0xd800 && codePoint <= 0xdfff)
          ) {
            text += replacement();
            continue;
          }
          if (codePoint <= 0xffff) {
            text += String.fromCharCode(codePoint);
          } else {
            codePoint -= 0x10000;
            text += String.fromCharCode(
              0xd800 + (codePoint >> 10),
              0xdc00 + (codePoint & 0x3ff),
            );
          }
        }
        return text;
      }
    }
    Object.defineProperty(globalThis, 'TextDecoder', {
      value: QuickjsTextDecoder,
      configurable: true,
      enumerable: false,
      writable: true,
    });
  }
})()
''';
}
