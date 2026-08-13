import 'package:flutter_test/flutter_test.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('compares 60-second idle timer pump schedules', () async {
    const ticks = 120;
    const warmupTicks = 10;
    final optimized = QuickjsUiSession();
    final legacy = QuickjsUiSession();
    addTearDown(optimized.dispose);
    addTearDown(legacy.dispose);

    await optimized.loadPlugin(
      QuickjsUiPagePlugin.singleFile(
        id: 'timer_pump_optimized_benchmark',
        version: '1.0.0',
        source: '''
import { Page, Text } from 'quickjs_ui';
export default Page({
  createState() { return { count: 0 }; },
  build(state) { return Text('Count: ' + state.count); }
});
''',
      ),
    );
    await legacy.loadPlugin(_legacyIdlePlugin());

    for (var index = 0; index < warmupTicks; index += 1) {
      await optimized.pumpTimers();
      await legacy.pumpTimers();
    }

    final optimizedResult = await _measureScheduled(optimized, ticks);
    final legacyResult = await _measureScheduled(legacy, ticks);
    _printResult('version-poll', optimizedResult, workerRequestsPerTick: 2);
    _printResult('legacy', legacyResult, workerRequestsPerTick: 3);

    // An idle runtime has no next deadline. The event-driven scheduler performs
    // one discovery pump, then leaves the Dart event loop completely quiet.
    expect(optimizedResult.samples, hasLength(1));
    expect(legacyResult.samples, hasLength(1));
    expect(optimizedResult.changedTicks, 0);
    expect(legacyResult.changedTicks, 1);
  });
}

Future<_PumpBenchmarkResult> _measureScheduled(
  QuickjsUiSession session,
  int ticks,
) async {
  final samples = <int>[];
  var changedTicks = 0;
  final total = Stopwatch()..start();
  for (var index = 0; index < ticks; index += 1) {
    final sample = Stopwatch()..start();
    final result = await session.pumpTimers();
    if (result.changed) changedTicks += 1;
    samples.add(sample.elapsedMicroseconds);
    if (result.nextDelay == null) break;
  }
  total.stop();
  samples.sort();
  return _PumpBenchmarkResult(
    samples: samples,
    total: total.elapsed,
    changedTicks: changedTicks,
  );
}

void _printResult(
  String name,
  _PumpBenchmarkResult result, {
  required int workerRequestsPerTick,
}) {
  // ignore: avoid_print
  print(
    'timerPump[$name] ticks=${result.samples.length} '
    'changed=${result.changedTicks} '
    'median=${_ms(_percentile(result.samples, 0.50))}ms '
    'p95=${_ms(_percentile(result.samples, 0.95))}ms '
    'max=${_ms(result.samples.last)}ms '
    'total=${_ms(result.total.inMicroseconds)}ms '
    'workerRequests=${result.samples.length * workerRequestsPerTick} '
    'projectedFlutterNotifies=${result.changedTicks}',
  );
}

JsPlugin _legacyIdlePlugin() {
  return JsPlugin(
    manifest: const JsPluginManifest(
      id: 'timer_pump_legacy_benchmark',
      version: '1.0.0',
      entry: 'timer_pump_legacy_benchmark/main',
      exports: <String>[
        'mount',
        'handleEvent',
        'commit',
        'setState',
        'lifecycle',
        'snapshot',
        'capabilities',
        'dispose',
      ],
    ),
    modules: const <JsPluginModule>[
      JsPluginModule(
        specifier: 'timer_pump_legacy_benchmark/main',
        source: '''
let firstCommit = true;
export function capabilities() {
  return {
    protocol: 'quickjs_ui.runtime.v1',
    schemaVersion: 1,
    helperVersion: 1,
    minimumQuickjsUiVersion: 1,
    lifecycle: []
  };
}
export function mount() { return { version: 1, state: { count: 0 } }; }
export function handleEvent() { return { changed: false }; }
export function setState() { return { changed: false }; }
export function lifecycle() { return { changed: false }; }
export function snapshot() { return { version: 1, state: { count: 0 } }; }
export function commit() {
  if (!firstCommit) return { changed: false };
  firstCommit = false;
  return { changed: true, node: { type: 'Text', data: 'Count: 0' } };
}
export function dispose() { return true; }
''',
      ),
    ],
  );
}

num _percentile(List<int> sorted, double percentile) {
  return sorted[((sorted.length - 1) * percentile).round()];
}

String _ms(num microseconds) => (microseconds / 1000).toStringAsFixed(3);

final class _PumpBenchmarkResult {
  const _PumpBenchmarkResult({
    required this.samples,
    required this.total,
    required this.changedTicks,
  });

  final List<int> samples;
  final Duration total;
  final int changedTicks;
}
