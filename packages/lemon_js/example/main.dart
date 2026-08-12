import 'package:lemon_js/lemon_js.dart';

/// Runs a minimal QuickJS evaluation and prints the converted Dart value.
Future<void> main() async {
  final runtime = await Quickjs.create();
  try {
    final result = await runtime.evaluateValue('''
      const values = [1, 2, 3];
      ({ total: values.reduce((sum, value) => sum + value, 0) });
    ''');
    // ignore: avoid_print
    print(result);
  } finally {
    await runtime.dispose();
  }
}
