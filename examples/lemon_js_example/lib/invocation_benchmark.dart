import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:lemon_js/lemon_js.dart';

// Release CPU benchmark: same total row count for individual and batched calls.
Future<void> main(List<String> args) async {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && !kProfileMode) throw StateError('Use profile/release');
  final result = args.contains('--eval')
      ? await measureEvals()
      : await measureInvocations();
  await File(
    args[0],
  ).writeAsString(const JsonEncoder.withIndent('  ').convert(result));
  exit(0);
}

/// Isolates source evaluation from direct calls, with the same result codec.
Future<Map<String, Object>> measureEvals() async {
  final engine = await JsEngine.create();
  engine.evalRawSync('globalThis.makeValue=x=>({value:x+1});');
  final results = <Map<String, Object>>[];
  for (final mode in ['dart', 'call', 'raw', 'structured', 'temporary']) {
    Object? run() => switch (mode) {
      'dart' => <String, Object?>{'value': 8},
      'call' => engine.callSync('makeValue', [7]),
      'raw' => engine.evalRawSync('makeValue(7)'),
      'structured' => engine.evalSync('makeValue(7)'),
      _ => engine.evalSync('makeValue(input)', tempGlobals: {'input': 7}),
    };
    for (var i = 0; i < 300; i++) {
      run();
    }
    final samples = <double>[];
    for (var sample = 0; sample < 15; sample++) {
      final watch = Stopwatch()..start();
      for (var i = 0; i < 1000; i++) {
        if (run() == null) throw StateError('Missing result');
      }
      watch.stop();
      samples.add(watch.elapsedMicroseconds / 1000);
    }
    samples.sort();
    results.add({
      'mode': mode,
      'evaluationsPerSample': 1000,
      'samples': 15,
      'medianUs': samples[7],
      'p90Us': samples[13],
      'minUs': samples.first,
      'maxUs': samples.last,
    });
  }
  await engine.dispose();
  return {
    'buildMode': kReleaseMode ? 'release' : 'profile',
    'results': results,
  };
}

/// Shared by the standalone entry point and the complete list benchmark.
Future<Map<String, Object>> measureInvocations() async {
  final engine = await JsEngine.create(
    methods: [
      JsHostMethod.global(name: 'hostEcho', callback: (args, _) => args[0]),
    ],
  );
  engine.evalRawSync(
    "globalThis.row=i=>({type:'Text',key:'row-'+i,data:'Item '+i});globalThis.hostRow=i=>hostEcho(row(i));",
  );
  final results = <Map<String, Object>>[];
  for (final method in ['row', 'hostRow']) {
    for (final batchSize in [1, 20, 100]) {
      for (final asynchronous in [false, true]) {
        final groups = [
          for (var start = 0; start < 1000; start += batchSize)
            [
              for (var i = start; i < start + batchSize; i++) <Object?>[i],
            ],
        ];
        Future<void> run() async {
          for (final arguments in groups) {
            final Object? value;
            if (batchSize == 1) {
              value = asynchronous
                  ? await engine.call(method, arguments[0])
                  : engine.callSync(method, arguments[0]);
            } else {
              value = asynchronous
                  ? await engine.callBatch(method, arguments)
                  : engine.callBatchSync(method, arguments);
            }
            if (value == null) throw StateError('Missing result');
          }
        }

        for (var i = 0; i < 3; i++) {
          await run();
        }
        final samples = <double>[];
        for (var i = 0; i < 15; i++) {
          final watch = Stopwatch()..start();
          await run();
          watch.stop();
          samples.add(watch.elapsedMicroseconds / 1000);
        }
        samples.sort();
        results.add({
          'method': method,
          'batchSize': batchSize,
          'async': asynchronous,
          'rowsPerSample': 1000,
          'samples': 15,
          'medianMs': samples[7],
          'p90Ms': samples[13],
          'minMs': samples.first,
          'maxMs': samples.last,
          'medianUsPerRow': samples[7],
        });
      }
    }
  }
  await engine.dispose();
  return {
    'buildMode': kReleaseMode ? 'release' : 'profile',
    'results': results,
  };
}
