import 'dart:convert';

import 'package:crypto/crypto.dart' as crypto;
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';

void main() {
  for (final execution in JsExecution.values) {
    test('Node hashes and Buffer encodings: ${execution.name}', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
        features: [NodeFeatures()],
      );
      addTearDown(engine.dispose);
      await engine.runModule('''
import { Buffer } from 'node:buffer';
import { createHash } from 'node:crypto';
globalThis.check = (text, algorithm) => {
  const encoded = Buffer.from(text).toString('base64');
  const hash = createHash(algorithm).update(encoded, 'base64').digest('hex');
  if (typeof hash !== 'string') throw new Error('digest must be synchronous');
  return [hash, Buffer.from(encoded, 'base64').toString()];
};
''', name: 'hash-check.mjs');
      for (final text in ['', 'abc', '中文🎵', 'a' * 1000]) {
        for (final entry in {
          'md5': crypto.md5,
          'sha1': crypto.sha1,
          'sha256': crypto.sha256,
        }.entries) {
          final result = await engine.eval(
            'JSON.stringify(check(${jsonEncode(text)}, ${jsonEncode(entry.key)}))',
          );
          expect(jsonDecode(result as String), [
            entry.value.convert(utf8.encode(text)).toString(),
            text,
          ]);
        }
      }
      expect(
        await engine.runCommonJs('''
const { createHash } = require('crypto');
const { Buffer } = require('buffer');
const bytes = new Uint8Array([0, 97, 98, 99, 0]);
const hash = createHash('md5').update(bytes.subarray(1, 3)).update('63', 'hex');
const result = hash.digest('base64');
let rejected = false;
try { hash.update('x'); } catch (_) { rejected = true; }
module.exports = result + '/' + rejected + '/' + Buffer.from('616263', 'hex').toString();
''', name: 'hash-check.cjs'),
        'kAFQmDzST7DWlj99KOF/cg==/true/abc',
      );
    });
  }
}
