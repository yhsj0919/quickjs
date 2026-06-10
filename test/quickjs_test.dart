import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs/src/native/quickjs_native_worker.dart';

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
    expect(engine.state, QuickjsRuntimeState.ready);
    expect(await engine.evaluate('"a" + "b"'), 'ab');
    expect(await engine.evaluate('2 ** 10'), '1024');
    expect(engine.state, QuickjsRuntimeState.ready);
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
    expect(engine.state, QuickjsRuntimeState.running);
    expect(await evalFuture, 'done');
    expect(engine.state, QuickjsRuntimeState.ready);
  });

  // stop 期间公开状态应进入 stopping，恢复后回到 ready。
  test('runtime state is stopping while stop is in progress', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));

    final stopFuture = engine.stop();
    expect(engine.state, QuickjsRuntimeState.stopping);

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stopFuture.timeout(const Duration(seconds: 2));
    expect(engine.state, QuickjsRuntimeState.ready);
  });

  // dispose 后公开状态应稳定为 closed。
  test('runtime state is closed after dispose', () async {
    final engine = await Quickjs.create();

    await engine.dispose();

    expect(engine.state, QuickjsRuntimeState.closed);
  });

  // memory limit 应把超限分配映射成稳定的 OOM 错误，并保持 runtime 可继续使用。
  test('memory limit rejects oversized allocations', () async {
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

  // stack limit 应把递归栈溢出映射成稳定错误，并保持 runtime 可继续使用。
  test('stack limit rejects deep recursion', () async {
    final engine = await Quickjs.create(
      options: const QuickjsRuntimeOptions(stackLimitBytes: 64 * 1024),
    );
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('function recurse() { return recurse() + 1; } recurse();'),
      throwsA(isA<JsStackOverflowException>()),
    );
    expect(await engine.eval('1 + 1'), '2');
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
    await expectLater(engine.stop(), throwsA(isA<JsRuntimeClosedException>()));
  });

  // stop 进行中提交的新 eval 会等待 runtime 恢复后执行，不能永久 pending。
  test('evaluation queued during stop runs after runtime recovery', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stopFuture = engine.stop();
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
