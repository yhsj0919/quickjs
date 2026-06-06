import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('create and evaluate', () async {
    final engine = await Quickjs.create();
    expect(engine.quickjsVersion, isNotEmpty);
    expect(await engine.evaluate('1 + 2'), '3');
  });

  test('runtime can be reused', () async {
    final engine = await Quickjs.create();
    final runtime = await engine.createRuntime();
    addTearDown(runtime.dispose);
    expect(runtime.evaluate('"a" + "b"'), 'ab');
    expect(runtime.evaluate('2 ** 10'), '1024');
  });
}
