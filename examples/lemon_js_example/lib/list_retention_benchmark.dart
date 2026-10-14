import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/scheduler.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui/lemon_js_ui_session.dart';

// Each mode runs in a fresh release process. Probes are identical in every mode.
void main(List<String> args) {
  WidgetsFlutterBinding.ensureInitialized();
  if (!kReleaseMode && !kProfileMode) throw StateError('Use profile/release');
  runApp(
    MaterialApp(
      home: _Retention(mode: args[0], output: args[1]),
    ),
  );
}

class _Counts {
  int widgets = 0, mounts = 0, disposes = 0, builds = 0, updates = 0, peak = 0;
  final indices = <int, int>{};
  int get active => mounts - disposes;
  Widget row(int index) {
    widgets++;
    indices.update(index, (value) => value + 1, ifAbsent: () => 1);
    return _Row(key: ValueKey(index), index: index, counts: this);
  }

  Map<String, Object> snapshot() => {
    'widgetsCreated': widgets,
    'distinctIndices': indices.length,
    'repeatWidgetConstructions': widgets - indices.length,
    'stateMounts': mounts,
    'stateDisposes': disposes,
    'activeStates': active,
    'peakActiveStates': peak,
    'stateBuilds': builds,
    'stateUpdates': updates,
  };
}

class _Row extends StatefulWidget {
  const _Row({super.key, required this.index, required this.counts});
  final int index;
  final _Counts counts;
  @override
  State<_Row> createState() => _RowState();
}

class _RowState extends State<_Row> {
  @override
  void initState() {
    super.initState();
    widget.counts.mounts++;
    if (widget.counts.active > widget.counts.peak) {
      widget.counts.peak = widget.counts.active;
    }
  }

  @override
  void didUpdateWidget(covariant _Row oldWidget) {
    super.didUpdateWidget(oldWidget);
    widget.counts.updates++;
  }

  @override
  Widget build(BuildContext context) {
    widget.counts.builds++;
    return Text('Item ${widget.index}');
  }

  @override
  void dispose() {
    widget.counts.disposes++;
    super.dispose();
  }
}

class _Retention extends StatefulWidget {
  const _Retention({required this.mode, required this.output});
  final String mode, output;
  @override
  State<_Retention> createState() => _RetentionState();
}

class _RetentionState extends State<_Retention>
    with SingleTickerProviderStateMixin {
  final _viewport = GlobalKey();
  final _counts = _Counts();
  Widget _list = const SizedBox.shrink();
  late final Ticker _ticker;
  int _remaining = 0, _clamps = 0, _cachedRows = 0, _events = 0;
  double _step = 0, _distance = 0;
  Completer<void>? _done;
  Future<void> _pending = Future<void>.value();
  ScrollableState? get _scrollable {
    ScrollableState? result;
    void visit(Element element) {
      if (element is StatefulElement && element.state is ScrollableState) {
        result ??= element.state as ScrollableState;
      }
      element.visitChildren(visit);
    }

    _viewport.currentContext?.visitChildElements(visit);
    return result;
  }

  @override
  void initState() {
    super.initState();
    _ticker = createTicker((_) {
      final position = _scrollable?.position;
      if (position != null && position.hasContentDimensions) {
        final target = position.pixels + _step;
        final next = target.clamp(
          position.minScrollExtent,
          position.maxScrollExtent,
        );
        if ((next - target).abs() > .01) _clamps++;
        _distance += (next - position.pixels).abs();
        position.jumpTo(next);
      }
      if (--_remaining == 0) {
        _ticker.stop();
        _done!.complete();
      }
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => unawaited(_run()));
  }

  Map<String, Object?> _checkpoint(String phase) {
    var elements = 0;
    void visit(Element element) {
      elements++;
      element.visitChildren(visit);
    }

    _viewport.currentContext?.visitChildElements(visit);
    return {
      'phase': phase,
      ..._counts.snapshot(),
      'rssBytes': ProcessInfo.currentRss,
      'peakRssBytes': ProcessInfo.maxRss,
      'subtreeElements': elements,
      'cachedRowWidgets': widget.mode == 'virtual-local' ? _cachedRows : 0,
      'rangeEvents': _events,
      'offset': _scrollable?.position.pixels,
      'distance': _distance,
      'clampedTicks': _clamps,
    };
  }

  Future<void> _segment(int ticks, double step) async {
    _remaining = ticks;
    _step = step;
    _distance = 0;
    _clamps = 0;
    _done = Completer<void>();
    _ticker.start();
    await _done!.future;
    await _pending;
    await WidgetsBinding.instance.endOfFrame;
    await Future<void>.delayed(const Duration(milliseconds: 300));
  }

  Future<void> _run() async {
    final checkpoints = <Map<String, Object?>>[];
    try {
      if (!['native', 'sync-builder', 'virtual-local'].contains(widget.mode)) {
        throw ArgumentError(widget.mode);
      }
      final engine = await JsEngine.create();
      JsUiSession? session;
      final registry = JsUiComponentRegistry.defaults()
        ..register(
          'BenchRow',
          (_, node) => _counts.row((node.props['index'] as num).toInt()),
        );
      late final JsUiRenderer renderer;
      renderer = JsUiRenderer(
        registry: registry,
        onEvent: (event) {
          _events++;
          _pending = session!.dispatch(event).then((_) {
            _cachedRows = (session!.node!.props['batchEnd'] as num).toInt();
            if (mounted) setState(() => _list = renderer.build(session!.node!));
          });
        },
      );
      if (widget.mode == 'virtual-local') {
        session = JsUiSession(engine: engine);
        await session.loadPlugin(
          JsUiPagePlugin.source(
            id: 'retention',
            version: '1.0.0',
            source: '''
import {Page,ListView} from 'quickjs_ui';
export default Page({build(){return ListView.builder({
key:'list',itemCount:100000,itemExtent:48,cacheExtent:250,padding:0,prefetchItemCount:20,
itemBuilder:i=>({type:'BenchRow',key:'row-'+i,index:i})});}});
''',
          ),
        );
        _cachedRows = (session.node!.props['batchEnd'] as num).toInt();
        _list = renderer.build(session.node!);
      } else {
        engine.evalRawSync(
          "globalThis.row=i=>({type:'BenchRow',key:'row-'+i,index:i});",
        );
        _list = ListView.builder(
          itemCount: 100000,
          itemExtent: 48,
          padding: EdgeInsets.zero,
          scrollCacheExtent: const ScrollCacheExtent.pixels(250),
          itemBuilder: (_, index) => widget.mode == 'native'
              ? _counts.row(index)
              : renderer.build(
                  JsUiNode.fromMap(
                    Map<String, Object?>.from(
                      engine.callSync('row', [index]) as Map,
                    ),
                  ),
                ),
        );
      }
      setState(() {});
      await WidgetsBinding.instance.endOfFrame;
      await Future<void>.delayed(const Duration(seconds: 1));
      checkpoints.add(_checkpoint('initial'));
      await _segment(480, 48);
      checkpoints.add(_checkpoint('forward-480-rows'));
      await _segment(480, -48);
      checkpoints.add(_checkpoint('return-to-start'));
      await _segment(960, 48);
      checkpoints.add(_checkpoint('forward-960-rows'));
      setState(() => _list = const SizedBox.shrink());
      await WidgetsBinding.instance.endOfFrame;
      renderer.dispose();
      if (session != null) await session.dispose();
      await engine.dispose();
      _cachedRows = 0;
      await Future<void>.delayed(const Duration(seconds: 1));
      checkpoints.add(_checkpoint('disposed'));
      await File(widget.output).writeAsString(
        const JsonEncoder.withIndent('  ').convert({
          'mode': widget.mode,
          'buildMode': kReleaseMode ? 'release' : 'profile',
          'itemCount': 100000,
          'rowExtent': 48,
          'cacheExtent': 250,
          'memoryMetric':
              'OS process RSS, no forced GC; includes Dart/native/GPU allocator retention',
          'checkpoints': checkpoints,
        }),
      );
      exit(0);
    } catch (error, stack) {
      await File(widget.output).writeAsString(
        jsonEncode({
          'error': '$error',
          'stack': '$stack',
          'checkpoints': checkpoints,
        }),
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
    _ticker.dispose();
    super.dispose();
  }
}
