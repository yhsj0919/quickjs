import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'default runtime calls JS and synchronous Dart methods immediately',
    () async {
      final engine = await JsEngine.create(
        methods: [
          JsHostMethod.global(
            name: 'doubleValue',
            callback: (args, _) => (args[0] as num) * 2,
          ),
        ],
      );
      addTearDown(engine.dispose);
      expect(engine.supportsSync, isTrue);
      await engine.injectFunction(
        'add',
        (args) => (args[0] as num) + (args[1] as num),
      );
      expect(engine.evalSync('doubleValue(add(2, 3))'), 10);
      engine.evalRawSync(
        'globalThis.builder = index => ({key: "row-" + index, value: index})',
      );
      expect(engine.callSync('builder', [7]), {'key': 'row-7', 'value': 7});
      expect(
        () => engine.evalSync('Promise.resolve(1)'),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(
        () => engine.evalSync('throw new Error("sync error")'),
        throwsA(isA<JsThrownException>()),
      );
    },
  );

  test(
    'Future wait yields and resumes with the original closure and context',
    () async {
      final runtime = await JsRuntime.create();
      addTearDown(runtime.dispose);
      final result = Completer<Object?>();
      final entered = Completer<void>();
      final context = await runtime.createContext(
        methods: [
          JsHostMethod.global(
            name: 'request',
            callback: (args, _) {
              entered.complete();
              return result.future;
            },
          ),
        ],
      );
      context.evalRawSync(
        'globalThis.state = {count: 4}; globalThis.original = state',
      );
      final pending = context.run(
        'const stateRef = state; const value = await request(); return [stateRef === state, original === state, state.count + value];',
      );
      await entered.future;
      var eventRan = false;
      await Future<void>.delayed(Duration.zero, () {
        eventRan = true;
      });
      expect(eventRan, isTrue);
      expect(context.evalSync('state.count'), 4);
      context.evalRawSync('state.count = 5');
      result.complete(8);
      expect(await pending, [true, true, 13]);
    },
  );

  test('multiple local runtimes keep callback routing independent', () async {
    final first = await JsEngine.create();
    final second = await JsEngine.create();
    addTearDown(first.dispose);
    addTearDown(second.dispose);
    await first.injectFunction('value', (_) => 11);
    await second.injectFunction('value', (_) => 22);
    expect(first.evalSync('value()'), 11);
    expect(second.evalSync('value()'), 22);
    await second.dispose();
    expect(first.evalSync('value()'), 11);
  });

  test(
    'function handles and Dart objects/classes preserve synchronous behavior',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      final builder = await engine.bindFunction(
        '(() => { let count = 0; return index => ({index, count: ++count}); })()',
      );
      expect(builder.callSync([3]), {'index': 3, 'count': 1});
      expect(builder.callSync([9]), {'index': 9, 'count': 2});
      final target = <String, int>{'value': 1};
      final members = JsMembers<Map<String, int>>(
        accessors: [
          JsAccessor(
            'value',
            get: (object) => object['value'],
            set: (object, value) {
              object['value'] = value as int;
            },
          ),
        ],
        methods: [
          JsMethod(
            'add',
            (object, args) => object['value']! + (args[0] as int),
          ),
        ],
      );
      await engine.injectObject(
        'object',
        JsObject(target: target, members: members),
      );
      expect(engine.evalSync('object.value = 5; object.add(2)'), 7);
      await engine.injectClass(
        'Counter',
        JsClass(
          create: (args) => <String, int>{'value': args[0] as int},
          members: members,
        ),
      );
      expect(
        engine.evalSync(
          'globalThis.counter = new Counter(10); counter.value = 12; counter.add(3)',
        ),
        15,
      );
      await builder.dispose();
      expect(
        () => builder.callSync([1]),
        throwsA(isA<JsRuntimeClosedException>()),
      );
    },
  );

  test(
    'sync timeout and async compute timeout interrupt native execution',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      expect(
        () => engine.evalSync(
          'while (true) {}',
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<JsTimeoutException>()),
      );
      await expectLater(
        engine.run(
          'while (true) {}',
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<JsTimeoutException>()),
      );
      await engine.injectFunction('request', (_) => Future<Object?>.value(1));
      await expectLater(
        engine.run(
          'await request(); while (true) {}',
          timeout: const Duration(milliseconds: 30),
        ),
        throwsA(isA<JsTimeoutException>()),
      );
    },
  );

  test(
    'host callback reentry cannot enter the runtime through a sibling',
    () async {
      final runtime = await JsRuntime.create();
      addTearDown(runtime.dispose);
      final sibling = await runtime.createContext();
      final first = await runtime.createContext();
      await first.injectFunction('reenter', (_) => sibling.evalSync('1'));
      expect(
        () => first.evalSync('reenter()'),
        throwsA(
          isA<JsThrownException>().having(
            (error) => error.message,
            'message',
            contains('Reentrant'),
          ),
        ),
      );
      expect(sibling.evalSync('2'), 2);
    },
  );

  test(
    'explicit worker keeps asynchronous calls and rejects sync calls',
    () async {
      final runtime = await JsRuntime.create(
        options: const JsOptions(execution: JsExecution.workerIsolate),
      );
      addTearDown(runtime.dispose);
      final context = await runtime.createContext();
      expect(context.supportsSync, isFalse);
      expect(await context.eval('6 * 7'), 42);
      expect(() => context.evalSync('1'), throwsUnsupportedError);
    },
  );

  test('disposing an awaiting context ignores late host results', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final entered = Completer<void>();
    final result = Completer<Object?>();
    final first = await runtime.createContext(
      methods: [
        JsHostMethod.global(
          name: 'request',
          callback: (args, _) {
            entered.complete();
            return result.future;
          },
        ),
      ],
    );
    final sibling = await runtime.createContext();
    final pending = first.run('return await request();');
    final rejected = expectLater(pending, throwsA(isA<JsCancelledException>()));
    await entered.future;
    await first.dispose();
    result.complete(9);
    await rejected;
    expect(sibling.evalSync('40 + 2'), 42);
  });
}
