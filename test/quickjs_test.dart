import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('create and evaluate', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.quickjsVersion, isNotEmpty);
    expect(await engine.evaluate('1 + 2'), '3');
  });

  test('quickjs instance can be reused', () async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(await engine.evaluate('"a" + "b"'), 'ab');
    expect(await engine.evaluate('2 ** 10'), '1024');
  });

  test('disposed quickjs instance rejects evaluation', () async {
    final engine = await Quickjs.create();
    engine.dispose();
    expect(
      engine.evaluate('1 + 1'),
      throwsA(isA<StateError>()),
    );
  });
}
