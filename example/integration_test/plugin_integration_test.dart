import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evaluates JavaScript', (tester) async {
    final engine = await Quickjs.create();
    addTearDown(engine.dispose);
    expect(engine.quickjsVersion, '0.15.1');
    expect(await engine.eval('1 + 2'), '3');
  });
}
