import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // 最小闭环：创建 runtime、执行 JS、读取版本。
  test('create and evaluate', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.quickjsVersion, '0.15.1');
    expect(await engine.eval('1 + 2'), '3');
  });

  // 同一个 Quickjs 实例应能重复执行，不需要每次重新创建 runtime。
  test('quickjs instance can be reused', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(await engine.evaluate('"a" + "b"'), 'ab');
    expect(await engine.evaluate('2 ** 10'), '1024');
  });

  // JS throw 必须映射成公开的 JsException，而不是普通字符串结果。
  test('javascript throw is reported as JsException', () async {
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
      engine.stop,
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
    final stops = Future.wait([engine.stop(), engine.stop(), engine.stop()]);

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
      engine.stop,
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
