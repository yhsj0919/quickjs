import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js/src/native/quickjs_native_worker.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 最小闭环：创建 runtime、执行 JS、读取版本。
  test('create and evaluate', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.quickjsVersion, '0.15.1');
    expect(await engine.eval('1 + 2'), 3);
    expect(await engine.evalRaw('1 + 2'), '3');
  });

  // 同一个 Quickjs 实例应能重复执行，不需要每次重新创建 runtime。
  test('quickjs instance can be reused', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.state, JsRuntimeState.ready);
    expect(await engine.eval('"a" + "b"'), 'ab');
    expect(await engine.eval('2 ** 10'), 1024);
    expect(await engine.run('return await Promise.resolve(6 * 7);'), 42);
    expect(await engine.runRaw('return await Promise.resolve(6 * 7);'), '42');
    expect(engine.state, JsRuntimeState.ready);
  });

  // 结构化返回 API 不改变 eval 的字符串语义，先覆盖 JS primitives。
  test('eval maps primitive JavaScript values', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    expect(await engine.eval('1 + 2'), 3);
    expect(await engine.eval('1.5 + 2'), 3.5);
    expect(await engine.eval('true'), true);
    expect(await engine.eval('"hello"'), 'hello');
    expect(await engine.eval('null'), isNull);
    expect(await engine.eval('undefined'), isA<JsUndefined>());
    expect(await engine.evalRaw('undefined'), 'undefined');
  });

  // 结构化返回继续覆盖 JSON-compatible array 和 plain object。
  test('eval maps arrays and plain objects', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    expect(await engine.eval('[1, "two", true, null]'), <Object?>[
      1,
      'two',
      true,
      null,
    ]);
    expect(await engine.eval('({ a: 1, b: "two", c: false })'), {
      'a': 1,
      'b': 'two',
      'c': false,
    });
    expect(await engine.eval('({ nested: [1, { ok: true }, null] })'), {
      'nested': [
        1,
        {'ok': true},
        null,
      ],
    });
  });

  // ArrayBuffer / Uint8Array 应映射为 Dart Uint8List。
  test('eval maps binary buffers to Uint8List', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    expect(
      await engine.eval('new Uint8Array([1, 2, 255])'),
      Uint8List.fromList([1, 2, 255]),
    );
    expect(
      await engine.eval('new Uint8Array([3, 4, 5]).buffer'),
      Uint8List.fromList([3, 4, 5]),
    );
  });

  // JS bigint 应映射为 Dart BigInt，避免大整数精度丢失。
  test('eval maps BigInt values', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    expect(
      await engine.eval('9007199254740993n'),
      BigInt.parse('9007199254740993'),
    );
  });

  // 不可直接转换的 JS 值应给出明确的 Dart 错误，而不是静默丢值。
  test('eval rejects unsupported JavaScript values', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('Symbol("id")'),
      throwsA(isA<JsValueConversionException>()),
    );
    await expectLater(
      engine.eval('() => 1'),
      throwsA(isA<JsValueConversionException>()),
    );
    await expectLater(
      engine.eval('[1, Symbol("id")]'),
      throwsA(isA<JsValueConversionException>()),
    );
    await expectLater(
      engine.eval('const value = {}; value.self = value; value'),
      throwsA(isA<JsValueConversionException>()),
    );
  });

  test(
    'eval rejects overly deep object graphs before JS stack overflow',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('''
let value = { leaf: true };
for (let i = 0; i < 256; i += 1) {
  value = { child: value };
}
value;
'''),
        throwsA(
          isA<JsValueConversionException>().having(
            (error) => error.message,
            'message',
            contains('object graph is too deep'),
          ),
        ),
      );
    },
  );

  test('eval budgets containers rather than primitive leaves', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final flat = await engine.eval(
      'Array.from({ length: 15000 }, (_, index) => index)',
    );
    expect(flat, isA<List<Object?>>());
    expect((flat! as List<Object?>).length, 15000);

    await expectLater(
      engine.eval('Array.from({ length: 10001 }, () => ({}))'),
      throwsA(
        isA<JsValueConversionException>().having(
          (error) => error.message,
          'message',
          contains('object graph is too large'),
        ),
      ),
    );
  });

  test(
    'callPlugin rejects overly deep return values before JS stack overflow',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      final plugin = JsPlugin.singleFile(
        id: 'deep_return',
        version: '1.0.0',
        exports: const <String>['render'],
        source: '''
export function render() {
  let value = { type: 'Text', data: 'leaf' };
  for (let i = 0; i < 256; i += 1) {
    value = { type: 'Container', child: value };
  }
  return value;
}
''',
      );
      await engine.loadFeatures(plugin.asFeatures());

      await expectLater(
        engine.callPlugin(plugin, 'render', const <Object?>[]),
        throwsA(
          isA<JsValueConversionException>().having(
            (error) => error.message,
            'message',
            contains('object graph is too deep'),
          ),
        ),
      );
    },
  );

  test(
    'callPlugin rejects overly deep arguments before JS stack overflow',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);
      final plugin = JsPlugin.singleFile(
        id: 'deep_args',
        version: '1.0.0',
        exports: const <String>['echo'],
        source: '''
export function echo(value) {
  return value;
}
''',
      );
      await engine.loadFeatures(plugin.asFeatures());

      Object? value = <String, Object?>{'leaf': true};
      for (var index = 0; index < 256; index += 1) {
        value = <String, Object?>{'child': value};
      }

      await expectLater(
        engine.callPlugin(plugin, 'echo', <Object?>[value]),
        throwsA(
          isA<JsException>().having(
            (error) => error.message,
            'message',
            contains('QuickJS Dart value graph is too deep'),
          ),
        ),
      );
    },
  );

  // Dart values can be injected as temporary JS globals for one evaluation.
  test('eval maps Dart globals to JavaScript values', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final value = await engine.eval(
      '''
({
  intValue,
  doubleValue,
  boolValue,
  stringValue,
  nullValue,
  bytesValue: Array.from(bytesValue),
  listValue,
  mapValue,
  dateValue: dateValue.toISOString(),
})
''',
      globals: {
        'intValue': 42,
        'doubleValue': 1.5,
        'boolValue': true,
        'stringValue': 'hello',
        'nullValue': null,
        'bytesValue': Uint8List.fromList([1, 2, 255]),
        'listValue': [1, 'two', false, null],
        'mapValue': {
          'nested': [
            1,
            {'ok': true},
          ],
        },
        'dateValue': DateTime.utc(2026, 6, 10, 1, 2, 3, 4),
      },
    );

    expect(value, {
      'intValue': 42,
      'doubleValue': 1.5,
      'boolValue': true,
      'stringValue': 'hello',
      'nullValue': null,
      'bytesValue': [1, 2, 255],
      'listValue': [1, 'two', false, null],
      'mapValue': {
        'nested': [
          1,
          {'ok': true},
        ],
      },
      'dateValue': '2026-06-10T01:02:03.004Z',
    });
  });

  // Injected globals are temporary and should restore pre-existing runtime state.
  test('eval globals are restored after evaluation', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    expect(await engine.eval('globalThis.answer = 1'), '1');
    expect(
      await engine.eval('answer + extra', globals: {'answer': 41, 'extra': 1}),
      '42',
    );
    expect(await engine.eval('answer'), '1');
    expect(await engine.eval('typeof extra'), 'undefined');
  });

  test('bound Dart callback resolves JavaScript Promise', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await engine.injectFunction('hostAdd', (args) {
      return (args[0] as num).toInt() + (args[1] as num).toInt();
    });

    expect(await engine.call('hostAdd', [20, 22]), 42);
    expect(await engine.callRaw('hostAdd', [20, 22]), '42');
  });

  test(
    'call safely passes structured arguments to a global function',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.evalRaw('''
globalThis.describe = async function(value) {
  return { receiver: this === globalThis, value };
};
''');

      expect(
        await engine.call('describe', [
          {
            'text': 'quote: " and newline:\n',
            'items': [1, true, null],
          },
        ]),
        {
          'receiver': true,
          'value': {
            'text': 'quote: " and newline:\n',
            'items': [1, true, null],
          },
        },
      );
    },
  );

  test('call rejects a global that is not a function', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    await engine.evalRaw('globalThis.answer = 42');

    await expectLater(
      engine.call('answer', const []),
      throwsA(isA<JsThrownException>()),
    );
  });

  test(
    'bound Dart callback rejection is reported as JsThrownException',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await engine.injectFunction('hostFail', (_) {
        throw StateError('host failed');
      });

      await expectLater(
        engine.run('return await hostFail();'),
        throwsA(
          isA<JsThrownException>().having(
            (error) => error.message,
            'message',
            contains('host failed'),
          ),
        ),
      );
    },
  );

  // Unsupported Dart globals should fail before entering JS execution.
  test('eval rejects unsupported Dart globals', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('value', globals: {'value': Object()}),
      throwsA(isA<JsValueConversionException>()),
    );
    final cyclic = <Object?>[];
    cyclic.add(cyclic);
    await expectLater(
      engine.eval('value', globals: {'value': cyclic}),
      throwsA(isA<JsValueConversionException>()),
    );
  });

  // 公开状态观测应反映 eval 占用 runtime 的过程。
  test('runtime state is running during evaluation', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final evalFuture = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 200) {}
        return "done";
      })();
    ''');

    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(engine.state, JsRuntimeState.running);
    expect(await evalFuture, 'done');
    expect(engine.state, JsRuntimeState.ready);
  });

  // stop 期间公开状态应进入 stopping，恢复后回到 ready。
  test('runtime state is stopping while restart is in progress', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final stopFuture = engine.restart();
    expect(engine.state, JsRuntimeState.restarting);

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stopFuture.timeout(const Duration(seconds: 2));
    expect(engine.state, JsRuntimeState.ready);
  });

  // dispose 后公开状态应稳定为 closed。
  test('runtime state is closed after dispose', () async {
    final engine = await Quickjs.create();

    await engine.dispose();

    expect(engine.state, JsRuntimeState.closed);
  });

  // memory limit 应把超限分配映射成稳定的 OOM 错误，并保持 runtime 可继续使用。
  test('memory limit rejects oversized allocations', () async {
    final engine = await Quickjs.create(
      options: const JsOptions(memoryLimitBytes: 256 * 1024),
    );
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('new Array(1000000).fill("quickjs").join("")'),
      throwsA(isA<JsOutOfMemoryException>()),
    );
    expect(await engine.eval('1 + 1'), '2');
  });

  // stack limit 应把递归栈溢出映射成稳定错误，并保持 runtime 可继续使用。
  test('stack limit rejects deep recursion', () async {
    final engine = await Quickjs.create(
      options: const JsOptions(stackLimitBytes: 256 * 1024),
    );
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('function recurse() { return recurse() + 1; } recurse();'),
      throwsA(isA<JsStackOverflowException>()),
    );
    expect(await engine.eval('1 + 1'), '2');
  });

  // JS throw 必须映射成公开的 JsThrownException，而不是普通字符串结果。
  test('javascript throw is reported as JsThrownException', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('throw new Error("boom")'),
      throwsA(
        isA<JsThrownException>().having(
          (error) => error.message,
          'message',
          contains('boom'),
        ),
      ),
    );
  });

  test('javascript Error exposes structured exception fields', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('throw new TypeError("structured boom")'),
      throwsA(
        isA<JsThrownException>()
            .having(
              (error) => error.message,
              'message',
              contains('structured boom'),
            )
            .having((error) => error.name, 'name', 'TypeError')
            .having((error) => error.stack, 'stack', isNot(isEmpty)),
      ),
    );
  });

  test(
    'non Error JavaScript throw still reports a useful JsThrownException',
    () async {
      final engine = await Quickjs.create();
      addTearDown(engine.dispose);

      await expectLater(
        engine.eval('throw "plain boom"'),
        throwsA(
          isA<JsThrownException>()
              .having(
                (error) => error.message,
                'message',
                contains('plain boom'),
              )
              .having((error) => error.name, 'name', anyOf(isNull, isNotEmpty)),
        ),
      );
    },
  );

  // 并发提交的 eval 必须按 FIFO 顺序进入同一个 runtime。
  test('concurrent evaluations are queued in order', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    final results = await Future.wait([
      engine.eval('globalThis.x = (globalThis.x || "") + "a"; globalThis.x'),
      engine.eval('globalThis.x = (globalThis.x || "") + "b"; globalThis.x'),
      engine.eval('globalThis.x = (globalThis.x || "") + "c"; globalThis.x'),
    ]);
    expect(results, ['a', 'ab', 'abc']);
  });

  // 大量并发请求用于压测队列顺序和 request/Future 对应关系。
  test('one hundred concurrent evaluations are queued in order', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await _expectHundredQueuedEvals(engine);
  });

  // 连续批次用于避免队列 drain 后状态没有正确复位。
  test('one hundred concurrent evaluations can be repeated', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await _expectHundredQueuedEvals(engine);
    await _expectHundredQueuedEvals(engine);
  });

  // 长耗时 JS 不能阻塞 Dart isolate 的 timer。
  test('long evaluation does not block the Dart isolate', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    final stopwatch = Stopwatch()..start();
    final timer = Completer<int>();
    Timer(const Duration(milliseconds: 50), () {
      timer.complete(stopwatch.elapsedMilliseconds);
    });

    final evalFuture = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 300) {}
        return "done";
      })();
    ''');

    final timerElapsed = await timer.future.timeout(const Duration(seconds: 1));
    expect(timerElapsed, lessThan(250));
    expect(await evalFuture, 'done');
  });

  // 正在执行的无限循环应能被 timeout 中断。
  test('evaluation can time out', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('while (true) {}', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<JsTimeoutException>()),
    );
  });

  // timeout 后 backend 会恢复 runtime，同一个 Quickjs 实例仍可继续执行。
  test('quickjs instance can evaluate after timeout', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('while (true) {}', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<JsTimeoutException>()),
    );
    expect(await engine.eval('21 * 2'), '42');
  });

  // timeout 从入队开始计算，排队过久的任务不应该再进入 runtime。
  test('queued evaluation can time out before it starts', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 100) {}
        return "running";
      })();
    ''');
    final queued = engine.eval(
      'globalThis.queuedTimeout = true',
      timeout: const Duration(milliseconds: 10),
    );

    await expectLater(queued, throwsA(isA<JsTimeoutException>()));
    expect(await running, 'running');
    expect(await engine.eval('globalThis.queuedTimeout'), 'undefined');
  });

  // stop 应取消正在执行的 eval，并在后台重建可用 runtime。
  test('stop cancels running evaluation and recovers runtime', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    final stopFuture = Future<void>.delayed(
      const Duration(milliseconds: 50),
      engine.restart,
    );

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stopFuture;
    expect(await engine.eval('21 * 2'), '42');
  });

  // 多次 stop 应共用同一个停止流程，不能产生悬挂 Future。
  test('repeated stop calls during evaluation complete', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stops = Future.wait([
      engine.restart(),
      engine.restart(),
      engine.restart(),
    ]);

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stops.timeout(const Duration(seconds: 2));
    expect(await engine.eval('21 * 2'), '42');
  });

  // stop 还必须取消尚未开始的队列任务。
  test('stop cancels queued evaluations', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    final queued = engine.eval('globalThis.stoppedQueue = true');
    final stopFuture = Future<void>.delayed(
      const Duration(milliseconds: 50),
      engine.restart,
    );

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await expectLater(queued, throwsA(isA<JsCancelledException>()));
    await stopFuture;
    expect(await engine.eval('globalThis.stoppedQueue'), 'undefined');
  });

  // 两个 Quickjs 实例的 globalThis 不能互相污染。
  test('multiple runtimes keep globals isolated', () async {
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

  // 释放一个 runtime 不应影响另一个 runtime。
  test('disposing one runtime does not affect another', () async {
    final first = await Quickjs.create();
    final second = await Quickjs.create();
    addTearDown(second.dispose);

    expect(await first.eval('globalThis.disposedPeer = 1'), '1');
    expect(await second.eval('globalThis.alivePeer = 2'), '2');

    await first.dispose();

    await expectLater(
      first.eval('1 + 1'),
      throwsA(isA<JsRuntimeClosedException>()),
    );
    expect(await second.eval('globalThis.alivePeer'), '2');
    expect(await second.eval('40 + 2'), '42');
  });

  // dispose 可以在 eval 运行中调用，等待运行中任务正常收尾。
  test('dispose during evaluation completes without hanging', () async {
    final engine = await Quickjs.create();
    final evalFuture = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 100) {}
        return "done";
      })();
    ''');

    final disposeFuture = engine.dispose();

    expect(await evalFuture, 'done');
    await disposeFuture.timeout(const Duration(seconds: 1));
    expect(engine.eval('1 + 1'), throwsA(isA<JsRuntimeClosedException>()));
  });

  // 重复 dispose 应共用同一个关闭流程，不能重复释放 runtime 或悬挂。
  test('repeated dispose calls during evaluation complete', () async {
    final engine = await Quickjs.create();
    final evalFuture = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 100) {}
        return "done";
      })();
    ''');

    final disposeA = engine.dispose();
    final disposeB = engine.dispose();
    final disposeC = engine.dispose();

    expect(await evalFuture, 'done');
    await Future.wait([
      disposeA,
      disposeB,
      disposeC,
    ]).timeout(const Duration(seconds: 1));
    expect(engine.eval('1 + 1'), throwsA(isA<JsRuntimeClosedException>()));
  });

  // dispose 会取消队列任务，并让它们以 closed error 完成。
  test('dispose cancels queued evaluations', () async {
    final engine = await Quickjs.create();
    final running = engine.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 100) {}
        return "running";
      })();
    ''');
    final queuedA = engine.eval('globalThis.disposedQueue = "a"');
    final queuedB = engine.eval('globalThis.disposedQueue = "b"');
    final queuedAFailure = expectLater(
      queuedA,
      throwsA(isA<JsRuntimeClosedException>()),
    );
    final queuedBFailure = expectLater(
      queuedB,
      throwsA(isA<JsRuntimeClosedException>()),
    );

    final disposeFuture = engine.dispose();

    expect(await running, 'running');
    await queuedAFailure;
    await queuedBFailure;
    await disposeFuture.timeout(const Duration(seconds: 1));
    expect(
      engine.eval('globalThis.disposedQueue'),
      throwsA(isA<JsRuntimeClosedException>()),
    );
  });

  // 已关闭实例必须拒绝新 eval。
  test('disposed quickjs instance rejects evaluation', () async {
    final engine = await Quickjs.create();
    await engine.dispose();
    expect(engine.eval('1 + 1'), throwsA(isA<JsRuntimeClosedException>()));
  });

  // closed 状态下 stop 必须立即失败，不能重新打开 runtime。
  test('disposed quickjs instance rejects stop', () async {
    final engine = await Quickjs.create();
    await engine.dispose();
    await expectLater(
      engine.restart(),
      throwsA(isA<JsRuntimeClosedException>()),
    );
  });

  // stop 进行中提交的新 eval 会等待 runtime 恢复后执行，不能永久 pending。
  test('evaluation queued during stop runs after runtime recovery', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stopFuture = engine.restart();
    final queuedDuringStop = engine.eval('21 * 2');

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stopFuture.timeout(const Duration(seconds: 2));
    expect(await queuedDuringStop.timeout(const Duration(seconds: 2)), '42');
  });

  // worker crash 后 pending eval 必须完成为 crash error，不能永久 pending。
  test('native worker crash completes pending request with error', () async {
    final runtime = await NativeQuickjsWorkerRuntime.create();
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.debugCrashForTest().timeout(const Duration(seconds: 2)),
      throwsA(isA<JsRuntimeCrashException>()),
    );
  });

  test('native worker contexts isolate global objects', () async {
    final runtime = await NativeQuickjsWorkerRuntime.create();
    addTearDown(runtime.dispose);

    final first = await runtime.createContext();
    final second = await runtime.createContext();
    addTearDown(() => runtime.disposeContext(first));
    addTearDown(() => runtime.disposeContext(second));

    expect(
      await runtime.evaluateContext(first, 'globalThis.value = 41; value'),
      '41',
    );
    expect(await runtime.evaluateContext(second, 'typeof value'), 'undefined');
    expect(
      await runtime.evaluateContext(second, 'globalThis.value = 7; value'),
      '7',
    );
    expect(await runtime.evaluateContext(first, 'value + 1'), '42');
  });

  test('native worker contexts isolate module source tables', () async {
    final runtime = await NativeQuickjsWorkerRuntime.create();
    addTearDown(runtime.dispose);

    final first = await runtime.createContext();
    final second = await runtime.createContext();
    addTearDown(() => runtime.disposeContext(first));
    addTearDown(() => runtime.disposeContext(second));

    const entry =
        "import { value } from './shared.mjs'; globalThis.moduleValue = value";
    expect(
      await runtime.evaluateModuleContext(
        first,
        entry,
        name: 'first.mjs',
        modules: const {'shared.mjs': 'export const value = 41'},
      ),
      'undefined',
    );
    expect(
      await runtime.evaluateModuleContext(
        second,
        entry,
        name: 'second.mjs',
        modules: const {'shared.mjs': 'export const value = 7'},
      ),
      'undefined',
    );
    expect(await runtime.evaluateContext(first, 'moduleValue'), '41');
    expect(await runtime.evaluateContext(second, 'moduleValue'), '7');
  });

  test('public runtime creates isolated contexts', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final first = await runtime.createContext();
    final second = await runtime.createContext();

    expect(await first.eval('globalThis.value = 11; value'), '11');
    expect(await second.eval('typeof value'), 'undefined');
    await first.dispose();
    expect(() => first.eval('value'), throwsA(isA<JsRuntimeClosedException>()));
    expect(await second.eval('6 * 7'), '42');
  });

  test('public contexts keep host callbacks isolated', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final first = await runtime.createContext();
    final second = await runtime.createContext();

    await first.injectFunction('hostValue', (args) => (args.single as int) + 1);
    await second.injectFunction(
      'hostValue',
      (args) => (args.single as int) * 2,
    );
    await first.eval('hostValue(20).then(value => globalThis.result = value)');
    await second.eval('hostValue(20).then(value => globalThis.result = value)');

    await _waitForContextValue(first, 'result', '21');
    await _waitForContextValue(second, 'result', '40');
  });

  test(
    'late context callback response does not close shared runtime',
    () async {
      final runtime = await JsRuntime.create();
      addTearDown(runtime.dispose);
      final disposed = await runtime.createContext();
      final sibling = await runtime.createContext();
      final started = Completer<void>();

      await disposed.injectFunction('slowHost', (_) async {
        started.complete();
        await Future<void>.delayed(const Duration(milliseconds: 20));
        return 1;
      });
      await disposed.eval('slowHost()');
      await started.future;
      await disposed.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 30));

      expect(await sibling.eval('40 + 2'), '42');
    },
  );

  test('context async evaluation pumps isolated timers', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final first = await runtime.createContext();
    final second = await runtime.createContext();

    expect(
      await first.run(
        'new Promise(resolve => setTimeout(() => resolve(21), 5))',
      ),
      '21',
    );
    expect(await second.eval('typeof result'), 'undefined');
    expect(
      await second.run(
        'new Promise(resolve => setTimeout(() => resolve(40), 5))',
      ),
      '40',
    );
  });

  test('disposing a context cancels only its timers', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final disposed = await runtime.createContext();
    final sibling = await runtime.createContext();

    await disposed.eval('setInterval(() => {}, 1)');
    await disposed.dispose();
    expect(
      await sibling.run(
        'new Promise(resolve => setTimeout(() => resolve(42), 5))',
      ),
      '42',
    );
  });

  test('context callback exposes Dart Stream to its JS context', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final context = await runtime.createContext();

    await context.injectFunction(
      'numbers',
      (_) => Stream<Object?>.fromIterable(<Object?>[1, 2, 3]),
    );
    expect(
      await context.run('''
(async () => {
  const values = [];
  for await (const value of await numbers()) values.push(value);
  return values.join(',');
})()
'''),
      '1,2,3',
    );
  });

  test('context injects Dart Stream as a JS async iterable', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final context = await runtime.createContext();

    await context.injectStream(
      'numbers',
      Stream<int>.fromIterable(<int>[1, 2, 3]),
    );
    expect(
      await context.run('''
const values = [];
for await (const value of numbers) values.push(value);
return values.join(',');
'''),
      '1,2,3',
    );
  });

  test('context JS sink emits to its Dart stream', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final context = await runtime.createContext();
    final values = <Object?>[];
    final done = Completer<void>();
    final stream = await context.bindStream('progress');
    final subscription = stream.listen(values.add, onDone: done.complete);
    addTearDown(subscription.cancel);

    await context.run('''
(async () => {
  await progress.emit(10);
  await progress.emit(20);
  await progress.close();
})()
''');
    await done.future.timeout(const Duration(seconds: 1));
    expect(values, <Object?>[10, 20]);
  });

  test(
    'contexts install and isolate plugins without rebuilding runtime',
    () async {
      final runtime = await JsRuntime.create();
      addTearDown(runtime.dispose);
      final firstPlugin = JsPlugin.singleFile(
        id: 'counter',
        version: '1.0.0',
        source: 'export function add(value) { return value + 1; }',
        exports: const <String>['add'],
      );
      final secondPlugin = JsPlugin.singleFile(
        id: 'counter',
        version: '2.0.0',
        source: 'export function add(value) { return value + 10; }',
        exports: const <String>['add'],
      );
      final first = await runtime.createContext(
        plugins: <JsPlugin>[firstPlugin],
      );
      final second = await runtime.createContext(
        plugins: <JsPlugin>[secondPlugin],
      );

      await first.validatePlugin(firstPlugin);
      await second.validatePlugin(secondPlugin);
      expect(await first.callPlugin(firstPlugin, 'add', <Object?>[5]), 6);
      expect(await second.callPlugin(secondPlugin, 'add', <Object?>[5]), 15);
    },
  );

  test('context loads a plugin in place and preserves globals', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final context = await runtime.createContext();
    await context.eval('globalThis.beforeMount = 41');
    final plugin = JsPlugin.singleFile(
      id: 'dynamic',
      version: '1.0.0',
      source: 'export function read() { return globalThis.beforeMount + 1; }',
      exports: const <String>['read'],
    );

    await context.loadPlugin(plugin);

    expect(await context.callPlugin(plugin, 'read', const <Object?>[]), 42);
    expect(await context.eval('beforeMount'), '41');
  });

  test('failed batched context initialization releases the context', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.createContext(
        scripts: const <JsScript>[
          JsScript.js(
            name: 'broken-context-bootstrap.js',
            source: 'throw new Error("bootstrap failed")',
          ),
        ],
      ),
      throwsA(isA<JsThrownException>()),
    );
    expect(runtime.activeContextCount, 0);

    final recovered = await runtime.createContext();
    expect(runtime.activeContextCount, 1);
    expect(await recovered.eval('1 + 1'), '2');
    await recovered.dispose();
    expect(runtime.activeContextCount, 0);
  });

  // crash 后 runtime 进入 closed 状态，后续请求必须立即失败。
  test('native worker crash closes runtime for later evaluations', () async {
    final runtime = await NativeQuickjsWorkerRuntime.create();
    addTearDown(runtime.dispose);

    await expectLater(
      runtime.debugCrashForTest(),
      throwsA(isA<JsRuntimeCrashException>()),
    );

    await expectLater(
      runtime.evaluate('1 + 1'),
      throwsA(isA<JsRuntimeClosedException>()),
    );
  });
}

Future<void> _expectHundredQueuedEvals(Quickjs engine) async {
  await engine.eval('globalThis.queue = ""');

  final results = await Future.wait([
    for (var i = 0; i < 100; i++)
      engine.eval(
        'globalThis.queue = (globalThis.queue || "") + "$i,"; globalThis.queue',
      ),
  ]);

  final expected = <String>[];
  var value = '';
  for (var i = 0; i < 100; i++) {
    value += '$i,';
    expected.add(value);
  }
  expect(results, expected);
}

Future<void> _waitForContextValue(
  JsContext context,
  String expression,
  String expected,
) async {
  for (var attempt = 0; attempt < 50; attempt++) {
    final value = await context.eval(expression);
    if (value == expected) return;
    await Future<void>.delayed(const Duration(milliseconds: 2));
  }
  expect(await context.eval(expression), expected);
}
