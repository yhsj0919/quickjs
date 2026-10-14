import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:ui' show FramePhase;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:flutter/rendering.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/lemon_js_ui_session.dart';
import 'invocation_benchmark.dart' show measureInvocations;

// Standalone release benchmark; no application routes or production protocol changes.
const _count = 100000;
const _extent = 48.0;
const _rowSource = '''
globalThis.row = i => ({type:'Text',key:'row-'+i,data:'Item '+i});
''';

void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && !kProfileMode) {
    throw StateError('Run this benchmark in profile or release mode');
  }
  runApp(
    MaterialApp(
      home: _Benchmark(
        output: args.isEmpty ? 'list-benchmark.json' : args.first,
      ),
    ),
  );
}

class _Benchmark extends StatefulWidget {
  const _Benchmark({required this.output});
  final String output;
  @override
  State<_Benchmark> createState() => _BenchmarkState();
}

class _BenchmarkState extends State<_Benchmark>
    with SingleTickerProviderStateMixin {
  final _viewport = GlobalKey();
  Widget _list = const SizedBox.shrink();
  final _samples = <FrameTiming>[];
  late final Ticker _ticker;
  bool _measuring = false;
  int _frame = 0;
  int _sampleStartMicros = 0;
  int _sampleEndMicros = 0;
  final _measurementClock = Stopwatch();
  double _distance = 0;
  int _clamped = 0;
  Completer<void>? _done;

  @override
  void initState() {
    super.initState();
    SchedulerBinding.instance.addTimingsCallback(_timings);
    _ticker = createTicker((_) {
      ScrollableState? scrollable;
      void visit(Element element) {
        if (element is StatefulElement && element.state is ScrollableState) {
          scrollable ??= element.state as ScrollableState;
        }
        element.visitChildren(visit);
      }

      _viewport.currentContext?.visitChildElements(visit);
      final position = scrollable?.position;
      if (position != null && position.hasContentDimensions) {
        final target = position.pixels + 8;
        final next = target.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if (_measuring) {
          _distance += next - position.pixels;
          if (next < target) _clamped++;
        }
        position.jumpTo(next);
      }
      _frame++;
      if (_frame == 60) {
        _measuring = true;
        _sampleStartMicros = SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds;
        _measurementClock
          ..reset()
          ..start();
      }
      if (_frame == 540) {
        _sampleEndMicros = SchedulerBinding
            .instance
            .currentSystemFrameTimeStamp
            .inMicroseconds;
        _measurementClock.stop();
        _measuring = false;
        _ticker.stop();
        _done?.complete();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  void _timings(List<FrameTiming> timings) {
    if (_sampleStartMicros == 0) return;
    _samples.addAll(
      timings.where((timing) {
        final timestamp = timing.timestampInMicroseconds(FramePhase.vsyncStart);
        return timestamp >= _sampleStartMicros &&
            (_sampleEndMicros == 0 || timestamp < _sampleEndMicros);
      }),
    );
  }

  Future<void> _run() async {
    final reports = <Map<String, Object?>>[];
    try {
      for (var round = 0; round < 2; round++) {
        final modes = [
          'native',
          'dart-schema',
          'sync-builder',
          'virtual-local',
          'virtual-worker',
        ];
        for (final mode in round == 0 ? modes : modes.reversed) {
          final engine = await JsEngine.create(
            options: JsOptions(
              execution: mode == 'virtual-worker'
                  ? JsExecution.workerIsolate
                  : JsExecution.currentIsolate,
            ),
          );
          JsUiSession? session;
          var calls = 0;
          var rowMicros = 0;
          var batches = 0;
          late final JsUiRenderer renderer;
          renderer = JsUiRenderer(
            onEvent: (event) {
              batches++;
              unawaited(
                session!.dispatch(event).then((_) {
                  if (mounted) {
                    setState(() => _list = renderer.build(session!.node!));
                  }
                }),
              );
            },
          );
          Widget buildRow(int index) {
            calls++;
            final watch = Stopwatch()..start();
            final Widget result;
            if (mode == 'native') {
              result = Text('Item $index', key: ValueKey('row-$index'));
            } else {
              final map = mode == 'sync-builder'
                  ? engine.callSync('row', [index]) as Map
                  : {
                      'type': 'Text',
                      'key': 'row-$index',
                      'data': 'Item $index',
                    };
              result = renderer.build(
                JsUiNode.fromMap(Map<String, Object?>.from(map)),
              );
            }
            rowMicros += watch.elapsedMicroseconds;
            return result;
          }

          if (mode.startsWith('virtual')) {
            session = JsUiSession(engine: engine);
            await session.loadPlugin(
              JsUiPagePlugin.source(
                id: 'list-benchmark',
                version: '1.0.0',
                source:
                    '''
import {Page,ListView,Text} from 'quickjs_ui';
export default Page({build(){return ListView.builder({
 key:'list',itemCount:$_count,itemExtent:$_extent,cacheExtent:250,
 padding:0,prefetchItemCount:20,itemBuilder:i=>Text('Item '+i,{key:'row-'+i})
});}});
''',
              ),
            );
            _list = renderer.build(session.node!);
          } else {
            engine.evalRawSync(_rowSource);
            _list = ListView.builder(
              key: UniqueKey(),
              padding: EdgeInsets.zero,
              itemExtent: _extent,
              scrollCacheExtent: const ScrollCacheExtent.pixels(250),
              itemCount: _count,
              itemBuilder: (_, index) => buildRow(index),
            );
          }
          setState(() {});
          await WidgetsBinding.instance.endOfFrame;
          await Future<void>.delayed(const Duration(milliseconds: 300));
          _samples.clear();
          _sampleStartMicros = 0;
          _sampleEndMicros = 0;
          _frame = 0;
          _distance = 0;
          _clamped = 0;
          _done = Completer<void>();
          final elapsed = Stopwatch()..start();
          _ticker.start();
          await _done!.future;
          elapsed.stop();
          await Future<void>.delayed(const Duration(milliseconds: 300));
          if (!mounted) return;
          final view = View.of(context);
          final refresh = view.display.refreshRate;
          final budget = 1000 / refresh;
          Map<String, Object> stats(double Function(FrameTiming) select) {
            final values = _samples.map(select).toList()..sort();
            if (values.length < 180) {
              throw StateError('Insufficient timing samples: ${values.length}');
            }
            return {
              'averageMs': values.reduce((a, b) => a + b) / values.length,
              'p90Ms': values[(values.length * .9).floor()],
              'maxMs': values.last,
              'overBudget': values.where((v) => v > budget).length,
            };
          }

          reports.add({
            'mode': mode,
            'round': round,
            'samples': _samples.length,
            'ui': stats((t) => t.buildDuration.inMicroseconds / 1000),
            'raster': stats((t) => t.rasterDuration.inMicroseconds / 1000),
            'total': stats((t) => t.totalSpan.inMicroseconds / 1000),
            'refreshHz': refresh,
            'budgetMs': budget,
            'driverTickHz': 540000 / elapsed.elapsedMilliseconds,
            'physicalWidth': view.physicalSize.width,
            'physicalHeight': view.physicalSize.height,
            'dpr': view.devicePixelRatio,
            'viewportWidth':
                (_viewport.currentContext!.findRenderObject() as RenderBox)
                    .size
                    .width,
            'viewportHeight':
                (_viewport.currentContext!.findRenderObject() as RenderBox)
                    .size
                    .height,
            'sampleWindowMs': _measurementClock.elapsedMicroseconds / 1000,
            'renderedFpsEstimate':
                _samples.length *
                1000000 /
                _measurementClock.elapsedMicroseconds,
            'scrollPixels': _distance,
            'clampedFrames': _clamped,
            'rowCallsIncludingWarmup': calls,
            'rowBuildTotalMs': rowMicros / 1000,
            'rangeEvents': batches,
          });
          setState(() => _list = const SizedBox.shrink());
          await WidgetsBinding.instance.endOfFrame;
          renderer.dispose();
          if (session != null) await session.dispose();
          await engine.dispose();
        }
      }
      await File(widget.output).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'buildMode': kReleaseMode ? 'release' : 'profile',
          'itemCount': _count,
          'itemExtent': _extent,
          'driver': '8 logical px/vsync, 60 warmup + 480 measured ticks',
          'runs': reports,
          'invocationBenchmark': await measureInvocations(),
        }),
      );
      exit(0);
    } catch (error, stack) {
      await File(widget.output).writeAsString(
        jsonEncode({'error': '$error', 'stack': '$stack', 'runs': reports}),
      );
      exit(1);
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    body: Center(
      child: SizedBox(
        width: 800,
        height: 600,
        child: RepaintBoundary(key: _viewport, child: _list),
      ),
    ),
  );

  @override
  void dispose() {
    SchedulerBinding.instance.removeTimingsCallback(_timings);
    _ticker.dispose();
    super.dispose();
  }
}
