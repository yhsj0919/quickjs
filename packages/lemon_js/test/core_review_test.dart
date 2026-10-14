import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js_context.dart';
import 'package:lemon_js/src/native/native_runtime.dart';
import 'package:lemon_js/src/runtime/runtime_base.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  test(
    'disposing from an immediate callback keeps the engine closed',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      Future<void>? disposal;
      await engine.injectFunction('disposeNow', (_) {
        disposal = engine.dispose();
        return null;
      });
      await engine
          .evalRaw('disposeNow(); 1;')
          .then<void>((_) {}, onError: (Object _) {});
      await disposal;
      expect(engine.state, JsRuntimeState.closed);
      await expectLater(
        engine.eval('1'),
        throwsA(isA<JsRuntimeClosedException>()),
      );
    },
  );
  test('synchronous calls cannot enter an engine during restart', () async {
    final engine = await JsEngine.create();
    addTearDown(engine.dispose);
    final restarted = engine.restart();
    expect(() => engine.evalSync('1'), throwsA(isA<JsCancelledException>()));
    await restarted;
    expect(engine.evalSync('42'), 42);
  });
  test('zero sync raw timeout does not execute source', () async {
    final engine = await JsEngine.create();
    addTearDown(engine.dispose);
    engine.evalRawSync('globalThis.count=0;');
    expect(
      () => engine.evalRawSync('++count', timeout: Duration.zero),
      throwsA(isA<JsTimeoutException>()),
    );
    expect(engine.evalSync('count'), 0);
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final context = await runtime.createContext();
    context.evalRawSync('globalThis.count=0;');
    expect(
      () => context.evalRawSync('++count', timeout: Duration.zero),
      throwsA(isA<JsTimeoutException>()),
    );
    expect(context.evalSync('count'), 0);
  });
  for (final execution in JsExecution.values) {
    test('stop and dispose share one teardown: $execution', () async {
      final JsJsRuntimeBase runtime = execution == JsExecution.currentIsolate
          ? await NativeJsLocalRuntime.create()
          : await NativeJsWorkerRuntime.create();
      addTearDown(runtime.dispose);
      expect(await runtime.evaluateAsync('Promise.resolve(42)'), '42');
      final stopped = runtime.stop();
      final disposed = runtime.dispose();
      await Future.wait([stopped, disposed]);
      await runtime.stop();
      await runtime.dispose();
    });
    test(
      'runtime disposal drains concurrent contexts once: $execution',
      () async {
        final runtime = await JsRuntime.create(
          options: JsOptions(execution: execution),
        );
        addTearDown(runtime.dispose);
        final first = await runtime.createContext();
        final second = await runtime.createContext();
        final firstEntered = Completer<void>();
        final secondEntered = Completer<void>();
        final result = Completer<Object?>();
        await first.injectFunction('wait', (_) {
          firstEntered.complete();
          return result.future;
        });
        await second.injectFunction('wait', (_) {
          secondEntered.complete();
          return result.future;
        });
        final firstRejected = expectLater(
          first.run('return await wait();'),
          throwsA(isA<JsCancelledException>()),
        );
        final secondRejected = expectLater(
          second.run('return await wait();'),
          throwsA(isA<JsCancelledException>()),
        );
        await Future.wait([firstEntered.future, secondEntered.future]);
        final disposed = runtime.dispose();
        await runtime.dispose();
        await disposed;
        result.complete(42);
        await Future.wait([firstRejected, secondRejected]);
        expect(runtime.activeContextCount, 0);
      },
    );
    for (final child in [false, true]) {
      test(
        'async timeout releases execution slot: $execution child=$child',
        () async {
          final runtime = child
              ? await JsRuntime.create(options: JsOptions(execution: execution))
              : null;
          final engine = child
              ? null
              : await JsEngine.create(options: JsOptions(execution: execution));
          final context = await runtime?.createContext();
          addTearDown(() async {
            await engine?.dispose();
            await runtime?.dispose();
          });
          const setup =
              'globalThis.never=()=>new Promise(()=>{});globalThis.answer=()=>42;';
          if (child) {
            await context!.evalRaw(setup);
          } else {
            await engine!.evalRaw(setup);
          }
          await expectLater(
            child
                ? context!.call(
                    'never',
                    [],
                    timeout: const Duration(milliseconds: 20),
                  )
                : engine!.call(
                    'never',
                    [],
                    timeout: const Duration(milliseconds: 20),
                  ),
            throwsA(isA<JsTimeoutException>()),
          );
          expect(
            await (child
                ? context!.call('answer', [])
                : engine!.call('answer', [])),
            42,
          );
          await expectLater(
            child
                ? context!.run(
                    'return new Promise(()=>{});',
                    timeout: const Duration(milliseconds: 20),
                  )
                : engine!.run(
                    'return new Promise(()=>{});',
                    timeout: const Duration(milliseconds: 20),
                  ),
            throwsA(isA<JsTimeoutException>()),
          );
          expect(
            await (child
                ? context!.run('return 43;')
                : engine!.run('return 43;')),
            43,
          );
        },
      );
    }
    test(
      'disposed context does not subscribe to late callback stream: $execution',
      () async {
        final runtime = await JsRuntime.create(
          options: JsOptions(execution: execution),
        );
        addTearDown(runtime.dispose);
        final context = await runtime.createContext();
        final sibling = await runtime.createContext();
        final entered = Completer<void>();
        final result = Completer<Object?>();
        var subscriptions = 0;
        final stream = StreamController<Object?>(
          onListen: () {
            subscriptions++;
          },
        );
        addTearDown(() {
          unawaited(stream.close());
        });
        await context.injectFunction('lateStream', (_) {
          entered.complete();
          return result.future;
        });
        final pending = context.run('return await lateStream();');
        final rejected = expectLater(
          pending,
          throwsA(isA<JsCancelledException>()),
        );
        await entered.future;
        await context.dispose();
        result.complete(stream.stream);
        await rejected;
        await Future<void>.delayed(const Duration(milliseconds: 20));
        expect(subscriptions, 0);
        expect(await sibling.eval('6*7'), 42);
      },
    );
  }
}
