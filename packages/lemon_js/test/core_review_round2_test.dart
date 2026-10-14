import 'dart:async';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js_context.dart';
import 'package:lemon_js/src/native/native_runtime.dart';
import 'package:lemon_js/src/runtime/runtime_base.dart';

class _DelayedScriptBundle extends CachingAssetBundle {
  final entered = Completer<void>();
  final source = Completer<String>();

  @override
  Future<String> loadString(String key, {bool cache = true}) {
    entered.complete();
    return source.future;
  }

  @override
  Future<ByteData> load(String key) =>
      throw UnsupportedError('loadString only');
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  for (final execution in JsExecution.values) {
    test('run does not shadow user global names: $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      await engine.evalRaw('globalThis.value=3;globalThis.convert=4;');
      expect(
        await engine.run('await Promise.resolve(); return value+convert;'),
        7,
      );
      expect(
        await engine.run('return value+convert;', tempGlobals: {'value': 5}),
        9,
      );
      expect(await engine.eval('value'), 3);
    });
    test('function replacement preserves pending calls: $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      final entered = Completer<void>();
      final result = Completer<Object?>();
      await engine.injectFunction('pendingHost', (_) {
        entered.complete();
        return result.future;
      });
      final pending = engine.run('return await globalThis.pendingHost();');
      await entered.future;
      await engine.injectFunction('pendingHost', (_) => 2);
      result.complete(1);
      expect(await pending.timeout(const Duration(milliseconds: 500)), 1);
      expect(await engine.run('return await globalThis.pendingHost();'), 2);
    });
    test(
      'runtime closes before child attachment completes: $execution',
      () async {
        final runtime = await JsRuntime.create(
          options: JsOptions(execution: execution),
        );
        final created = runtime.createContext();
        final rejected = expectLater(
          created.timeout(const Duration(milliseconds: 500)),
          throwsA(isA<JsRuntimeClosedException>()),
        );
        await runtime.dispose();
        await rejected;
        expect(runtime.activeContextCount, 0);
      },
    );
    test('same-runtime replaced bindings retain ownership: $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      final oldObject = await engine.injectObject(
        'value',
        JsObject(
          target: 1,
          members: JsMembers(
            accessors: [JsAccessor<int>('number', get: (n) => n)],
          ),
        ),
      );
      final oldClass = await engine.injectClass(
        'Counter',
        JsClass(
          create: (_) => 1,
          members: JsMembers(
            accessors: [JsAccessor<int>('number', get: (n) => n)],
          ),
        ),
      );
      await engine.run(
        'globalThis.savedValue=globalThis.value;globalThis.savedCounter=new Counter();return await savedCounter.number;',
      );
      await engine.injectObject(
        'value',
        JsObject(
          target: 2,
          members: JsMembers(
            accessors: [JsAccessor<int>('number', get: (n) => n)],
          ),
        ),
      );
      await engine.injectClass(
        'Counter',
        JsClass(
          create: (_) => 2,
          members: JsMembers(
            accessors: [JsAccessor<int>('number', get: (n) => n)],
          ),
        ),
      );
      await oldObject.dispose();
      await oldClass.dispose();
      expect(await engine.run('return await globalThis.value.number;'), 2);
      expect(await engine.run('return await (new Counter()).number;'), 2);
      await expectLater(
        engine.run('return await savedValue.number;'),
        throwsA(
          isA<JsThrownException>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
      await expectLater(
        engine.run('return await savedCounter.number;'),
        throwsA(
          isA<JsThrownException>().having(
            (e) => e.message,
            'message',
            contains('disposed'),
          ),
        ),
      );
    });
    test('runtime can close during child startup assets: $execution', () async {
      final runtime = await JsRuntime.create(
        options: JsOptions(execution: execution),
      );
      final bundle = _DelayedScriptBundle();
      final created = runtime.createContext(
        scripts: [
          JsScript.asset(
            name: 'startup.js',
            path: 'startup.js',
            bundle: bundle,
          ),
        ],
      );
      final rejected = expectLater(
        created,
        throwsA(isA<JsRuntimeClosedException>()),
      );
      await bundle.entered.future;
      Object? disposalError;
      try {
        await runtime.dispose();
      } catch (error) {
        disposalError = error;
      }
      bundle.source.complete('globalThis.ready=true;');
      await rejected;
      expect(disposalError, isNull);
      expect(runtime.activeContextCount, 0);
    });
    test('function handles cannot alias after restart: $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      final old = await engine.bindFunction('()=>1');
      await engine.restart();
      final current = await engine.bindFunction('()=>2');
      await expectLater(old.call([]), throwsA(isA<JsRuntimeClosedException>()));
      if (engine.supportsSync) {
        expect(
          () => old.callSync([]),
          throwsA(isA<JsRuntimeClosedException>()),
        );
      }
      expect(await current.call([]), 2);
    });
    test(
      'disposing old function does not remove current handle: $execution',
      () async {
        final engine = await JsEngine.create(
          options: JsOptions(execution: execution),
        );
        addTearDown(engine.dispose);
        final old = await engine.bindFunction('()=>1');
        await engine.restart();
        final current = await engine.bindFunction('()=>2');
        await old.dispose();
        expect(await current.call([]), 2);
      },
    );
    test(
      'disposing old object and class leaves new bindings: $execution',
      () async {
        final engine = await JsEngine.create(
          options: JsOptions(execution: execution),
        );
        addTearDown(engine.dispose);
        final oldObject = await engine.injectObject(
          'value',
          JsObject(
            target: Object(),
            members: JsMembers(values: [JsValue('number', 1)]),
          ),
        );
        final oldClass = await engine.injectClass(
          'Counter',
          JsClass(
            create: (_) => Object(),
            members: JsMembers(values: [JsValue('number', 1)]),
          ),
        );
        await engine.restart();
        await engine.injectObject(
          'value',
          JsObject(
            target: Object(),
            members: JsMembers(values: [JsValue('number', 2)]),
          ),
        );
        await engine.injectClass(
          'Counter',
          JsClass(
            create: (_) => Object(),
            members: JsMembers(values: [JsValue('number', 2)]),
          ),
        );
        await oldObject.dispose();
        await oldClass.dispose();
        expect(await engine.eval('value.number'), 2);
        expect(await engine.run('return (new Counter()).number;'), 2);
      },
    );
    test(
      'native child requests reject after runtime disposal: $execution',
      () async {
        final JsJsRuntimeBase runtime = execution == JsExecution.currentIsolate
            ? await NativeJsLocalRuntime.create()
            : await NativeJsWorkerRuntime.create();
        await runtime.dispose();
        await expectLater(
          (runtime as JsMultiContextRuntimeBase).createContext().timeout(
            const Duration(milliseconds: 200),
          ),
          throwsA(isA<JsRuntimeClosedException>()),
        );
      },
    );
  }
}
