import 'dart:async';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js_context.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  for (final execution in JsExecution.values) {
    test('eval executor preserves script semantics in $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      await engine.evalRaw('globalThis.counter=0;globalThis.input=99;');
      expect(await engine.eval('++counter'), 1);
      expect(await engine.eval('++counter'), 2);
      expect(await engine.eval('var declared=7; declared'), 7);
      expect(await engine.eval('declared'), 7);
      expect(await engine.eval('let lexical=8; lexical'), 8);
      expect(await engine.eval('typeof lexical'), 'undefined');
      expect(
        await engine.eval('input+extra', tempGlobals: {'input': 3, 'extra': 4}),
        7,
      );
      expect(await engine.eval('[input,typeof extra]'), [99, 'undefined']);
      await expectLater(
        engine.eval(
          'throw Error("boom")',
          tempGlobals: {'input': 3, 'extra': 4},
        ),
        throwsA(isA<JsException>()),
      );
      expect(await engine.eval('[input,typeof extra]'), [99, 'undefined']);
      await expectLater(
        engine.eval(') syntax', tempGlobals: {'input': 3}),
        throwsA(isA<JsException>()),
      );
      expect(await engine.eval('input'), 99);
      await expectLater(
        engine.eval('throw "primitive"'),
        throwsA(
          isA<JsThrownException>().having(
            (e) => e.message,
            'message',
            'primitive',
          ),
        ),
      );
      await expectLater(
        engine.eval(
          'throw Object.freeze(new Error("frozen"))',
          name: 'scripts/frozen.js',
        ),
        throwsA(
          isA<JsThrownException>()
              .having((e) => e.message, 'message', 'frozen')
              .having((e) => e.fileName, 'source', 'scripts/frozen.js'),
        ),
      );
      await expectLater(
        engine.eval('throw Error("named")', name: 'scripts/executor.js'),
        throwsA(
          isA<JsThrownException>().having(
            (e) => e.fileName,
            'source',
            'scripts/executor.js',
          ),
        ),
      );
      expect(await engine.evalRaw('input+1', tempGlobals: {'input': 3}), '4');
      expect(await engine.eval('input'), 99);
      expect(
        await engine.eval('new Uint8Array([1,2])'),
        Uint8List.fromList([1, 2]),
      );
      if (engine.supportsSync) {
        expect(engine.evalSync('++counter'), 3);
        expect(engine.evalRawSync('input+1', tempGlobals: {'input': 3}), '4');
        expect(engine.evalSync('input'), 99);
        expect(
          () => engine.evalSync(
            'throw Error("sync named")',
            name: 'scripts/sync.js',
          ),
          throwsA(
            isA<JsThrownException>().having(
              (e) => e.fileName,
              'source',
              'scripts/sync.js',
            ),
          ),
        );
        expect(
          () => engine.evalSync(
            'while(true){}',
            timeout: const Duration(milliseconds: 10),
          ),
          throwsA(isA<JsTimeoutException>()),
        );
        expect(engine.evalSync('counter'), 3);
      }
    });
  }

  test('direct global and handle calls do not use JavaScript eval', () async {
    final engine = await JsEngine.create();
    addTearDown(engine.dispose);
    final handle = await engine.bindFunction('(x)=>x+1');
    engine.evalRawSync(
      'globalThis.add=x=>x+2;globalThis.eval=()=>{throw Error("unexpected eval")};',
    );
    expect(engine.callSync('add', [3]), 5);
    expect(await engine.call('add', [3]), 5);
    expect(
      engine.callBatchSync('add', [
        [1],
        [2],
      ]),
      [3, 4],
    );
    expect(
      await engine.callBatch('add', [
        [1],
        [2],
      ]),
      [3, 4],
    );
    expect(handle.callSync([3]), 4);
    expect(await handle.run([3]), 4);
  });

  test(
    'direct awaiting calls cancel on disposal and ignore late host completion',
    () async {
      final entered = Completer<void>();
      final result = Completer<Object?>();
      final engine = await JsEngine.create(
        methods: [
          JsHostMethod.global(
            name: 'host',
            callback: (_, _) {
              entered.complete();
              return result.future;
            },
          ),
        ],
      );
      engine.evalRawSync('globalThis.wait=async()=>await host();');
      final pending = engine.call('wait', []);
      final rejected = expectLater(
        pending,
        throwsA(isA<JsCancelledException>()),
      );
      await entered.future;
      await engine.dispose();
      result.complete(9);
      await rejected;
    },
  );

  test(
    'direct calls keep codecs, receivers and global replacements live',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      engine.evalRawSync(
        'globalThis.echo=function(x){if(this!==globalThis)throw Error("receiver");return x};',
      );
      final value = {
        'text': '中文 " \\ \n',
        'bytes': Uint8List.fromList([0, 255]),
        'nested': [1, true, null],
      };
      expect(engine.callSync('echo', [value]), value);
      expect(await engine.call('echo', [value]), value);
      engine.evalRawSync('globalThis.echo=x=>x+1');
      expect(engine.callSync('echo', [4]), 5);
      engine.evalRawSync('globalThis.echo=x=>x+2');
      expect(await engine.call('echo', [4]), 6);
      engine.evalRawSync('globalThis["a.b"]=()=>9');
      expect(engine.callSync('a.b', []), 9);
      expect(await engine.callRaw('a.b', []), '9');
      expect(
        () => engine.callSync('missing', []),
        throwsA(isA<JsThrownException>()),
      );
    },
  );

  for (final execution in JsExecution.values) {
    test('batch preserves order and stops on rejection: $execution', () async {
      final engine = await JsEngine.create(
        options: JsOptions(execution: execution),
      );
      addTearDown(engine.dispose);
      await engine.evalRaw(
        'globalThis.seen=[];globalThis.step=async x=>{seen.push(x);if(x===3)throw Error("stop");return x*2};',
      );
      expect(
        await engine.callBatch('step', [
          [1],
          [2],
        ]),
        [2, 4],
      );
      await expectLater(
        engine.callBatch('step', [
          [3],
          [4],
        ]),
        throwsA(isA<JsThrownException>()),
      );
      expect(await engine.eval('seen'), [1, 2, 3]);
      expect(await engine.callBatch('step', []), isEmpty);
    });
  }

  test(
    'sync batch aborts on Promise and has a native execution deadline',
    () async {
      final engine = await JsEngine.create();
      addTearDown(engine.dispose);
      engine.evalRawSync(
        'globalThis.seen=[];globalThis.step=x=>{seen.push(x);return x===2?Promise.resolve(x):x};',
      );
      expect(
        () => engine.callBatchSync('step', [
          [1],
          [2],
          [3],
        ]),
        throwsA(isA<JsValueConversionException>()),
      );
      expect(engine.evalSync('seen'), [1, 2]);
      engine.evalRawSync('globalThis.spin=()=>{while(true){}}');
      expect(
        () => engine.callBatchSync('spin', [
          [],
        ], timeout: const Duration(milliseconds: 20)),
        throwsA(isA<JsTimeoutException>()),
      );
    },
  );

  test('async invocation preserves context while host Future waits', () async {
    final runtime = await JsRuntime.create();
    addTearDown(runtime.dispose);
    final entered = Completer<void>();
    final answer = Completer<Object?>();
    final first = await runtime.createContext(
      methods: [
        JsHostMethod.global(
          name: 'host',
          callback: (_, _) {
            entered.complete();
            return answer.future;
          },
        ),
      ],
    );
    final sibling = await runtime.createContext();
    first.evalRawSync('globalThis.wait=async x=>x+await host();');
    sibling.evalRawSync('globalThis.wait=x=>x*3');
    final pending = first.call('wait', [2]);
    await entered.future;
    expect(
      sibling.callBatchSync('wait', [
        [4],
        [5],
      ]),
      [12, 15],
    );
    answer.complete(8);
    expect(await pending, 10);
  });
}
