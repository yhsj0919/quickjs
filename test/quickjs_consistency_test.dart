import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('native/web consistency', () {
    // 最小求值语义必须在 native FFI 和 Web WASM 上一致。
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

    // 结构化返回 API 在 native 和 web 上应保持基础 primitive 映射一致。
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

    // BigInt 在 native 和 web 上都应映射为 Dart BigInt。
    test('maps BigInt values to Dart BigInt', () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      expect(
        await engine.evaluateValue('9007199254740993n'),
        BigInt.parse('9007199254740993'),
      );
    });

    // JSON-compatible array / plain object 在 native 和 web 上保持同样结构。
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

    // ArrayBuffer / Uint8Array 在 native 和 web 上都应映射为 Uint8List。
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

    // 不可直接转换值在 native 和 web 上都应返回同一类公开转换错误。
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

    // Dart globals 注入在 native 和 web 上应保持同样的转换与恢复语义。
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

    // Promise-based Dart callback 在 native 和 web 上都应 resolve 为 JS await 结果。
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
      final second = await Quickjs.create();
      addTearDown(first.dispose);
      addTearDown(second.dispose);

      final results = await Future.wait([
        first.evalAsync(
          'globalThis.timerName = "first";'
          'return await new Promise((resolve) => '
          'setTimeout(() => resolve(timerName), 1));',
        ),
        second.evalAsync(
          'globalThis.timerName = "second";'
          'return await new Promise((resolve) => '
          'setTimeout(() => resolve(timerName), 1));',
        ),
      ]);

      expect(results, ['first', 'second']);
    });

    // JS throw 不能被当成普通字符串结果。
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

    // 多 runtime 的 globalThis 基础隔离必须一致。
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

    // timeout 后同一个 Quickjs 实例应恢复为可继续 eval 的状态。
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

    // web 侧 timeout 会 terminate shared Worker；其它 runtime 下一次 eval 必须自动恢复。
    // native 侧每个 runtime 独占 worker，因此 peer runtime 的 globals 不应丢失。
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

    // native 和 web 都应把 memory limit 超限映射成同一个公开错误类型。
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

    // stop 后同一个 Quickjs 实例应恢复为可继续 eval 的状态。
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

    // dispose 后继续 eval 必须返回 closed error。
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
