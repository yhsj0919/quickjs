import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:quickjs/quickjs.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('measures fixed cost of an already-loaded module call', () async {
    const iterations = 500;
    const warmupIterations = 50;
    final plugin = QuickjsPlugin(
      manifest: const QuickjsPluginManifest(
        id: 'call_module_benchmark',
        version: '1.0.0',
        entry: 'call_module_benchmark/main',
        exports: <String>['empty'],
      ),
      modules: const <QuickjsPluginModule>[
        QuickjsPluginModule(
          specifier: 'call_module_benchmark/main',
          source: 'export function empty() { return null; }',
        ),
      ],
    );

    final runtime = await QuickjsRuntime.create();
    final context = await runtime.createContext(
      options: QuickjsContextOptions(plugins: <QuickjsPlugin>[plugin]),
    );
    try {
      for (var index = 0; index < warmupIterations; index += 1) {
        await context.callPlugin(plugin, 'empty', const <Object?>[]);
      }

      final samples = <int>[];
      final total = Stopwatch()..start();
      for (var index = 0; index < iterations; index += 1) {
        final sample = Stopwatch()..start();
        await context.callPlugin(plugin, 'empty', const <Object?>[]);
        samples.add(sample.elapsedMicroseconds);
      }
      total.stop();
      samples.sort();

      // ignore: avoid_print
      print('QuickJS callModule fixed-cost benchmark');
      // ignore: avoid_print
      print('iterations=$iterations warmup=$warmupIterations');
      // ignore: avoid_print
      print('dll=${Platform.environment['QUICKJS_DLL_PATH'] ?? 'auto'}');
      // ignore: avoid_print
      print('median=${_milliseconds(_percentile(samples, 0.50))}ms');
      // ignore: avoid_print
      print('p95=${_milliseconds(_percentile(samples, 0.95))}ms');
      // ignore: avoid_print
      print('p99=${_milliseconds(_percentile(samples, 0.99))}ms');
      // ignore: avoid_print
      print('max=${_milliseconds(samples.last)}ms');
      // ignore: avoid_print
      print(
        'average=${_milliseconds(total.elapsedMicroseconds / iterations)}ms',
      );
    } finally {
      await context.dispose();
      await runtime.dispose();
    }
  });
}

num _percentile(List<int> sorted, double percentile) {
  final index = ((sorted.length - 1) * percentile).round();
  return sorted[index];
}

String _milliseconds(num microseconds) {
  return (microseconds / 1000).toStringAsFixed(3);
}
