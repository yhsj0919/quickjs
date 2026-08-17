import 'package:lemon_js/lemon_js.dart';

/// Runs a minimal QuickJS evaluation and prints the converted Dart value.
Future<void> main() async {
  final engine = await JsEngine.create();
  try {
    final result = await engine.eval('''
      const values = [1, 2, 3];
      ({ total: values.reduce((sum, value) => sum + value, 0) });
    ''');
    // ignore: avoid_print
    print(result);
  } finally {
    await engine.dispose();
  }
}
