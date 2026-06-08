import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('create and evaluate', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.quickjsVersion, '0.15.1');
    expect(await engine.eval('1 + 2'), '3');
  });

  test('quickjs instance can be reused', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(await engine.evaluate('"a" + "b"'), 'ab');
    expect(await engine.evaluate('2 ** 10'), '1024');
  });

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

  test('one hundred concurrent evaluations are queued in order', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await _expectHundredQueuedEvals(engine);
  });

  test('one hundred concurrent evaluations can be repeated', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await _expectHundredQueuedEvals(engine);
    await _expectHundredQueuedEvals(engine);
  });

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

  test('evaluation can time out', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('while (true) {}', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<JsTimeoutException>()),
    );
  });

  test('quickjs instance can evaluate after timeout', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    await expectLater(
      engine.eval('while (true) {}', timeout: const Duration(milliseconds: 50)),
      throwsA(isA<JsTimeoutException>()),
    );
    expect(await engine.eval('21 * 2'), '42');
  });

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

  test('repeated stop calls during evaluation complete', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);

    final running = engine.eval('while (true) {}');
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final stops = Future.wait([
      engine.stop(),
      engine.stop(),
      engine.stop(),
    ]);

    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stops.timeout(const Duration(seconds: 2));
    expect(await engine.eval('21 * 2'), '42');
  });

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

  test('disposing one runtime does not affect another', () async {
    final first = await Quickjs.create();
    final second = await Quickjs.create();
    addTearDown(second.dispose);

    expect(await first.eval('globalThis.disposedPeer = 1'), '1');
    expect(await second.eval('globalThis.alivePeer = 2'), '2');

    await first.dispose();

    await expectLater(first.eval('1 + 1'), throwsA(isA<StateError>()));
    expect(await second.eval('globalThis.alivePeer'), '2');
    expect(await second.eval('40 + 2'), '42');
  });

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
    expect(engine.eval('1 + 1'), throwsA(isA<StateError>()));
  });

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
    final queuedAFailure = expectLater(queuedA, throwsA(isA<StateError>()));
    final queuedBFailure = expectLater(queuedB, throwsA(isA<StateError>()));

    final disposeFuture = engine.dispose();

    expect(await running, 'running');
    await queuedAFailure;
    await queuedBFailure;
    await disposeFuture.timeout(const Duration(seconds: 1));
    expect(engine.eval('globalThis.disposedQueue'), throwsA(isA<StateError>()));
  });

  test('disposed quickjs instance rejects evaluation', () async {
    final engine = await Quickjs.create();
    await engine.dispose();
    expect(engine.eval('1 + 1'), throwsA(isA<StateError>()));
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
