import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

Object? _objectProxyTestGetter() => 'value';

final class _TestUser {
  _TestUser(this.name);

  String name;
}

_TestUser _classTestUserConstructor(List<Object?> args) {
  return _TestUser(args.single as String);
}

Object? _classTestUserNameGetter(_TestUser user) => user.name;

Future<void> _waitFor(bool Function() condition) async {
  final stopwatch = Stopwatch()..start();
  while (!condition()) {
    if (stopwatch.elapsed > const Duration(seconds: 2)) {
      throw StateError('Timed out waiting for condition');
    }
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

bool _jsExceptionMentionsSource(JsException error, String sourceName) {
  return error.fileName == sourceName ||
      (error.stack?.contains(sourceName) ?? false);
}

QuickjsSourceMap _testSourceMap({String file = 'bundle.js'}) {
  return QuickjsSourceMap.fromMap({
    'version': 3,
    'file': file,
    'sources': ['src/main.ts'],
    'sourcesContent': ['throw new Error("boom");'],
    'names': ['fail'],
    'mappings': 'AAAA',
  });
}

const _randomUuidHostScript = QuickjsHostScript(
  name: 'host:crypto-random-uuid.js',
  source: r'''
(() => {
  const crypto = (globalThis.crypto && typeof globalThis.crypto === 'object')
    ? globalThis.crypto
    : {};
  const hex = [];
  for (let i = 0; i < 256; i++) {
    hex[i] = (i + 0x100).toString(16).slice(1);
  }
  const randomByte = () => Math.floor(Math.random() * 256) & 0xff;
  Object.defineProperty(crypto, 'randomUUID', {
    value: () => {
      const bytes = new Uint8Array(16);
      for (let i = 0; i < bytes.length; i++) {
        bytes[i] = randomByte();
      }
      bytes[6] = (bytes[6] & 0x0f) | 0x40;
      bytes[8] = (bytes[8] & 0x3f) | 0x80;
      return hex[bytes[0]] + hex[bytes[1]] + hex[bytes[2]] + hex[bytes[3]] + '-' +
        hex[bytes[4]] + hex[bytes[5]] + '-' +
        hex[bytes[6]] + hex[bytes[7]] + '-' +
        hex[bytes[8]] + hex[bytes[9]] + '-' +
        hex[bytes[10]] + hex[bytes[11]] + hex[bytes[12]] +
        hex[bytes[13]] + hex[bytes[14]] + hex[bytes[15]];
    },
    configurable: true,
    enumerable: true,
    writable: true,
  });
  Object.defineProperty(globalThis, 'crypto', {
    value: crypto,
    configurable: true,
    enumerable: false,
    writable: true,
  });
})()
''',
);

const _hostMathModule = QuickjsHostModule.esModule(
  specifier: 'app/math',
  source: '''
export const value = 41;
export function add(a, b) {
  return a + b;
}
''',
);

const _hostBufferModule = QuickjsHostModule.esModule(
  specifier: 'buffer',
  source: '''
export const label = 'host-buffer';
export const byteLength = (value) => String(value).length;
''',
);

const _hostCryptoModule = QuickjsHostModule.esModule(
  specifier: 'crypto',
  source: '''
export const label = 'node-crypto-module';
export function randomBytes(length) {
  return 'bytes:' + length;
}
''',
);

const _hostPackageMainModule = QuickjsHostModule.esModule(
  specifier: 'pkg/main',
  source: '''
import { value } from './dep';
export const result = value + 1;
''',
);

const _hostPackageDepModule = QuickjsHostModule.esModule(
  specifier: 'pkg/dep',
  source: 'export const value = 9;',
);

const _hostModuleLoaderMainModule = QuickjsHostModule.esModule(
  specifier: 'loader/main',
  source: '''
import { value } from './dep';
export const result = value + 1;
''',
);

const _hostCommonJsModule = QuickjsHostModule.commonJs(
  specifier: 'app/cjs',
  source: '''
const local = require('./local');
module.exports = {
  value: local.value + 1,
};
''',
);

const _hostCommonJsLocalModule = QuickjsHostModule.commonJs(
  specifier: 'app/local',
  source: 'exports.value = 6;',
);

const _hostCommonJsLoaderMainModule = QuickjsHostModule.commonJs(
  specifier: 'loader/cjs-main',
  source: '''
const dep = require('./cjs-dep');
exports.result = dep.value + 1;
''',
);

const _hostCommonJsBufferModule = QuickjsHostModule.commonJs(
  specifier: 'buffer',
  source: "exports.label = 'commonjs-buffer';",
);

const _hostCounterModule = QuickjsHostModule.esModule(
  specifier: 'app/counter',
  source: '''
globalThis.hostModuleImportCount = (globalThis.hostModuleImportCount || 0) + 1;
export const count = globalThis.hostModuleImportCount;
''',
);

const _hostCommonJsCounterModule = QuickjsHostModule.commonJs(
  specifier: 'app/cjs-counter',
  source: '''
globalThis.hostCommonJsImportCount = (globalThis.hostCommonJsImportCount || 0) + 1;
exports.count = globalThis.hostCommonJsImportCount;
''',
);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native/web consistency', () {
    // 鏈€灏忔眰鍊艰涔夊繀椤诲湪 native FFI 鍜?Web WASM 涓婁竴鑷淬€?
    test('evaluates basic JavaScript values', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(engine.quickjsVersion, '0.15.1');
      expect(await engine.eval('1 + 2'), '3');
      expect(await engine.eval('"a" + "b"'), 'ab');
      expect(await engine.eval('undefined'), 'undefined');
      expect(await engine.eval('null'), 'null');
      expect(await engine.eval('true'), 'true');
    });

    test('provides no-op console methods by default', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.eval('typeof console.log + "/" + console.log("ignored")'),
        'function/undefined',
      );
      expect(await engine.eval('typeof console.warn'), 'function');
      expect(await engine.eval('typeof console.error'), 'function');
    });

    test('emits console events to the configured sink', () async {
      final events = <QuickjsConsoleEvent>[];
      final engine = await Quickjs.create(onConsole: events.add);
      addTearDown(engine.dispose);

      expect(
        await engine.eval('''
console.log("hello", 42, { ok: true });
console.warn("careful");
console.error(new Error("boom"));
"done";
'''),
        'done',
      );

      await _waitFor(() => events.length == 3);
      expect(events[0].level, QuickjsConsoleLevel.log);
      expect(events[0].text, 'hello 42 {"ok":true}');
      expect(events[0].args, <Object?>[
        'hello',
        42,
        {'ok': true},
      ]);
      expect(events[1].level, QuickjsConsoleLevel.warn);
      expect(events[1].text, 'careful');
      expect(events[2].level, QuickjsConsoleLevel.error);
      expect(events[2].text, contains('boom'));
      expect(events[2].timestamp, isA<DateTime>());
    });

    test('can emit console events repeatedly in one runtime', () async {
      final events = <QuickjsConsoleEvent>[];
      final engine = await Quickjs.create(onConsole: events.add);
      addTearDown(engine.dispose);

      for (var i = 0; i < 2; i++) {
        expect(
          await engine.eval('''
console.log("run", $i);
console.warn("warn", $i);
console.error("error", $i);
"done";
'''),
          'done',
        );
      }

      await _waitFor(() => events.length == 6);
      expect(events.map((event) => event.text), <String>[
        'run 0',
        'warn 0',
        'error 0',
        'run 1',
        'warn 1',
        'error 1',
      ]);
    });

    test('keeps console events isolated per runtime', () async {
      final firstEvents = <QuickjsConsoleEvent>[];
      final secondEvents = <QuickjsConsoleEvent>[];
      final first = await Quickjs.create(onConsole: firstEvents.add);
      final second = await Quickjs.create(onConsole: secondEvents.add);
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await first.eval('console.log("first")');
      await second.eval('console.error("second")');

      await _waitFor(() => firstEvents.length == 1 && secondEvents.length == 1);
      expect(firstEvents.single.text, 'first');
      expect(firstEvents.single.level, QuickjsConsoleLevel.log);
      expect(secondEvents.single.text, 'second');
      expect(secondEvents.single.level, QuickjsConsoleLevel.error);
    });

    test('reinstalls console after stop rebuilds the runtime', () async {
      final events = <QuickjsConsoleEvent>[];
      final engine = await Quickjs.create(onConsole: events.add);
      addTearDown(engine.dispose);

      final running = engine
          .eval('while (true) {}')
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.stop();
      final error = await running;
      expect(error, isA<JsCancelledException>());

      await engine.eval('console.warn("after stop")');
      await _waitFor(() => events.length == 1);
      expect(events.single.level, QuickjsConsoleLevel.warn);
      expect(events.single.text, 'after stop');
    });

    // 缁撴瀯鍖栬繑鍥?API 鍦?native 鍜?web 涓婂簲淇濇寔鍩虹 primitive 鏄犲皠涓€鑷淬€?
    test('maps primitive JavaScript values to Dart values', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(await engine.evaluateValue('1 + 2'), 3);
      expect(await engine.evaluateValue('1.5 + 2'), 3.5);
      expect(await engine.evaluateValue('true'), true);
      expect(await engine.evaluateValue('"hello"'), 'hello');
      expect(await engine.evaluateValue('null'), isNull);
      expect(await engine.evaluateValue('undefined'), isA<JsUndefined>());
    });

    // BigInt 鍦?native 鍜?web 涓婇兘搴旀槧灏勪负 Dart BigInt銆?
    test('maps BigInt values to Dart BigInt', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evaluateValue('9007199254740993n'),
        BigInt.parse('9007199254740993'),
      );
    });

    // JSON-compatible array / plain object 鍦?native 鍜?web 涓婁繚鎸佸悓鏍风粨鏋勩€?
    test('maps arrays and plain objects to Dart values', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(await engine.evaluateValue('[1, "two", true, null]'), <Object?>[
        1,
        'two',
        true,
        null,
      ]);
      expect(await engine.evaluateValue('({ a: 1, b: "two", c: false })'), {
        'a': 1,
        'b': 'two',
        'c': false,
      });
      expect(
        await engine.evaluateValue('({ nested: [1, { ok: true }, null] })'),
        {
          'nested': [
            1,
            {'ok': true},
            null,
          ],
        },
      );
    });

    // ArrayBuffer / Uint8Array 鍦?native 鍜?web 涓婇兘搴旀槧灏勪负 Uint8List銆?
    test('maps binary buffers to Dart Uint8List', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evaluateValue('new Uint8Array([1, 2, 255])'),
        Uint8List.fromList([1, 2, 255]),
      );
      expect(
        await engine.evaluateValue('new Uint8Array([3, 4, 5]).buffer'),
        Uint8List.fromList([3, 4, 5]),
      );
    });

    // 涓嶅彲鐩存帴杞崲鍊煎湪 native 鍜?web 涓婇兘搴旇繑鍥炲悓涓€绫诲叕寮€杞崲閿欒銆?
    test('rejects unsupported JavaScript values consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      for (final code in <String>[
        'Symbol("id")',
        '() => 1',
        '[1, Symbol("id")]',
        'const value = {}; value.self = value; value',
      ]) {
        await expectLater(
          engine.evaluateValue(code),
          throwsA(isA<JsValueConversionException>()),
        );
      }
    });

    // Dart globals 娉ㄥ叆鍦?native 鍜?web 涓婂簲淇濇寔鍚屾牱鐨勮浆鎹笌鎭㈠璇箟銆?
    test('maps Dart globals to JavaScript values consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evaluateValue(
          '''
({
  sum: intValue + doubleValue,
  flag: boolValue,
  text: stringValue,
  missing: nullValue,
  bytes: Array.from(bytesValue),
  list: listValue,
  nested: mapValue.nested[1].ok,
  date: dateValue.toISOString(),
})
''',
          globals: {
            'intValue': 40,
            'doubleValue': 2.5,
            'boolValue': true,
            'stringValue': 'hello',
            'nullValue': null,
            'bytesValue': Uint8List.fromList([1, 2, 255]),
            'listValue': [1, 'two', false],
            'mapValue': {
              'nested': [
                1,
                {'ok': true},
              ],
            },
            'dateValue': DateTime.utc(2026, 6, 10),
          },
        ),
        {
          'sum': 42.5,
          'flag': true,
          'text': 'hello',
          'missing': null,
          'bytes': [1, 2, 255],
          'list': [1, 'two', false],
          'nested': true,
          'date': '2026-06-10T00:00:00.000Z',
        },
      );

      expect(await engine.eval('globalThis.answer = 1'), '1');
      expect(
        await engine.eval(
          'answer + extra',
          globals: {'answer': 41, 'extra': 1},
        ),
        '42',
      );
      expect(await engine.eval('answer'), '1');
      expect(await engine.eval('typeof extra'), 'undefined');
    });

    test('evaluates ES modules consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evalModule(
          'export const value = 42;'
          'globalThis.moduleValue = value;',
          name: 'module-basic.mjs',
        ),
        'undefined',
      );
      expect(await engine.eval('globalThis.moduleValue'), '42');
    });

    test('evaluates multiple ES module names in one runtime', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      for (var i = 1; i <= 2; i++) {
        expect(
          await engine.evalModule(
            'export const value = $i;'
            'globalThis.moduleValue = value;',
            name: 'module-run-$i.mjs',
          ),
          'undefined',
        );
        expect(await engine.eval('globalThis.moduleValue'), '$i');
      }
    });

    test('loads relative ES module imports consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'lib/dep.mjs' => 'export const value = 40;',
            'shared/add.mjs' => 'export function add(a, b) { return a + b; }',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalModule('''
import { value } from './dep.mjs';
import { add } from '../shared/add.mjs';
globalThis.moduleValue = add(value, 2);
''', name: 'lib/main.mjs'),
        'undefined',
      );
      expect(await engine.eval('globalThis.moduleValue'), '42');
    });

    test('caches imported ES modules in one runtime consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'counter.mjs' =>
              'globalThis.moduleImportCount = (globalThis.moduleImportCount || 0) + 1;'
                  'export const value = globalThis.moduleImportCount;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalModule(
        'import { value } from "counter.mjs"; globalThis.firstImport = value;',
        name: 'first.mjs',
      );
      await engine.evalModule(
        'import { value } from "counter.mjs"; globalThis.secondImport = value;',
        name: 'second.mjs',
      );

      expect(await engine.eval('globalThis.firstImport'), '1');
      expect(await engine.eval('globalThis.secondImport'), '1');
      expect(await engine.eval('globalThis.moduleImportCount'), '1');
    });

    test('reports missing ES module imports consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(moduleLoader: (_) => null),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.evalModule('import "./missing.mjs";', name: 'main.mjs'),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('maps ES module throw to JsException consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.evalModule(
          'throw new Error("module boom");',
          name: 'module-error.mjs',
        ),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('module boom'),
          ),
        ),
      );
    });

    test('loads relative CommonJS require consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'lib/dep.js' => 'exports.value = 40;',
            'shared/add.js' =>
              'module.exports = function add(a, b) { return a + b; };',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs('''
const dep = require('./dep.js');
const add = require('../shared/add.js');
globalThis.commonJsValue = add(dep.value, 2);
exports.value = globalThis.commonJsValue;
''', name: 'lib/main.js'),
        '[object Object]',
      );
      expect(await engine.eval('globalThis.commonJsValue'), '42');
    });

    test('supports CommonJS module.exports consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'answer.js' => 'module.exports = 42;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs(
          'globalThis.commonJsAnswer = require("./answer.js");',
          name: 'main.js',
        ),
        '[object Object]',
      );
      expect(await engine.eval('globalThis.commonJsAnswer'), '42');
    });

    test('caches CommonJS modules in one runtime consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'counter.js' =>
              'globalThis.commonJsImportCount = (globalThis.commonJsImportCount || 0) + 1;'
                  'exports.count = globalThis.commonJsImportCount;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalCommonJs(
        'globalThis.firstCommonJsCount = require("./counter.js").count;',
        name: 'first.js',
      );
      await engine.evalCommonJs(
        'globalThis.secondCommonJsCount = require("./counter.js").count;',
        name: 'second.js',
      );

      expect(await engine.eval('globalThis.firstCommonJsCount'), '1');
      expect(await engine.eval('globalThis.secondCommonJsCount'), '1');
      expect(await engine.eval('globalThis.commonJsImportCount'), '1');
    });

    test('reports missing CommonJS modules consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(moduleLoader: (_) => null),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.evalCommonJs('require("./missing.js");', name: 'main.js'),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('calls JavaScript function handles consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final add = await engine.evaluateHandle('''
function add(a, b) {
  return a + b;
}
add
''');

      expect(await add.call([20, 22]), '42');
      expect(await add.call([1, 2]), '3');
    });

    test(
      'passes structured arguments to function handles consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);

        final summarize = await engine.evaluateHandle(
          '(input) => input.name + ":" + input.values.join(",")',
        );

        expect(
          await summarize.call([
            {
              'name': 'items',
              'values': [1, 2, 3],
            },
          ]),
          'items:1,2,3',
        );
      },
    );

    test('awaits Promise-returning function handles consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final add = await engine.evaluateHandle('''
async (a, b) => {
  await new Promise((resolve) => setTimeout(resolve, 1));
  return a + b;
}
''');

      expect(await add.callAsync([20, 22]), '42');
    });

    test('maps Promise rejection from function handles consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final fail = await engine.evaluateHandle('''
async () => {
  await new Promise((resolve) => setTimeout(resolve, 1));
  throw new Error('handle async boom');
}
''');

      await expectLater(
        fail.callAsync(const []),
        throwsA(
          isA<JsException>().having(
            (error) => error.toString(),
            'message',
            contains('handle async boom'),
          ),
        ),
      );
    });

    test('rejects non-function handles consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.evaluateHandle('42'),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('keeps function handles isolated per runtime', () async {
      final first = await Quickjs.create();
      final second = await Quickjs.create();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final firstHandle = await first.evaluateHandle('() => "first"');
      final secondHandle = await second.evaluateHandle('() => "second"');

      expect(await firstHandle.call(const []), 'first');
      expect(await secondHandle.call(const []), 'second');
    });

    test('function handle calls can time out consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final loop = await engine.evaluateHandle('() => { while (true) {} }');

      await expectLater(
        loop.call(const [], timeout: const Duration(milliseconds: 50)),
        throwsA(isA<JsTimeoutException>()),
      );
      expect(await engine.eval('21 * 2'), '42');
    });

    test('async function handle calls can time out consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final pending = await engine.evaluateHandle(
        '() => new Promise(() => {})',
      );

      await expectLater(
        pending.callAsync(const [], timeout: const Duration(milliseconds: 50)),
        throwsA(isA<JsTimeoutException>()),
      );
      expect(await engine.eval('21 * 2'), '42');
    });

    test('function handle calls can be cancelled consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final loop = await engine.evaluateHandle('() => { while (true) {} }');
      final running = loop.call(const []);
      final cancelFuture = Future<void>.delayed(
        const Duration(milliseconds: 50),
        loop.cancel,
      );

      await expectLater(running, throwsA(isA<JsCancelledException>()));
      await cancelFuture.timeout(const Duration(seconds: 2));
      expect(await engine.eval('21 * 2'), '42');
    });

    test('function handles reject calls after dispose consistently', () async {
      final engine = await Quickjs.create();
      final add = await engine.evaluateHandle('(a, b) => a + b');

      await engine.dispose();

      await expectLater(
        add.call([1, 2]),
        throwsA(isA<JsRuntimeClosedException>()),
      );
      await expectLater(
        add.callAsync([1, 2]),
        throwsA(isA<JsRuntimeClosedException>()),
      );
    });

    test('function handles can be disposed consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final add = await engine.evaluateHandle('(a, b) => a + b');

      expect(await add.call([20, 22]), '42');
      await add.dispose();
      await add.dispose();

      await expectLater(
        add.call([1, 2]),
        throwsA(
          isA<JsRuntimeClosedException>().having(
            (error) => error.message,
            'message',
            contains('function handle is disposed'),
          ),
        ),
      );
      await expectLater(
        add.callAsync([1, 2]),
        throwsA(
          isA<JsRuntimeClosedException>().having(
            (error) => error.message,
            'message',
            contains('function handle is disposed'),
          ),
        ),
      );

      final multiply = await engine.evaluateHandle('(a, b) => a * b');
      expect(await multiply.call([6, 7]), '42');
    });

    test(
      'disposing function handles after runtime dispose is a no-op',
      () async {
        final engine = await Quickjs.create();
        final add = await engine.evaluateHandle('(a, b) => a + b');

        await engine.dispose();
        await add.dispose();
        await add.dispose();
      },
    );

    // Promise-based Dart callback 鍦?native 鍜?web 涓婇兘搴?resolve 涓?JS await 缁撴灉銆?
    test('binds readonly Dart object proxy properties consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bindObject(
        'user',
        const QuickjsObjectProxy(properties: {'name': 'Tom', 'age': 42}),
      );

      expect(await engine.eval('user.name + ":" + user.age'), 'Tom:42');
      expect(
        await engine.eval(
          'Reflect.set(user, "name", "Jerry") + ":" + user.name',
        ),
        'false:Tom',
      );
    });

    test('binds dynamic Dart object proxy accessors consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      var name = 'Tom';

      await engine.bindObject(
        'profile',
        QuickjsObjectProxy(
          accessors: {
            'name': QuickjsObjectAccessor(
              get: () => name,
              set: (value) {
                name = value as String;
              },
            ),
            'readonly': QuickjsObjectAccessor(get: () => 'fixed'),
          },
        ),
      );

      expect(await engine.evalAsync('return await profile.name;'), 'Tom');
      expect(
        await engine.evalAsync('''
profile.name = 'Jerry';
await new Promise((resolve) => setTimeout(resolve, 1));
return await profile.name;
'''),
        'Jerry',
      );
      expect(name, 'Jerry');
      expect(
        await engine.evalAsync(
          'return Reflect.set(profile, "readonly", "changed") + ":" + '
          'await profile.readonly;',
        ),
        'false:fixed',
      );
    });

    test('maps Dart object proxy getter errors consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bindObject(
        'profile',
        QuickjsObjectProxy(
          accessors: {
            'name': QuickjsObjectAccessor(
              get: () {
                throw StateError('getter failed');
              },
            ),
          },
        ),
      );

      await expectLater(
        engine.evalAsync('return await profile.name;'),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('getter failed'),
          ),
        ),
      );
    });

    test('binds Dart object proxy methods consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final handle = await engine.bindObject(
        'calculator',
        QuickjsObjectProxy(
          properties: const {'name': 'calc'},
          methods: {
            'add': (args) {
              return (args[0] as num).toInt() + (args[1] as num).toInt();
            },
            'label': (args) async {
              return '${args.single}:${DateTime.utc(2024).year}';
            },
          },
        ),
      );

      expect(
        await engine.evalAsync('return await calculator.add(20, 22);'),
        '42',
      );
      expect(
        await engine.evalAsync(
          'return await calculator.label(calculator.name);',
        ),
        'calc:2024',
      );
      expect(handle.name, 'calculator');
      expect(handle.disposed, isFalse);
    });

    test('Dart object proxy handles can be disposed consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final handle = await engine.bindObject(
        'service',
        QuickjsObjectProxy(methods: {'ping': (_) => 'pong'}),
      );

      expect(await engine.evalAsync('return await service.ping();'), 'pong');
      expect(
        await engine.eval(
          'const quickjsObjectProxyKeys = Object.keys(globalThis).filter((key) => '
          'key.startsWith("__quickjsObjectProxy_"));'
          'globalThis.leakedPing = globalThis[quickjsObjectProxyKeys[0]];'
          '"saved"',
        ),
        'saved',
      );
      expect(
        await engine.eval(
          'Object.keys(globalThis).filter((key) => '
          'key.startsWith("__quickjsObjectProxy_")).length',
        ),
        '1',
      );

      await handle.dispose();
      await handle.dispose();

      expect(handle.disposed, isTrue);
      expect(await engine.eval('typeof service'), 'undefined');
      expect(
        await engine.eval(
          'Object.keys(globalThis).filter((key) => '
          'key.startsWith("__quickjsObjectProxy_")).length',
        ),
        '0',
      );
      await expectLater(
        engine.evalAsync('return await leakedPing();'),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('not bound'),
          ),
        ),
      );
    });

    test(
      'leaked Dart object proxies reject access after dispose consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);
        var name = 'Tom';

        final handle = await engine.bindObject(
          'service',
          QuickjsObjectProxy(
            properties: const {'role': 'admin'},
            accessors: {
              'name': QuickjsObjectAccessor(
                get: () => name,
                set: (value) {
                  name = value as String;
                },
              ),
            },
            methods: {'ping': (_) => 'pong'},
          ),
        );

        expect(
          await engine.evalAsync(
            'globalThis.leakedService = service;'
            'globalThis.leakedPing = service.ping;'
            'return await service.name + ":" + service.role + ":" + '
            'await service.ping();',
          ),
          'Tom:admin:pong',
        );

        await handle.dispose();

        for (final code in <String>[
          'return leakedService.role;',
          'return await leakedService.name;',
          'leakedService.name = "Jerry"; return "updated";',
          'return await leakedService.ping();',
          'return await leakedPing();',
        ]) {
          await expectLater(
            engine.evalAsync(code),
            throwsA(
              isA<JsException>().having(
                (error) => error.message,
                'message',
                contains('object proxy is disposed'),
              ),
            ),
          );
        }
        expect(name, 'Tom');
      },
    );

    test(
      'disposing Dart object proxy handles after runtime dispose is a no-op',
      () async {
        final engine = await Quickjs.create();
        final handle = await engine.bindObject(
          'service',
          QuickjsObjectProxy(methods: {'ping': (_) => 'pong'}),
        );

        await engine.dispose();
        await handle.dispose();
        await handle.dispose();

        expect(handle.disposed, isTrue);
      },
    );

    test('maps Dart object proxy method errors consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bindObject(
        'service',
        QuickjsObjectProxy(
          methods: {
            'fail': (_) {
              throw StateError('proxy failed');
            },
          },
        ),
      );

      await expectLater(
        engine.evalAsync('return await service.fail();'),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('proxy failed'),
          ),
        ),
      );
    });

    test(
      'rejects invalid Dart object proxy descriptors consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);

        await expectLater(
          engine.bindObject(
            'invalidProxy',
            const QuickjsObjectProxy(properties: {'not-valid': 1}),
          ),
          throwsA(isA<JsValueConversionException>()),
        );
        await expectLater(
          engine.bindObject(
            'invalidProxy',
            QuickjsObjectProxy(
              properties: const {'value': 1},
              methods: {'value': (_) => null},
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );
        await expectLater(
          engine.bindObject(
            'invalidProxy',
            const QuickjsObjectProxy(
              accessors: {'value': QuickjsObjectAccessor()},
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );
        await expectLater(
          engine.bindObject(
            'invalidProxy',
            QuickjsObjectProxy(
              accessors: const {
                'value': QuickjsObjectAccessor(get: _objectProxyTestGetter),
              },
              methods: {'value': (_) => null},
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );
      },
    );

    test(
      'rejects Dart object proxy binding after dispose consistently',
      () async {
        final engine = await Quickjs.create();

        await engine.dispose();

        await expectLater(
          engine.bindObject('user', const QuickjsObjectProxy()),
          throwsA(isA<JsRuntimeClosedException>()),
        );
      },
    );

    test(
      'binds Dart classes as JavaScript constructors consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);

        final handle = await engine.bindClass<_TestUser>(
          'User',
          QuickjsClass<_TestUser>(
            constructor: (args) => _TestUser(args.single as String),
            accessors: {
              'name': QuickjsInstanceAccessor<_TestUser>(
                get: (user) => user.name,
                set: (user, value) {
                  user.name = value as String;
                },
              ),
            },
            methods: {
              'greet': (user, args) =>
                  'Hello ${args.single}, I am ${user.name}',
            },
          ),
        );

        expect(
          await engine.evalAsync('''
const user = new User('Tom');
const before = await user.name;
user.name = 'Jerry';
const after = await user.name;
const greeting = await user.greet('Alice');
return before + ':' + after + ':' + greeting + ':' + (user instanceof User);
'''),
          'Tom:Jerry:Hello Alice, I am Jerry:true',
        );
        expect(handle.name, 'User');
        expect(handle.disposed, isFalse);
      },
    );

    test('Dart class instances survive separate async evaluations', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bindClass<_TestUser>(
        'User',
        QuickjsClass<_TestUser>(
          constructor: (args) => _TestUser(args.single as String),
          accessors: {
            'name': QuickjsInstanceAccessor<_TestUser>(
              get: (user) => user.name,
              set: (user, value) {
                user.name = value as String;
              },
            ),
          },
        ),
      );

      expect(
        await engine.evalAsync('''
globalThis.currentUser = new User('Tom');
return await currentUser.name;
'''),
        'Tom',
      );
      expect(
        await engine.evalAsync('''
globalThis.currentUser ??= new User('Tom');
const before = await currentUser.name;
currentUser.name = 'Jerry';
const after = await currentUser.name;
return before + ' -> ' + after;
'''),
        'Tom -> Jerry',
      );
    });

    test('maps Dart class constructor errors consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bindClass<_TestUser>(
        'User',
        QuickjsClass<_TestUser>(
          constructor: (_) {
            throw StateError('constructor failed');
          },
          methods: {'name': (user, _) => user.name},
        ),
      );

      await expectLater(
        engine.evalAsync('''
const user = new User('Tom');
return await user.name();
'''),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('constructor failed'),
          ),
        ),
      );
    });

    test('Dart class handles can be disposed consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final handle = await engine.bindClass<_TestUser>(
        'User',
        QuickjsClass<_TestUser>(
          constructor: (args) => _TestUser(args.single as String),
          accessors: {
            'name': QuickjsInstanceAccessor<_TestUser>(
              get: (user) => user.name,
              set: (user, value) {
                user.name = value as String;
              },
            ),
          },
          methods: {'greet': (user, _) => 'Hello ${user.name}'},
        ),
      );

      expect(
        await engine.evalAsync(
          'globalThis.leakedUser = new User("Tom");'
          'return await leakedUser.greet();',
        ),
        'Hello Tom',
      );

      await handle.dispose();
      await handle.dispose();

      expect(handle.disposed, isTrue);
      expect(await engine.eval('typeof User'), 'undefined');
      for (final code in <String>[
        'return await leakedUser.name;',
        'return await leakedUser.greet();',
      ]) {
        await expectLater(
          engine.evalAsync(code),
          throwsA(
            isA<JsException>().having(
              (error) => error.message,
              'message',
              contains('class instance is disposed'),
            ),
          ),
        );
      }
    });

    test(
      'disposing Dart class handles after runtime dispose is a no-op',
      () async {
        final engine = await Quickjs.create();
        final handle = await engine.bindClass<_TestUser>(
          'User',
          QuickjsClass<_TestUser>(
            constructor: (args) => _TestUser(args.single as String),
          ),
        );

        await engine.dispose();
        await handle.dispose();
        await handle.dispose();

        expect(handle.disposed, isTrue);
      },
    );

    test('rejects invalid Dart class descriptors consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.bindClass<_TestUser>(
          'Invalid',
          QuickjsClass<_TestUser>(
            constructor: _classTestUserConstructor,
            accessors: const {
              'not-valid': QuickjsInstanceAccessor<_TestUser>(),
            },
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      await expectLater(
        engine.bindClass<_TestUser>(
          'Invalid',
          QuickjsClass<_TestUser>(
            constructor: _classTestUserConstructor,
            accessors: const {
              'value': QuickjsInstanceAccessor<_TestUser>(
                get: _classTestUserNameGetter,
              ),
            },
            methods: {'value': (user, _) => user.name},
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('rejects Dart class binding after dispose consistently', () async {
      final engine = await Quickjs.create();

      await engine.dispose();

      await expectLater(
        engine.bindClass<_TestUser>(
          'User',
          QuickjsClass<_TestUser>(constructor: _classTestUserConstructor),
        ),
        throwsA(isA<JsRuntimeClosedException>()),
      );
    });

    test('maps Promise-based Dart callback resolve consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostAdd', (args) {
        return (args[0] as num).toInt() + (args[1] as num).toInt();
      });

      expect(await engine.evalAsync('return await hostAdd(20, 22);'), '42');
    });

    test('maps Promise-based Dart callback reject consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostFail', (_) {
        throw StateError('host failed');
      });

      await expectLater(
        engine.evalAsync('return await hostFail();'),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('host failed'),
          ),
        ),
      );
    });

    test('keeps bound Dart callbacks isolated per runtime', () async {
      final first = await Quickjs.create();
      final second = await Quickjs.create();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      await first.bind('hostName', (_) => 'first');
      await second.bind('hostName', (_) => 'second');

      expect(await first.evalAsync('return await hostName();'), 'first');
      expect(await second.evalAsync('return await hostName();'), 'second');
    });

    test('maps callback binary values consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostBytes', (args) {
        final bytes = args.single as Uint8List;
        return Uint8List.fromList([bytes[0], bytes[1], 255]);
      });

      expect(
        await engine.evalAsync(
          'const bytes = await hostBytes(new Uint8Array([1, 2]));'
          'return Array.from(bytes).join(",");',
        ),
        '1,2,255',
      );
    });

    test('dispose cancels pending Dart callback Promise', () async {
      final engine = await Quickjs.create();
      final callbackInvoked = Completer<void>();
      final callbackResult = Completer<Object?>();

      await engine.bind('hostWait', (_) {
        if (!callbackInvoked.isCompleted) {
          callbackInvoked.complete();
        }
        return callbackResult.future;
      });

      final running = engine.evalAsync('return await hostWait();');
      await callbackInvoked.future.timeout(const Duration(seconds: 2));

      final runningFailure = expectLater(
        running,
        throwsA(
          anyOf(isA<JsCancelledException>(), isA<JsRuntimeClosedException>()),
        ),
      );
      await engine.dispose().timeout(const Duration(seconds: 2));
      await runningFailure;
    });

    test('resolves Promise through setTimeout consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync(
          'const value = await new Promise((resolve) => '
          'setTimeout(() => resolve(42), 1));'
          'return value;',
        ),
        '42',
      );
    });

    test('clearTimeout cancels scheduled callback consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync(
          'let called = false;'
          'const id = setTimeout(() => { called = true; }, 1);'
          'clearTimeout(id);'
          'await new Promise((resolve) => setTimeout(resolve, 2));'
          'return called;',
        ),
        'false',
      );
    });

    test('setInterval repeats until clearInterval consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync(
          'let count = 0;'
          'await new Promise((resolve) => {'
          '  const id = setInterval(() => {'
          '    count++;'
          '    if (count === 3) {'
          '      clearInterval(id);'
          '      resolve();'
          '    }'
          '  }, 1);'
          '});'
          'return count;',
        ),
        '3',
      );
    });

    test('keeps timers isolated per runtime', () async {
      final first = await Quickjs.create();
      try {
        expect(
          await first.evalAsync(
            'globalThis.timerName = "first";'
            'return await new Promise((resolve) => '
            'setTimeout(() => resolve(timerName), 1));',
          ),
          'first',
        );
      } finally {
        await first.dispose();
      }

      final second = await Quickjs.create();
      try {
        expect(
          await second.evalAsync(
            'globalThis.timerName = "second";'
            'return await new Promise((resolve) => '
            'setTimeout(() => resolve(timerName), 1));',
          ),
          'second',
        );
      } finally {
        await second.dispose();
      }
    });

    test('maps Dart Stream callback to JS for-await consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostStream', (_) {
        return Stream<Object?>.fromIterable([1, 2, 3]);
      });

      expect(
        await engine.evalAsync('''
const values = [];
const stream = await hostStream();
for await (const item of stream) {
  values.push(item);
}
return values.join(',');
'''),
        '1,2,3',
      );
    });

    test('can consume Dart Stream callback repeatedly', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostStream', (_) {
        return Stream<Object?>.fromIterable([1, 2, 3]);
      });

      expect(
        await engine.evalAsync('''
const collect = async () => {
  const values = [];
  const stream = await hostStream();
  for await (const item of stream) {
    values.push(item);
  }
  return values.join(',');
};
return [await collect(), await collect()].join('|');
'''),
        '1,2,3|1,2,3',
      );
    });

    test(
      'maps periodic Dart Stream callback to JS for-await consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);

        await engine.bind('hostCount', (args) {
          final max = (args.single as num).toInt();
          return Stream<Object?>.periodic(
            const Duration(milliseconds: 10),
            (index) => index + 1,
          ).take(max);
        });

        expect(
          await engine.evalAsync('''
const values = [];
const stream = await hostCount(5);
for await (const value of stream) {
  values.push(value);
}
return values.join(',');
'''),
          '1,2,3,4,5',
        );
      },
    );

    test('maps JS sink to Dart Stream consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      final values = <Object?>[];
      final done = Completer<void>();

      final stream = await engine.bindSink('progress');
      final subscription = stream.listen(values.add, onDone: done.complete);
      addTearDown(subscription.cancel);

      expect(
        await engine.evalAsync('''
await progress.emit('chunk-1');
await progress.emit('chunk-2');
await progress.close();
return 'done';
'''),
        'done',
      );
      await done.future.timeout(const Duration(seconds: 2));
      expect(values, ['chunk-1', 'chunk-2']);
    });

    test('keeps stream and sink bindings isolated per runtime', () async {
      final first = await Quickjs.create();
      final firstValues = <Object?>[];
      final firstDone = Completer<void>();

      try {
        await first.bind('hostStream', (_) => Stream<Object?>.value('first'));
        final firstStream = await first.bindSink('progress');
        final firstSub = firstStream.listen(
          firstValues.add,
          onDone: firstDone.complete,
        );
        addTearDown(firstSub.cancel);

        expect(
          await first.evalAsync('''
await progress.emit('first-sink');
await progress.close();
const values = [];
for await (const item of await hostStream()) {
  values.push(item);
}
return values.join(',');
'''),
          'first',
        );
        await firstDone.future.timeout(const Duration(seconds: 2));
        expect(firstValues, ['first-sink']);
      } finally {
        await first.dispose();
      }

      final second = await Quickjs.create();
      final secondValues = <Object?>[];
      final secondDone = Completer<void>();
      try {
        await second.bind('hostStream', (_) => Stream<Object?>.value('second'));
        final secondStream = await second.bindSink('progress');
        final secondSub = secondStream.listen(
          secondValues.add,
          onDone: secondDone.complete,
        );
        addTearDown(secondSub.cancel);

        expect(
          await second.evalAsync('''
await progress.emit('second-sink');
await progress.close();
const values = [];
for await (const item of await hostStream()) {
  values.push(item);
}
return values.join(',');
'''),
          'second',
        );
        await secondDone.future.timeout(const Duration(seconds: 2));
        expect(secondValues, ['second-sink']);
      } finally {
        await second.dispose();
      }
    });

    test(
      'streams periodic JS sink values without starving async jobs',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);
        final values = <Object?>[];
        final done = Completer<void>();

        final stream = await engine.bindSink('progress');
        final subscription = stream.listen(values.add, onDone: done.complete);
        addTearDown(subscription.cancel);

        expect(
          await engine.evalAsync('''
let n = 0;
const sideJob = new Promise((resolve) => setTimeout(() => resolve('side'), 1));
while (n < 3) {
  await new Promise((resolve) => setTimeout(resolve, 1));
  await progress.emit(++n);
}
await progress.close();
return await sideJob;
'''),
          'side',
        );
        await done.future.timeout(const Duration(seconds: 2));
        expect(values, [1, 2, 3]);
      },
    );

    test('maps Dart Stream errors to JS exceptions consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.bind('hostStream', (_) async* {
        yield 'before';
        throw StateError('stream failed');
      });

      await expectLater(
        engine.evalAsync('''
const values = [];
const stream = await hostStream();
for await (const item of stream) {
  values.push(item);
}
return values.join(',');
'''),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('stream failed'),
          ),
        ),
      );
    });

    test('maps JS sink error to Dart Stream error consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      final errorSeen = Completer<Object>();

      final stream = await engine.bindSink('progress');
      final subscription = stream.listen(
        (_) {},
        onError: (Object error) {
          if (!errorSeen.isCompleted) {
            errorSeen.complete(error);
          }
        },
      );
      addTearDown(subscription.cancel);

      expect(
        await engine.evalAsync('''
await progress.error('sink failed');
return 'done';
'''),
        'done',
      );
      expect(
        '${await errorSeen.future.timeout(const Duration(seconds: 2))}',
        contains('sink failed'),
      );
    });

    test('cancels Dart Stream when JS stops consuming', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      final cancelled = Completer<void>();
      StreamController<Object?>? controller;

      await engine.bind('hostStream', (_) {
        late final StreamController<Object?> current;
        current = StreamController<Object?>(
          onListen: () {
            current.add(1);
            current.add(2);
          },
          onCancel: () {
            if (!cancelled.isCompleted) {
              cancelled.complete();
            }
          },
        );
        controller = current;
        return current.stream;
      });

      expect(
        await engine.evalAsync('''
let first;
const stream = await hostStream();
for await (const item of stream) {
  first = item;
  break;
}
return first;
'''),
        '1',
      );
      await cancelled.future.timeout(const Duration(seconds: 2));
      await controller?.close();
    });

    // JS throw 涓嶈兘琚綋鎴愭櫘閫氬瓧绗︿覆缁撴灉銆?
    test('maps JavaScript throw to JsException', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('throw new Error("boom")'),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('boom'),
          ),
        ),
      );
    });

    test('maps JavaScript Error details consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('throw new TypeError("consistent boom")'),
        throwsA(
          isA<JsException>()
              .having(
                (error) => error.message,
                'message',
                contains('consistent boom'),
              )
              .having((error) => error.name, 'name', 'TypeError')
              .having((error) => error.stack, 'stack', isNot(isEmpty)),
        ),
      );
    });

    test('uses source names for eval exceptions consistently', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      const sourceName = 'scripts/named_eval.js';

      await expectLater(
        engine.eval('''
function fail() {
  throw new Error("named eval boom");
}
fail();
''', name: sourceName),
        throwsA(
          isA<JsException>()
              .having(
                (error) => error.message,
                'message',
                contains('named eval boom'),
              )
              .having(
                (error) => _jsExceptionMentionsSource(error, sourceName),
                'source name',
                isTrue,
              ),
        ),
      );
    });

    test(
      'uses source names for wrapped eval exceptions consistently',
      () async {
        final engine = await Quickjs.create();
        addTearDown(engine.dispose);
        const sourceName = 'scripts/named_value.js';

        await expectLater(
          engine.evaluateValue(
            '''
function fail() {
  throw new Error("named value boom");
}
fail();
''',
            name: sourceName,
            globals: {'prefix': 'named'},
          ),
          throwsA(
            isA<JsException>()
                .having(
                  (error) => error.message,
                  'message',
                  contains('named value boom'),
                )
                .having(
                  (error) => _jsExceptionMentionsSource(error, sourceName),
                  'source name',
                  isTrue,
                ),
          ),
        );
      },
    );

    test('attaches registered source maps to eval exceptions', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      const sourceName = 'bundle.js';
      final sourceMap = _testSourceMap(file: sourceName);
      engine.registerSourceMap(sourceName, sourceMap);

      expect(engine.sourceMapFor(sourceName), same(sourceMap));
      await expectLater(
        engine.eval('throw new Error("mapped boom")', name: sourceName),
        throwsA(
          isA<JsException>()
              .having(
                (error) => error.message,
                'message',
                contains('mapped boom'),
              )
              .having((error) => error.sourceMap, 'sourceMap', same(sourceMap))
              .having(
                (error) => error.stack,
                'stack',
                contains('src/main.ts:1:1'),
              )
              .having((error) => error.fileName, 'fileName', 'src/main.ts')
              .having((error) => error.line, 'line', 1)
              .having((error) => error.column, 'column', 0)
              .having((error) => error.sourceMap?.sources, 'sources', [
                'src/main.ts',
              ]),
        ),
      );

      engine.unregisterSourceMap(sourceName);
      expect(engine.sourceMapFor(sourceName), isNull);
      await expectLater(
        engine.eval('throw new Error("unmapped boom")', name: sourceName),
        throwsA(
          isA<JsException>().having(
            (error) => error.sourceMap,
            'sourceMap',
            isNull,
          ),
        ),
      );
    });

    test('captures debug inspector snapshots consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          memoryLimitBytes: 512 * 1024,
          stackLimitBytes: 128 * 1024,
          moduleLoader: (name) => switch (name) {
            'dep.mjs' => 'export const value = 41;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);
      const sourceName = 'debug-bundle.js';
      final sourceMap = _testSourceMap(file: sourceName);

      engine.registerSourceMap(sourceName, sourceMap);
      await engine.bind('debugAdd', (args) {
        return (args[0] as num).toInt() + (args[1] as num).toInt();
      });
      await engine.evalModule(
        'import { value } from "./dep.mjs"; globalThis.debugAnswer = value + 1;',
        name: 'main.mjs',
      );

      expect(await engine.debugEvaluateValue('debugAnswer + 1'), 43);
      final snapshot = await engine.debugInspect(includeGlobals: true);
      expect(snapshot.state, QuickjsRuntimeState.ready);
      expect(snapshot.running, isFalse);
      expect(snapshot.pendingEvaluations, 0);
      expect(snapshot.memoryLimitBytes, 512 * 1024);
      expect(snapshot.stackLimitBytes, 128 * 1024);
      expect(snapshot.registeredCallbacks, contains('debugAdd'));
      expect(snapshot.moduleNames, containsAll(['main.mjs', 'dep.mjs']));
      expect(snapshot.sourceMapNames, contains(sourceName));
      expect(snapshot.globals, containsAll(['debugAnswer', 'debugAdd']));
    });

    test('captures registered host modules in debug snapshots', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[
            _hostMathModule,
            _hostBufferModule,
            _hostCommonJsModule,
          ],
        ),
      );
      addTearDown(engine.dispose);

      final snapshot = await engine.debugInspect();

      expect(
        snapshot.moduleNames,
        containsAll(['app/math', 'buffer', 'app/cjs']),
      );
    });

    test('captures registered host providers in debug snapshots', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'debug.provider',
              debugName: 'debug-provider-callback',
              implementation: QuickjsHostProviderImplementation.platform,
              callback: (_, _) => null,
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      final snapshot = await engine.debugInspect();

      expect(snapshot.registeredProviders, contains('debug.provider'));
      expect(snapshot.registeredCallbacks, contains('debug-provider-callback'));
      expect(snapshot.providerDetails, hasLength(1));
      expect(snapshot.providerDetails.single.name, 'debug.provider');
      expect(
        snapshot.providerDetails.single.debugName,
        'debug-provider-callback',
      );
      expect(
        snapshot.providerDetails.single.implementation,
        QuickjsHostProviderImplementation.platform,
      );
    });

    test('does not expose browser globals unless configured', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.eval('typeof window + "/" + typeof self'),
        'undefined/undefined',
      );
    });

    test('does not expose crypto randomUUID unless injected', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.eval(
          'typeof crypto === "undefined" || '
          'typeof crypto.randomUUID === "undefined"',
        ),
        'true',
      );
      expect(await engine.eval('typeof fetch'), 'undefined');
      expect(await engine.eval('typeof Buffer'), 'undefined');
    });

    test('installs configured browser global aliases consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          hostCapabilities: QuickjsHostCapabilities(
            browserGlobals: QuickjsBrowserGlobals(window: true, self: true),
          ),
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('window === globalThis && self === globalThis'),
        'true',
      );
      expect(
        await engine.eval('Object.keys(globalThis).includes("window")'),
        'false',
      );
    });

    test('installs host script crypto randomUUID consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          environmentPatches: <QuickjsHostScript>[_randomUuidHostScript],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('''
(() => {
  const first = crypto.randomUUID();
  const second = crypto.randomUUID();
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$/;
  return typeof first + '/' + pattern.test(first) + '/' +
    pattern.test(second) + '/' + (first !== second);
})()
'''),
        'string/true/true/true',
      );
    });

    test('installs minimal web crypto environment consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsWebCryptoMount(allowInsecureRandomFallback: true),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('''
(() => {
  const first = crypto.randomUUID();
  const second = crypto.randomUUID();
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$/;
  const bytes = new Uint8Array(8);
  const returned = crypto.getRandomValues(bytes);
  return [
    pattern.test(first),
    pattern.test(second),
    first !== second,
    returned === bytes,
    bytes.length,
    bytes.some((byte) => byte !== 0),
    typeof crypto.subtle
  ].join('/');
})()
'''),
        'true/true/true/true/8/true/undefined',
      );
    });

    test('can install selected web crypto helpers consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsWebCryptoMount(getRandomValues: false),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval(
          'typeof crypto.randomUUID + "/" + typeof crypto.getRandomValues',
        ),
        'function/undefined',
      );
    });

    test('rejects insecure web crypto random fallback by default', () async {
      if (kIsWeb) {
        return;
      }
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount()],
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('crypto.getRandomValues(new Uint8Array(1))'),
        throwsA(isA<JsException>()),
      );
    });

    test('rejects invalid web crypto getRandomValues targets', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount()],
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('crypto.getRandomValues(new Float32Array(1))'),
        throwsA(isA<JsException>()),
      );
      await expectLater(
        engine.eval('crypto.getRandomValues(new Uint8Array(65537))'),
        throwsA(isA<JsException>()),
      );
    });

    test('installs Flutter-backed web crypto digest consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount(subtleDigest: true)],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync('''
const data = new Uint8Array([104, 101, 108, 108, 111]);
const digest = await crypto.subtle.digest('SHA-256', data);
const sha1Digest = await crypto.subtle.digest('SHA-1', data);
const viewDigest = await crypto.subtle.digest(
  { name: 'SHA-256' },
  new Uint8Array([0, 104, 101, 108, 108, 111, 0]).subarray(1, 6),
);
const hex = Array.from(new Uint8Array(digest))
  .map((byte) => byte.toString(16).padStart(2, '0'))
  .join('');
const sha1Hex = Array.from(new Uint8Array(sha1Digest))
  .map((byte) => byte.toString(16).padStart(2, '0'))
  .join('');
const viewHex = Array.from(new Uint8Array(viewDigest))
  .map((byte) => byte.toString(16).padStart(2, '0'))
  .join('');
return (digest instanceof ArrayBuffer) + '/' + hex + '/' + sha1Hex + '/' + viewHex;
'''),
        'true/2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824/aaf4c61ddcc5e8a2dabede0f3b482cd9aea9434d/2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824',
      );
    });

    test('installs Flutter-backed web crypto HMAC consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount(subtleHmac: true)],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync('''
const keyBytes = new Uint8Array([107, 101, 121]);
const data = new Uint8Array([104, 101, 108, 108, 111]);
const key256 = await crypto.subtle.importKey(
  'raw',
  keyBytes,
  { name: 'HMAC', hash: 'SHA-256' },
  false,
  ['sign', 'verify']
);
const key1 = await crypto.subtle.importKey(
  'raw',
  keyBytes,
  { name: 'HMAC', hash: { name: 'SHA-1' } },
  false,
  ['sign', 'verify']
);
const signature256 = await crypto.subtle.sign('HMAC', key256, data);
const signature1 = await crypto.subtle.sign({ name: 'HMAC' }, key1, data);
const hex256 = Array.from(new Uint8Array(signature256))
  .map((byte) => byte.toString(16).padStart(2, '0'))
  .join('');
const hex1 = Array.from(new Uint8Array(signature1))
  .map((byte) => byte.toString(16).padStart(2, '0'))
  .join('');
const valid = await crypto.subtle.verify('HMAC', key256, signature256, data);
const invalid = await crypto.subtle.verify(
  'HMAC',
  key256,
  signature256,
  new Uint8Array([72, 69, 76, 76, 79])
);
return hex256 + '/' + hex1 + '/' + valid + '/' + invalid;
'''),
        '9307b3b915efb5171ff14d8cb55fbcc798c6c0ef1456d66ded1a6aa723a58b7b/b34ceac4516ff23a143e61d79d0fa7a4fbe5f266/true/false',
      );
    });

    test('web crypto digest rejects unsupported algorithms', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount(subtleDigest: true)],
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.evalAsync(
          "return await crypto.subtle.digest('MD5', new Uint8Array([1]));",
        ),
        throwsA(isA<JsException>()),
      );
    });

    test('installs async host providers for startup scripts', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'app.hello',
              callback: (args, _) {
                return 'hello ${args.single}';
              },
            ),
          ],
          environmentPatches: const <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'host:app-provider.js',
              source: '''
Object.defineProperty(globalThis, 'app', {
  value: {
    hello(name) {
      return globalThis.__quickjsHostProviders['app.hello'](name);
    },
  },
  configurable: true,
  enumerable: false,
  writable: true,
});
''',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync("return await app.hello('QuickJS');"),
        'hello QuickJS',
      );
    });

    test(
      'reinstalls async host providers after stop rebuilds runtime',
      () async {
        final engine = await Quickjs.create(
          options: QuickjsRuntimeOptions(
            providers: <QuickjsHostProvider>[
              QuickjsHostProvider.async(
                name: 'app.double',
                callback: (args, _) => (args.single! as num).toInt() * 2,
              ),
            ],
            environmentPatches: const <QuickjsHostScript>[
              QuickjsHostScript(
                name: 'host:provider-rebuild.js',
                source: '''
globalThis.app = {
  double(value) {
    return globalThis.__quickjsHostProviders['app.double'](value);
  },
};
''',
              ),
            ],
          ),
        );
        addTearDown(engine.dispose);

        final running = engine.eval('while (true) {}');
        await pumpEventQueue();
        await engine.stop();
        await expectLater(running, throwsA(isA<JsCancelledException>()));

        expect(await engine.evalAsync('return await app.double(21);'), '42');
      },
    );

    test('cancels pending async host providers on stop', () async {
      final invoked = Completer<QuickjsHostProviderContext>();
      var invocationCount = 0;
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'app.wait',
              callback: (_, context) async {
                invocationCount += 1;
                if (invocationCount == 1) {
                  invoked.complete(context);
                  await context.cancelled;
                  context.throwIfCancelled();
                }
                return 42;
              },
            ),
          ],
          environmentPatches: const <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'host:provider-cancel-stop.js',
              source: '''
globalThis.app = {
  wait() {
    return globalThis.__quickjsHostProviders['app.wait']();
  },
};
''',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      final running = engine.evalAsync('return await app.wait();');
      final context = await invoked.future.timeout(const Duration(seconds: 2));
      final runningFailure = expectLater(
        running,
        throwsA(
          anyOf(isA<JsCancelledException>(), isA<JsRuntimeClosedException>()),
        ),
      );

      await engine.stop().timeout(const Duration(seconds: 2));
      await runningFailure;
      expect(context.isCancelled, isTrue);
      expect(context.cancellationReason, isA<JsCancelledException>());
      expect(await engine.evalAsync('return await app.wait();'), '42');
    });

    test('dispose detaches pending async host provider Futures', () async {
      final invoked = Completer<QuickjsHostProviderContext>();
      final providerResult = Completer<Object?>();
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'app.wait',
              callback: (_, context) {
                invoked.complete(context);
                return providerResult.future;
              },
            ),
          ],
          environmentPatches: const <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'host:provider-cancel-dispose.js',
              source: '''
globalThis.app = {
  wait() {
    return globalThis.__quickjsHostProviders['app.wait']();
  },
};
''',
            ),
          ],
        ),
      );

      final running = engine.evalAsync('return await app.wait();');
      final context = await invoked.future.timeout(const Duration(seconds: 2));
      final runningFailure = expectLater(
        running,
        throwsA(
          anyOf(isA<JsCancelledException>(), isA<JsRuntimeClosedException>()),
        ),
      );

      await engine.dispose().timeout(const Duration(seconds: 2));
      await runningFailure;
      expect(context.isCancelled, isTrue);
      expect(context.cancellationReason, isA<JsRuntimeClosedException>());
    });

    test('keeps async host providers isolated per runtime', () async {
      QuickjsRuntimeOptions providerOptions(String value) {
        return QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'app.identity',
              callback: (_, _) => value,
            ),
          ],
          environmentPatches: const <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'host:provider-isolation.js',
              globals: <String>['app'],
              source: '''
globalThis.app = {
  identity() {
    return globalThis.__quickjsHostProviders['app.identity']();
  },
};
''',
            ),
          ],
        );
      }

      final first = await Quickjs.create(options: providerOptions('first'));
      final second = await Quickjs.create(options: providerOptions('second'));
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      expect(await first.evalAsync('return await app.identity();'), 'first');
      expect(await second.evalAsync('return await app.identity();'), 'second');

      await first.dispose();
      expect(await second.evalAsync('return await app.identity();'), 'second');
    });

    test('wraps async host providers from ES host modules', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'app.sum',
              callback: (args, _) {
                return args.fold<int>(
                  0,
                  (sum, value) => sum + (value! as num).toInt(),
                );
              },
            ),
          ],
          modules: const <QuickjsHostModule>[
            QuickjsHostModule.esModule(
              specifier: 'app/provider',
              source: '''
export function sum(...values) {
  return globalThis.__quickjsHostProviders['app.sum'](...values);
}
''',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalModule(
          "import { sum } from 'app/provider'; globalThis.providerSumPromise = sum(1, 2, 3);",
          name: 'app/provider-main.mjs',
        ),
        'undefined',
      );
      expect(
        await engine.evalAsync('return await globalThis.providerSumPromise;'),
        '6',
      );
    });

    test('rejects duplicate async host provider names', () async {
      await expectLater(
        Quickjs.create(
          options: QuickjsRuntimeOptions(
            providers: <QuickjsHostProvider>[
              QuickjsHostProvider.async(
                name: 'app.hello',
                callback: (_, _) => 1,
              ),
              QuickjsHostProvider.async(
                name: 'app.hello',
                callback: (_, _) => 2,
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('installs named host mounts as one capability bundle', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount(
              name: 'app-api',
              capabilities: const QuickjsHostCapabilities(
                browserGlobals: QuickjsBrowserGlobals(window: true),
              ),
              providers: <QuickjsHostProvider>[
                QuickjsHostProvider.async(
                  name: 'app.hello',
                  callback: (args, _) => 'hello ${args.single}',
                ),
              ],
              environmentPatches: const <QuickjsHostScript>[
                QuickjsHostScript(
                  name: 'mount:app-global.js',
                  source: '''
globalThis.app = {
  hello(name) {
    return globalThis.__quickjsHostProviders['app.hello'](name);
  },
};
''',
                ),
              ],
              modules: const <QuickjsHostModule>[
                QuickjsHostModule.esModule(
                  specifier: 'app/constants',
                  source: 'export const answer = 42;',
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync(
          "return typeof window + '/' + await app.hello('mount');",
        ),
        'object/hello mount',
      );
      expect(
        await engine.evalModule(
          "import { answer } from 'app/constants'; globalThis.mountAnswer = answer;",
          name: 'mount-main.mjs',
        ),
        'undefined',
      );
      expect(await engine.eval('mountAnswer'), '42');

      final snapshot = await engine.debugInspect();
      expect(snapshot.registeredMounts, contains('app-api'));
      expect(snapshot.registeredProviders, contains('app.hello'));
      expect(snapshot.moduleNames, contains('app/constants'));
    });

    test('reinstalls named host mounts after stop rebuilds runtime', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount(
              name: 'app-rebuild',
              environmentPatches: const <QuickjsHostScript>[
                QuickjsHostScript(
                  name: 'mount:rebuild.js',
                  source: 'globalThis.mountedValue = 42;',
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      final running = engine.eval('while (true) {}');
      await pumpEventQueue();
      await engine.stop();
      await expectLater(running, throwsA(isA<JsCancelledException>()));

      expect(await engine.eval('mountedValue'), '42');
      expect(
        (await engine.debugInspect()).registeredMounts,
        contains('app-rebuild'),
      );
    });

    test('installs named host mount presets consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.web(locationHref: 'https://example.test/app'),
            QuickjsWebCryptoMount(subtleDigest: true),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalAsync('''
const digest = await crypto.subtle.digest('SHA-256', new Uint8Array([1]));
return location.hostname + '/' + typeof crypto.randomUUID + '/' + digest.byteLength;
'''),
        'example.test/function/32',
      );
      expect(
        (await engine.debugInspect()).registeredMounts,
        containsAll(<String>['web', 'web-crypto']),
      );
    });

    test('mounts capability bundles at runtime by rebuilding', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      await engine.eval('globalThis.beforeMount = 1');

      await engine.mount(
        QuickjsHostMount(
          name: 'runtime-api',
          providers: <QuickjsHostProvider>[
            QuickjsHostProvider.async(
              name: 'runtime.echo',
              callback: (args, _) => args.single,
            ),
          ],
          environmentPatches: const <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'mount:runtime-api.js',
              source: '''
globalThis.runtimeApi = {
  echo(value) {
    return globalThis.__quickjsHostProviders['runtime.echo'](value);
  },
};
''',
            ),
          ],
          modules: const <QuickjsHostModule>[
            QuickjsHostModule.esModule(
              specifier: 'runtime/constants',
              source: 'export const value = 7;',
            ),
          ],
        ),
      );

      expect(await engine.eval('typeof beforeMount'), 'undefined');
      expect(
        await engine.evalAsync("return await runtimeApi.echo('mounted');"),
        'mounted',
      );
      expect(
        await engine.evalModule(
          "import { value } from 'runtime/constants'; globalThis.runtimeConstant = value;",
          name: 'runtime-main.mjs',
        ),
        'undefined',
      );
      expect(await engine.eval('runtimeConstant'), '7');
      expect(
        (await engine.debugInspect()).registeredMounts,
        contains('runtime-api'),
      );
    });

    test('replaces same-name runtime mounts atomically', () async {
      QuickjsHostMount versionedMount(int version) {
        return QuickjsHostMount(
          name: 'versioned-runtime',
          environmentPatches: <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'mount:versioned-runtime.js',
              globals: const <String>['runtimeMountVersion'],
              source: 'globalThis.runtimeMountVersion = $version;',
            ),
          ],
          modules: <QuickjsHostModule>[
            QuickjsHostModule.esModule(
              specifier: 'versioned/module',
              source: 'export const value = $version;',
            ),
          ],
        );
      }

      Future<String> readVersionedModule(Quickjs engine) async {
        await engine.evalModule('''
import { value } from 'versioned/module';
globalThis.versionedModuleValue = value;
''', name: 'versioned-check.mjs');
        return engine.eval('versionedModuleValue');
      }

      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      await engine.mount(versionedMount(1));
      expect(await engine.eval('runtimeMountVersion'), '1');
      expect(await readVersionedModule(engine), '1');

      await expectLater(
        engine.mount(versionedMount(2)),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(await engine.eval('runtimeMountVersion'), '1');

      await engine.mount(
        versionedMount(2),
        conflictPolicy: QuickjsHostMountConflictPolicy.replace,
      );
      expect(await engine.eval('runtimeMountVersion'), '2');
      expect(await readVersionedModule(engine), '2');
      expect(
        (await engine.debugInspect()).registeredMounts,
        contains('versioned-runtime'),
      );

      final running = engine.eval('while (true) {}');
      await pumpEventQueue();
      await engine.stop();
      await expectLater(running, throwsA(isA<JsCancelledException>()));
      expect(await engine.eval('runtimeMountVersion'), '2');
      expect(await readVersionedModule(engine), '2');
    });

    test('does not shadow modules already resolved by moduleLoader', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'dynamic/value' => 'export const value = 42;',
            'dynamic/cjs' => 'exports.value = 43;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);
      await engine.evalModule('''
import { value } from 'dynamic/value';
globalThis.dynamicLoaderValue = value;
''', name: 'dynamic-loader-main.mjs');
      expect(await engine.eval('dynamicLoaderValue'), '42');

      await expectLater(
        engine.mount(
          const QuickjsHostMount(
            name: 'dynamic-shadow',
            modules: <QuickjsHostModule>[
              QuickjsHostModule.esModule(
                specifier: 'dynamic/value',
                source: 'export const value = 7;',
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );

      expect(engine.state, QuickjsRuntimeState.ready);
      expect(await engine.eval('dynamicLoaderValue'), '42');
      expect(
        (await engine.debugInspect()).registeredMounts,
        isNot(contains('dynamic-shadow')),
      );

      expect(
        await engine.evalCommonJs(
          "module.exports = require('dynamic/cjs').value;",
          name: 'dynamic-loader-main.cjs',
        ),
        '43',
      );
      await expectLater(
        engine.mount(
          const QuickjsHostMount(
            name: 'dynamic-cjs-shadow',
            modules: <QuickjsHostModule>[
              QuickjsHostModule.commonJs(
                specifier: 'dynamic/cjs',
                source: 'exports.value = 8;',
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(engine.state, QuickjsRuntimeState.ready);
    });

    test('does not replace initialization mounts at runtime', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount(
              name: 'static-mount',
              environmentPatches: <QuickjsHostScript>[
                QuickjsHostScript(
                  name: 'mount:static.js',
                  globals: <String>['staticMountValue'],
                  source: 'globalThis.staticMountValue = 42;',
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.mount(
          const QuickjsHostMount(name: 'static-mount'),
          conflictPolicy: QuickjsHostMountConflictPolicy.replace,
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(await engine.eval('staticMountValue'), '42');
      expect(engine.state, QuickjsRuntimeState.ready);
    });

    test('rolls back runtime mount replacement when rebuild fails', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      await engine.mount(
        const QuickjsHostMount(
          name: 'replace-rollback',
          environmentPatches: <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'mount:replace-rollback.js',
              globals: <String>['replaceRollbackValue'],
              source: 'globalThis.replaceRollbackValue = 1;',
            ),
          ],
        ),
      );

      await expectLater(
        engine.mount(
          const QuickjsHostMount(
            name: 'replace-rollback',
            environmentPatches: <QuickjsHostScript>[
              QuickjsHostScript(
                name: 'mount:replace-rollback.js',
                globals: <String>['replaceRollbackValue'],
                source: 'throw new Error("replacement install failed");',
              ),
            ],
          ),
          conflictPolicy: QuickjsHostMountConflictPolicy.replace,
        ),
        throwsA(isA<JsException>()),
      );

      expect(engine.state, QuickjsRuntimeState.ready);
      expect(await engine.eval('replaceRollbackValue'), '1');
      expect(
        (await engine.debugInspect()).registeredMounts,
        contains('replace-rollback'),
      );
    });

    test('keeps runtime mounts across later stop rebuilds', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      await engine.mount(
        const QuickjsHostMount(
          name: 'runtime-rebuild',
          environmentPatches: <QuickjsHostScript>[
            QuickjsHostScript(
              name: 'mount:runtime-rebuild.js',
              source: 'globalThis.runtimeMountedValue = 42;',
            ),
          ],
        ),
      );

      final running = engine.eval('while (true) {}');
      await pumpEventQueue();
      await engine.stop();
      await expectLater(running, throwsA(isA<JsCancelledException>()));

      expect(await engine.eval('runtimeMountedValue'), '42');
    });

    test('rejects conflicting runtime mounts without rebuilding', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount(
              name: 'existing',
              providers: <QuickjsHostProvider>[
                QuickjsHostProvider.async(
                  name: 'existing.provider',
                  callback: (_, _) => 42,
                ),
              ],
              environmentPatches: <QuickjsHostScript>[
                QuickjsHostScript(
                  name: 'mount:existing.js',
                  globals: <String>['existingValue'],
                  source: 'globalThis.existingValue = 42;',
                ),
              ],
              modules: <QuickjsHostModule>[
                QuickjsHostModule.esModule(
                  specifier: 'existing/module',
                  source: 'export const value = 42;',
                ),
              ],
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.mount(const QuickjsHostMount(name: 'existing')),
        throwsA(isA<JsValueConversionException>()),
      );
      await expectLater(
        engine.mount(
          QuickjsHostMount(
            name: 'provider-conflict',
            providers: <QuickjsHostProvider>[
              QuickjsHostProvider.async(
                name: 'existing.provider',
                callback: (_, _) => 7,
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      await expectLater(
        engine.mount(
          const QuickjsHostMount(
            name: 'module-conflict',
            modules: <QuickjsHostModule>[
              QuickjsHostModule.esModule(
                specifier: 'existing/module',
                source: 'export const value = 7;',
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      await expectLater(
        engine.mount(
          const QuickjsHostMount(
            name: 'global-conflict',
            environmentPatches: <QuickjsHostScript>[
              QuickjsHostScript(
                name: 'mount:global-conflict.js',
                globals: <String>['existingValue'],
                source: 'globalThis.existingValue = 7;',
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(await engine.eval('existingValue'), '42');
      expect(engine.state, QuickjsRuntimeState.ready);
    });

    test('rejects runtime mounts while JavaScript is running', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final running = engine.eval('while (true) {}');
      await pumpEventQueue();
      await expectLater(
        engine.mount(const QuickjsHostMount(name: 'busy')),
        throwsA(isA<StateError>()),
      );
      await engine.stop();
      await expectLater(running, throwsA(isA<JsCancelledException>()));
    });

    test(
      'rejects duplicate host mount, patch, and declared global names',
      () async {
        await expectLater(
          Quickjs.create(
            options: const QuickjsRuntimeOptions(
              mounts: <QuickjsHostMount>[
                QuickjsHostMount(name: 'duplicate'),
                QuickjsHostMount(name: 'duplicate'),
              ],
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );

        await expectLater(
          Quickjs.create(
            options: const QuickjsRuntimeOptions(
              mounts: <QuickjsHostMount>[
                QuickjsHostMount(
                  name: 'first',
                  environmentPatches: <QuickjsHostScript>[
                    QuickjsHostScript(name: 'same.js', source: 'void 0;'),
                  ],
                ),
                QuickjsHostMount(
                  name: 'second',
                  environmentPatches: <QuickjsHostScript>[
                    QuickjsHostScript(name: 'same.js', source: 'void 0;'),
                  ],
                ),
              ],
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );

        await expectLater(
          Quickjs.create(
            options: const QuickjsRuntimeOptions(
              mounts: <QuickjsHostMount>[
                QuickjsHostMount(
                  name: 'first-global',
                  environmentPatches: <QuickjsHostScript>[
                    QuickjsHostScript(
                      name: 'first.js',
                      globals: <String>['app'],
                      source: 'globalThis.app = 1;',
                    ),
                  ],
                ),
                QuickjsHostMount(
                  name: 'second-global',
                  environmentPatches: <QuickjsHostScript>[
                    QuickjsHostScript(
                      name: 'second.js',
                      globals: <String>['app'],
                      source: 'globalThis.app = 2;',
                    ),
                  ],
                ),
              ],
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );

        await expectLater(
          Quickjs.create(
            options: const QuickjsRuntimeOptions(
              hostCapabilities: QuickjsHostCapabilities(
                browserGlobals: QuickjsBrowserGlobals(window: true),
              ),
              environmentPatches: <QuickjsHostScript>[
                QuickjsHostScript(
                  name: 'window-conflict.js',
                  globals: <String>['window'],
                  source: 'globalThis.window = {};',
                ),
              ],
            ),
          ),
          throwsA(isA<JsValueConversionException>()),
        );
      },
    );

    test('installs configured host mounts consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount(
              name: 'configured',
              capabilities: QuickjsHostCapabilities(
                browserGlobals: QuickjsBrowserGlobals(window: true),
              ),
              environmentPatches: <QuickjsHostScript>[_randomUuidHostScript],
              modules: <QuickjsHostModule>[_hostMathModule],
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(await engine.eval('window === globalThis'), 'true');
      expect(
        await engine.eval('typeof crypto.randomUUID() === "string"'),
        'true',
      );
      await engine.evalModule('''
import { add, value } from 'app/math';
globalThis.hostEnvironmentModuleValue = add(value, 1);
''', name: 'main.mjs');
      expect(await engine.eval('globalThis.hostEnvironmentModuleValue'), '42');
      expect((await engine.debugInspect()).moduleNames, contains('app/math'));
    });

    test('installs minimal web host environment consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.web(
              locationHref: 'https://example.com:8443/app?q=1#top',
              userAgent: 'quickjs-test',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('''
(() => {
  localStorage.setItem('answer', 42);
  sessionStorage.setItem('answer', 7);
  const url = new URL('https://dart.dev/docs?tab=api#top');
  return [
    window === globalThis,
    self === globalThis,
    location.origin,
    location.pathname,
    location.search,
    location.hash,
    navigator.userAgent,
    localStorage.getItem('answer'),
    sessionStorage.getItem('answer'),
    localStorage.length,
    url.hostname,
    url.pathname
  ].join('|');
})()
'''),
        'true|true|https://example.com:8443|/app|?q=1|#top|quickjs-test|42|7|1|dart.dev|/docs',
      );
    });

    test('installs essential buffer modules consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsHostMount.essential()],
        ),
      );
      addTearDown(engine.dispose);

      expect(await engine.eval('typeof Buffer'), 'undefined');
      await engine.evalModule('''
import { Buffer } from 'node:buffer';
const first = Buffer.from('hello');
const second = Buffer.from([65, 66, 67]);
globalThis.essentialBufferValue = [
  Buffer.isBuffer(first),
  first.toString(),
  second.toString(),
  Buffer.byteLength('hello')
].join('/');
''', name: 'main.mjs');
      expect(
        await engine.eval('globalThis.essentialBufferValue'),
        'true/hello/ABC/5',
      );
      expect(
        await engine.evalCommonJs('''
const { Buffer } = require('node:buffer');
const value = Buffer.from('cjs');
module.exports = Buffer.isBuffer(value) + '/' + value.toString() + '/' + value.length;
''', name: 'main.cjs'),
        'true/cjs/3',
      );
    });

    test('installs essential global Buffer when requested', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.essential(globalBuffer: true),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval(
          "Buffer.isBuffer(Buffer.from('global')) + '/' + Buffer.from('global').toString()",
        ),
        'true/global',
      );
    });

    test('installs node preset modules without globals by default', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.node(
              env: <String, String>{'APP_ENV': 'test'},
              platform: 'test-platform',
              cwd: '/workspace/app',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('typeof Buffer + "/" + typeof process'),
        'undefined/undefined',
      );
      await engine.evalModule('''
import { Buffer } from 'node:buffer';
import crypto, { createHash, randomBytes } from 'node:crypto';
import path from 'node:path';
import process, { env, platform, cwd } from 'node:process';
import { setTimeout } from 'node:timers';
const bytes = randomBytes(4);
globalThis.nodePresetValue = [
  Buffer.from('node').toString(),
  Buffer.isBuffer(bytes),
  bytes.length,
  createHash('sha256').update('hello').digest('hex'),
  crypto.createHash('sha256').update(Buffer.from('hello')).digest().toString('hex'),
  path.join('/app', 'src', '..', 'main.js'),
  path.basename('/app/main.js', '.js'),
  process.env.APP_ENV,
  env.APP_ENV,
  process.platform,
  platform,
  process.cwd(),
  cwd(),
  typeof setTimeout
].join('|');
''', name: 'main.mjs');

      expect(
        await engine.eval('globalThis.nodePresetValue'),
        'node|true|4|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|/app/main.js|main|test|test|test-platform|test-platform|/workspace/app|/workspace/app|function',
      );
      final modules = (await engine.debugInspect()).moduleNames;
      expect(
        modules,
        containsAll(<String>['buffer', 'crypto', 'path', 'process', 'timers']),
      );
    });

    test('installs node preset CommonJS modules consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.node(
              env: <String, String>{'MODE': 'cjs'},
              cwd: '/cjs',
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs('''
const { Buffer } = require('node:buffer');
const crypto = require('node:crypto');
const path = require('node:path');
const process = require('node:process');
const timers = require('node:timers');
const bytes = crypto.randomBytes(3);
module.exports = [
  Buffer.from('cjs').toString(),
  Buffer.isBuffer(bytes),
  bytes.length,
  crypto.createHash('sha256').update('hello').digest('hex'),
  path.dirname('/app/main.js'),
  path.extname('/app/main.js'),
  process.env.MODE,
  process.cwd(),
  typeof timers.clearTimeout
].join('|');
''', name: 'main.cjs'),
        'cjs|true|3|2cf24dba5fb0a30e26e83b2ac5b9e29e1b161e5c1fa7425e73043362938b9824|/app|.js|cjs|/cjs|function',
      );
    });

    test('installs node preset globals when requested', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.node(
              globalBuffer: true,
              globalProcess: true,
              env: <String, String>{'GLOBAL_MODE': 'enabled'},
            ),
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('''
[
  Buffer.from('global-node').toString(),
  process.env.GLOBAL_MODE,
  process.versions.quickjs
].join('|')
'''),
        'global-node|enabled|0.15.1',
      );
    });

    test('loads configured ES host modules consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[_hostMathModule],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalModule('''
import { add, value } from 'app/math';
globalThis.hostModuleValue = add(value, 1);
''', name: 'main.mjs'),
        'undefined',
      );
      expect(await engine.eval('globalThis.hostModuleValue'), '42');
    });

    test('does not expose host modules as globals consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[_hostBufferModule],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.eval('typeof Buffer + "/" + typeof label'),
        'undefined/undefined',
      );
      await engine.evalModule('''
import { label } from 'buffer';
globalThis.hostBufferImportLabel = label;
''', name: 'main.mjs');
      expect(
        await engine.eval('globalThis.hostBufferImportLabel'),
        'host-buffer',
      );
    });

    test('keeps global crypto and node crypto module separate', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          environmentPatches: <QuickjsHostScript>[_randomUuidHostScript],
          modules: <QuickjsHostModule>[_hostCryptoModule],
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalModule('''
import { label, randomBytes } from 'node:crypto';
globalThis.hostNodeCryptoValue =
  typeof crypto.randomUUID + '/' + label + '/' + randomBytes(4);
''', name: 'main.mjs');

      expect(
        await engine.eval('globalThis.hostNodeCryptoValue'),
        'function/node-crypto-module/bytes:4',
      );
    });

    test(
      'normalizes node-prefixed host module specifiers consistently',
      () async {
        final engine = await Quickjs.create(
          options: const QuickjsRuntimeOptions(
            modules: <QuickjsHostModule>[_hostBufferModule],
          ),
        );
        addTearDown(engine.dispose);

        expect(
          await engine.evalModule('''
import { byteLength, label } from 'node:buffer';
globalThis.hostNodeBufferValue = label + '/' + byteLength('abcd');
''', name: 'main.mjs'),
          'undefined',
        );
        expect(
          await engine.eval('globalThis.hostNodeBufferValue'),
          'host-buffer/4',
        );
      },
    );

    test('loads relative dependencies between ES host modules', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[
            _hostPackageMainModule,
            _hostPackageDepModule,
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalModule(
          "import { result } from 'pkg/main'; globalThis.hostPackageValue = result;",
          name: 'main.mjs',
        ),
        'undefined',
      );
      expect(await engine.eval('globalThis.hostPackageValue'), '10');
    });

    test('loads ES host module dependencies from moduleLoader', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          modules: const <QuickjsHostModule>[_hostModuleLoaderMainModule],
          moduleLoader: (name) => switch (name) {
            'loader/dep' => 'export const value = 40;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalModule('''
import { result } from 'loader/main';
globalThis.hostLoaderDependencyValue = result;
''', name: 'main.mjs');

      expect(await engine.eval('globalThis.hostLoaderDependencyValue'), '41');
    });

    test('prefers ES host modules over moduleLoader consistently', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          modules: const <QuickjsHostModule>[_hostMathModule],
          moduleLoader: (name) => switch (name) {
            'app/math' =>
              'export const value = -1; export const add = () => -1;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalModule('''
import { add, value } from 'app/math';
globalThis.hostPreferredValue = add(value, 1);
''', name: 'main.mjs');

      expect(await engine.eval('globalThis.hostPreferredValue'), '42');
    });

    test('caches ES host modules in one runtime consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[_hostCounterModule],
        ),
      );
      addTearDown(engine.dispose);

      await engine.evalModule('''
import { count as first } from 'app/counter';
import { count as second } from 'app/counter';
globalThis.hostCounterResult = first + '/' + second + '/' + globalThis.hostModuleImportCount;
''', name: 'main.mjs');

      expect(await engine.eval('globalThis.hostCounterResult'), '1/1/1');
    });

    test('loads configured CommonJS host modules consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[
            _hostCommonJsModule,
            _hostCommonJsLocalModule,
          ],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs(
          "const cjs = require('app/cjs'); module.exports = cjs.value;",
          name: 'main.cjs',
        ),
        '7',
      );
    });

    test('caches CommonJS host modules in one runtime consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[_hostCommonJsCounterModule],
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs('''
const first = require('app/cjs-counter');
const second = require('app/cjs-counter');
module.exports = first.count + '/' + second.count + '/' + globalThis.hostCommonJsImportCount;
''', name: 'main.cjs'),
        '1/1/1',
      );
    });

    test('loads CommonJS host module dependencies from moduleLoader', () async {
      final engine = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          modules: const <QuickjsHostModule>[_hostCommonJsLoaderMainModule],
          moduleLoader: (name) => switch (name) {
            'loader/cjs-dep' => 'exports.value = 40;',
            _ => null,
          },
        ),
      );
      addTearDown(engine.dispose);

      expect(
        await engine.evalCommonJs(
          "module.exports = require('loader/cjs-main').result;",
          name: 'main.cjs',
        ),
        '41',
      );
    });

    test(
      'prefers CommonJS host modules over moduleLoader consistently',
      () async {
        final engine = await Quickjs.create(
          options: QuickjsRuntimeOptions(
            modules: const <QuickjsHostModule>[_hostCommonJsModule],
            moduleLoader: (name) => switch (name) {
              'app/cjs' => 'module.exports = { value: -1 };',
              'app/local' => 'exports.value = 6;',
              _ => null,
            },
          ),
        );
        addTearDown(engine.dispose);

        expect(
          await engine.evalCommonJs(
            "module.exports = require('app/cjs').value;",
            name: 'main.cjs',
          ),
          '7',
        );
      },
    );

    test(
      'normalizes node-prefixed CommonJS host modules consistently',
      () async {
        final engine = await Quickjs.create(
          options: const QuickjsRuntimeOptions(
            modules: <QuickjsHostModule>[_hostCommonJsBufferModule],
          ),
        );
        addTearDown(engine.dispose);

        expect(
          await engine.evalCommonJs(
            "module.exports = require('node:buffer').label;",
            name: 'main.cjs',
          ),
          'commonjs-buffer',
        );
      },
    );

    test('rejects duplicate host module specifiers consistently', () async {
      await expectLater(
        Quickjs.create(
          options: const QuickjsRuntimeOptions(
            modules: <QuickjsHostModule>[
              QuickjsHostModule.esModule(
                specifier: 'dup',
                source: 'export const value = 1;',
              ),
              QuickjsHostModule.esModule(
                specifier: 'node:dup',
                source: 'export const value = 2;',
              ),
            ],
          ),
        ),
        throwsA(isA<JsValueConversionException>()),
      );
    });

    test('keeps host capability configuration isolated by runtime', () async {
      final enabled = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          hostCapabilities: QuickjsHostCapabilities(
            browserGlobals: QuickjsBrowserGlobals(window: true),
          ),
        ),
      );
      final disabled = await Quickjs.create();
      addTearDown(enabled.dispose);
      addTearDown(disabled.dispose);

      expect(await enabled.eval('window === globalThis'), 'true');
      expect(await disabled.eval('typeof window'), 'undefined');
    });

    test('reinstalls host environment after stop rebuilds runtime', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          hostCapabilities: QuickjsHostCapabilities(
            browserGlobals: QuickjsBrowserGlobals(window: true),
          ),
          environmentPatches: <QuickjsHostScript>[_randomUuidHostScript],
          modules: <QuickjsHostModule>[_hostMathModule],
        ),
      );
      addTearDown(engine.dispose);

      final running = engine.eval('while (true) {}');
      await Future<void>.delayed(const Duration(milliseconds: 50), engine.stop);
      await expectLater(running, throwsA(isA<JsCancelledException>()));

      expect(await engine.eval('window === globalThis'), 'true');
      expect(
        await engine.eval('typeof crypto.randomUUID() === "string"'),
        'true',
      );
      expect(
        await engine.evalModule(
          "import { value } from 'app/math'; globalThis.rebuiltHostModuleValue = value + 1;",
          name: 'main.mjs',
        ),
        'undefined',
      );
      expect(await engine.eval('globalThis.rebuiltHostModuleValue'), '42');
    });

    // 同一 runtime 内并发 eval 必须按 FIFO 顺序串行。
    test('queues concurrent evaluations in order', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final results = await Future.wait([
        engine.eval('globalThis.queue = (globalThis.queue || "") + "a"'),
        engine.eval('globalThis.queue = (globalThis.queue || "") + "b"'),
        engine.eval('globalThis.queue = (globalThis.queue || "") + "c"'),
      ]);

      expect(results, ['a', 'ab', 'abc']);
    });

    // 澶?runtime 鐨?globalThis 鍩虹闅旂蹇呴』涓€鑷淬€?
    test('keeps runtime globals isolated', () async {
      final first = await Quickjs.create();
      final second = await Quickjs.create();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      expect(await first.eval('globalThis.sharedName = "first"'), 'first');
      expect(await second.eval('globalThis.sharedName'), 'undefined');
      expect(await second.eval('globalThis.sharedName = "second"'), 'second');
      expect(await first.eval('globalThis.sharedName'), 'first');
      expect(await second.eval('globalThis.sharedName'), 'second');
    });

    // timeout 鍚庡悓涓€涓?Quickjs 瀹炰緥搴旀仮澶嶄负鍙户缁?eval 鐨勭姸鎬併€?
    test('recovers after timeout', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval(
          'while (true) {}',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<JsTimeoutException>()),
      );

      expect(await engine.eval('21 * 2'), '42');
    });

    // web 渚?timeout 浼?terminate shared Worker锛涘叾瀹?runtime 涓嬩竴娆?eval 蹇呴』鑷姩鎭㈠銆?
    // native 渚ф瘡涓?runtime 鐙崰 worker锛屽洜姝?peer runtime 鐨?globals 涓嶅簲涓㈠け銆?
    test('keeps peer runtime usable after timeout recovery', () async {
      final first = await Quickjs.create();
      final second = await Quickjs.create();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      expect(await second.eval('globalThis.peerValue = 2'), '2');
      await expectLater(
        first.eval(
          'while (true) {}',
          timeout: const Duration(milliseconds: 50),
        ),
        throwsA(isA<JsTimeoutException>()),
      );

      expect(await first.eval('1 + 1'), '2');
      expect(
        await second.eval('globalThis.peerValue'),
        kIsWeb ? 'undefined' : '2',
      );
      expect(await second.eval('40 + 2'), '42');
    });

    // native 鍜?web 閮藉簲鎶?memory limit 瓒呴檺鏄犲皠鎴愬悓涓€涓叕寮€閿欒绫诲瀷銆?
    test('maps memory limit failures consistently', () async {
      final engine = await Quickjs.create(
        options: const QuickjsRuntimeOptions(memoryLimitBytes: 256 * 1024),
      );
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('new Array(1000000).fill("quickjs").join("")'),
        throwsA(isA<JsOutOfMemoryException>()),
      );
      expect(await engine.eval('1 + 1'), '2');
    });

    // stop 鍚庡悓涓€涓?Quickjs 瀹炰緥搴旀仮澶嶄负鍙户缁?eval 鐨勭姸鎬併€?
    test('recovers after stop', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      final running = engine.eval('while (true) {}');
      final stopFuture = Future<void>.delayed(
        const Duration(milliseconds: 50),
        engine.stop,
      );

      await expectLater(running, throwsA(isA<JsCancelledException>()));
      await stopFuture.timeout(const Duration(seconds: 2));
      expect(await engine.eval('21 * 2'), '42');
    });

    // dispose 鍚庣户缁?eval 蹇呴』杩斿洖 closed error銆?
    test('rejects evaluation after dispose', () async {
      final engine = await Quickjs.create();
      await engine.dispose();

      await expectLater(
        engine.eval('1 + 1'),
        throwsA(isA<JsRuntimeClosedException>()),
      );
    });
  });
}
