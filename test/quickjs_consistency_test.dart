import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

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

    // Promise-based Dart callback 鍦?native 鍜?web 涓婇兘搴?resolve 涓?JS await 缁撴灉銆?
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

    // 鍚屼竴 runtime 鍐呭苟鍙?eval 蹇呴』鎸?FIFO 椤哄簭涓茶銆?
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
