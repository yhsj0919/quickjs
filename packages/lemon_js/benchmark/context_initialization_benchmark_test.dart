import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test(
    'compares batched and sequential context environment installation',
    () async {
      const iterations = 30;
      const scripts = <JsScript>[
        JsScript.js(name: 'init-0.js', source: 'globalThis.v0 = 0'),
        JsScript.js(name: 'init-1.js', source: 'globalThis.v1 = 1'),
        JsScript.js(name: 'init-2.js', source: 'globalThis.v2 = 2'),
        JsScript.js(name: 'init-3.js', source: 'globalThis.v3 = 3'),
        JsScript.js(name: 'init-4.js', source: 'globalThis.v4 = 4'),
        JsScript.js(name: 'init-5.js', source: 'globalThis.v5 = 5'),
        JsScript.js(name: 'init-6.js', source: 'globalThis.v6 = 6'),
        JsScript.js(name: 'init-7.js', source: 'globalThis.v7 = 7'),
      ];
      final runtime = await JsRuntime.create();
      addTearDown(runtime.dispose);

      final batched = await _measure(iterations, () async {
        final context = await runtime.createContext(scripts: scripts);
        await context.dispose();
      });
      final sequential = await _measure(iterations, () async {
        final context = await runtime.createContext();
        for (final script in scripts) {
          await context.eval(script.source!, name: script.name);
        }
        await context.dispose();
      });

      // ignore: avoid_print
      print('QuickJS Context initialization benchmark');
      // ignore: avoid_print
      print('iterations=$iterations scripts=${scripts.length}');
      // ignore: avoid_print
      print('dll=${Platform.environment['QUICKJS_DLL_PATH'] ?? 'auto'}');
      // ignore: avoid_print
      print(
        'batched median=${_ms(batched.median)}ms p95=${_ms(batched.p95)}ms',
      );
      // ignore: avoid_print
      print(
        'sequential median=${_ms(sequential.median)}ms '
        'p95=${_ms(sequential.p95)}ms',
      );

      // Timing is reported rather than asserted because shared CI hosts can
      // invert sub-millisecond samples under load.
      expect(batched.median, greaterThan(0));
      expect(sequential.median, greaterThan(0));
    },
  );
}

Future<_Measurements> _measure(
  int iterations,
  Future<void> Function() action,
) async {
  for (var index = 0; index < 5; index += 1) {
    await action();
  }
  final samples = <int>[];
  for (var index = 0; index < iterations; index += 1) {
    final stopwatch = Stopwatch()..start();
    await action();
    stopwatch.stop();
    samples.add(stopwatch.elapsedMicroseconds);
  }
  samples.sort();
  return _Measurements(
    median: samples[samples.length ~/ 2],
    p95: samples[((samples.length - 1) * 0.95).round()],
  );
}

String _ms(int microseconds) => (microseconds / 1000).toStringAsFixed(3);

final class _Measurements {
  const _Measurements({required this.median, required this.p95});

  final int median;
  final int p95;
}
