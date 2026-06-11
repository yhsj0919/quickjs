import 'dart:async';
import 'dart:collection';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs/src/quickjs_backend.dart';
import 'package:quickjs/src/quickjs_runtime_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'state transitions ready -> running -> ready for successful eval',
    () async {
      final runtime = _FakeRuntime();
      final engine = Quickjs.test(_FakeBackend(), runtime);

      expect(engine.state, QuickjsRuntimeState.ready);

      final evalFuture = engine.eval('hold');

      expect(engine.state, QuickjsRuntimeState.running);
      expect(runtime.evaluations, ['hold']);

      runtime.completeCurrent('done');

      expect(await evalFuture, 'done');
      await _flushMicrotasks();
      expect(engine.state, QuickjsRuntimeState.ready);
    },
  );

  test(
    'state stays running while queued eval waits for current eval',
    () async {
      final runtime = _FakeRuntime();
      final engine = Quickjs.test(_FakeBackend(), runtime);

      final running = engine.eval('hold');
      final queued = engine.eval('queued');

      expect(engine.state, QuickjsRuntimeState.running);
      expect(runtime.evaluations, ['hold']);

      runtime.completeCurrent('done');

      expect(await running, 'done');
      expect(await queued, 'queued');
      await _flushMicrotasks();
      expect(runtime.evaluations, ['hold', 'queued']);
      expect(engine.state, QuickjsRuntimeState.ready);
    },
  );

  test('stop moves running runtime through stopping back to ready', () async {
    final runtime = _FakeRuntime();
    final replacement = _FakeRuntime();
    final backend = _FakeBackend([replacement]);
    final engine = Quickjs.test(backend, runtime);

    final running = engine.eval('hold');
    final queued = engine.eval('queued');

    final stopFuture = engine.stop();

    expect(engine.state, QuickjsRuntimeState.stopping);
    await expectLater(queued, throwsA(isA<JsCancelledException>()));
    await expectLater(running, throwsA(isA<JsCancelledException>()));
    await stopFuture;
    await _flushMicrotasks();

    expect(backend.createCount, 1);
    expect(engine.state, QuickjsRuntimeState.ready);
    expect(await engine.eval('afterStop'), 'afterStop');
    expect(replacement.evaluations, ['afterStop']);
  });

  test(
    'eval queued during stopping runs after replacement runtime is ready',
    () async {
      final stopCompleter = Completer<void>();
      final runtime = _FakeRuntime(stopFuture: stopCompleter.future);
      final replacement = _FakeRuntime();
      final backend = _FakeBackend([replacement]);
      final engine = Quickjs.test(backend, runtime);

      final running = engine.eval('hold');
      final stopFuture = engine.stop();

      expect(engine.state, QuickjsRuntimeState.stopping);

      final queuedDuringStop = engine.eval('afterStop');
      expect(replacement.evaluations, isEmpty);

      stopCompleter.complete();

      await expectLater(running, throwsA(isA<JsCancelledException>()));
      await stopFuture;
      expect(await queuedDuringStop, 'afterStop');
      await _flushMicrotasks();

      expect(engine.state, QuickjsRuntimeState.ready);
      expect(replacement.evaluations, ['afterStop']);
    },
  );

  test(
    'dispose moves runtime to closed immediately and keeps it closed',
    () async {
      final runtime = _FakeRuntime();
      final engine = Quickjs.test(_FakeBackend(), runtime);

      final running = engine.eval('hold');
      final disposeFuture = engine.dispose();

      expect(engine.state, QuickjsRuntimeState.closed);
      expect(
        engine.eval('afterDispose'),
        throwsA(isA<JsRuntimeClosedException>()),
      );

      runtime.completeCurrent('done');

      expect(await running, 'done');
      await disposeFuture;
      await _flushMicrotasks();

      expect(runtime.disposed, isTrue);
      expect(engine.state, QuickjsRuntimeState.closed);
    },
  );

  test('backend closed error moves wrapper to closed terminal state', () async {
    final runtime = _FakeRuntime();
    final engine = Quickjs.test(_FakeBackend(), runtime);

    await expectLater(
      engine.eval('closed'),
      throwsA(isA<JsRuntimeClosedException>()),
    );
    await _flushMicrotasks();

    expect(engine.state, QuickjsRuntimeState.closed);
    expect(
      engine.eval('afterClosed'),
      throwsA(isA<JsRuntimeClosedException>()),
    );
    await expectLater(engine.stop(), throwsA(isA<JsRuntimeClosedException>()));
  });

  test('backend crash moves wrapper to failed terminal state', () async {
    final runtime = _FakeRuntime();
    final engine = Quickjs.test(_FakeBackend(), runtime);

    await expectLater(
      engine.eval('crash'),
      throwsA(isA<JsRuntimeCrashException>()),
    );
    await _flushMicrotasks();

    expect(engine.state, QuickjsRuntimeState.failed);
    expect(engine.eval('afterCrash'), throwsA(isA<JsRuntimeCrashException>()));
    await expectLater(engine.stop(), throwsA(isA<JsRuntimeCrashException>()));
  });
}

Future<void> _flushMicrotasks() async {
  await Future<void>.delayed(Duration.zero);
}

final class _FakeBackend implements QuickjsBackend {
  _FakeBackend([Iterable<_FakeRuntime> runtimes = const []])
    : _runtimes = Queue<_FakeRuntime>.of(runtimes);

  final Queue<_FakeRuntime> _runtimes;
  int createCount = 0;

  @override
  String get quickjsVersion => 'test';

  @override
  Future<QuickjsJsRuntimeBase> createRuntime(
    QuickjsRuntimeOptions options,
  ) async {
    createCount += 1;
    if (_runtimes.isNotEmpty) {
      return _runtimes.removeFirst();
    }
    return _FakeRuntime();
  }
}

final class _FakeRuntime implements QuickjsJsRuntimeBase {
  _FakeRuntime({this.stopFuture});

  final Future<void>? stopFuture;
  final List<String> evaluations = <String>[];
  Completer<String>? _current;
  bool disposed = false;

  @override
  Future<String> evaluate(String code, {Duration? timeout}) {
    evaluations.add(code);
    return switch (code) {
      'hold' => _hold(),
      'closed' => Future<String>.error(JsRuntimeClosedException()),
      'crash' => Future<String>.error(JsRuntimeCrashException('worker crash')),
      _ => Future<String>.value(code),
    };
  }

  @override
  Future<String> evaluateAsync(String code, {Duration? timeout}) {
    return evaluate(code, timeout: timeout);
  }

  @override
  Future<void> bindCallback(
    int callbackId,
    String name,
    Future<Object?> Function(List<Object?> args) callback,
  ) async {}

  @override
  Future<Stream<Object?>> bindJsSink(String name) async {
    return const Stream<Object?>.empty();
  }

  @override
  Future<void> stop() {
    _current?.completeError(JsCancelledException());
    _current = null;
    return stopFuture ?? Future<void>.value();
  }

  @override
  Future<void> dispose() async {
    disposed = true;
  }

  void completeCurrent(String result) {
    final current = _current;
    if (current == null) {
      throw StateError('No eval is currently held');
    }
    current.complete(result);
    _current = null;
  }

  Future<String> _hold() {
    if (_current != null) {
      throw StateError('Fake runtime does not support concurrent hold calls');
    }
    final completer = Completer<String>();
    _current = completer;
    return completer.future;
  }
}
