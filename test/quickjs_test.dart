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
