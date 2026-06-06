import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('evaluates JavaScript', (tester) async {
    final engine = await Quickjs.create();
    expect(engine.quickjsVersion, isNotEmpty);
    expect(await engine.evaluate('1 + 2'), '3');
  });
}
