import 'dart:async';
import 'dart:ui' show FrameTiming;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// PageView gesture and animation comparisons without a JS runtime.
class JsUiPageViewLabPage extends StatefulWidget {
  const JsUiPageViewLabPage({super.key});

  @override
  State<JsUiPageViewLabPage> createState() => _JsUiPageViewLabPageState();
}

class _JsUiPageViewLabPageState extends State<JsUiPageViewLabPage> {
  static const _count = 5;
  final _nativeController = PageController(initialPage: 1000000);
  final _timings = <FrameTiming>[];
  final _stats = ValueNotifier<String>('尚无帧样本');
  Timer? _nativeTimer;
  bool _native = false;
  bool _feedback = true;
  bool _loop = true;
  bool _playing = false;
  String _curve = 'easeOut';
  int _page = 0;
  int _pageCommandToken = 0;
  int _observed = 0;
  int _generation = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addTimingsCallback(_recordTimings);
  }

  void _recordTimings(List<FrameTiming> frames) {
    _timings.addAll(frames);
    if (_timings.length > 600) _timings.removeRange(0, _timings.length - 600);
    String summary(Duration Function(FrameTiming) read) {
      final values =
          _timings.map((frame) => read(frame).inMicroseconds / 1000).toList()
            ..sort();
      final avg = values.reduce((a, b) => a + b) / values.length;
      return '${avg.toStringAsFixed(1)}/${values[((values.length - 1) * .9).round()].toStringAsFixed(1)}/${values.last.toStringAsFixed(1)}';
    }

    _stats.value =
        '样本 ${_timings.length} · avg/P90/max (ms)\n'
        'UI ${summary((frame) => frame.buildDuration)} · Raster ${summary((frame) => frame.rasterDuration)}';
  }

  void _changed(int index) {
    setState(() {
      _observed = index;
      if (_feedback) _page = index;
    });
  }

  void _scheduleNative() {
    _nativeTimer?.cancel();
    if (!mounted ||
        !_native ||
        !_playing ||
        !_nativeController.hasClients ||
        _nativeController.position.isScrollingNotifier.value) {
      return;
    }
    final current = _nativeController.page!.round();
    if (!_loop && current >= _count - 1) return;
    _nativeTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted || !_nativeController.hasClients) return;
      _nativeController.animateToPage(
        current + 1,
        duration: const Duration(milliseconds: 300),
        curve: _curve == 'linear' ? Curves.linear : Curves.easeOut,
      );
    });
  }

  void _reset() {
    _nativeTimer?.cancel();
    _page = 0;
    _observed = 0;
    _generation++;
    _timings.clear();
    _stats.value = '尚无帧样本';
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (_nativeController.hasClients) {
        _nativeController.jumpToPage(_loop ? 1000000 : 0);
      }
      _scheduleNative();
    });
  }

  void _next() {
    if (_native) {
      final current = _nativeController.page!.round();
      if (!_loop && current == _count - 1) return;
      _nativeController.animateToPage(
        current + 1,
        duration: const Duration(milliseconds: 300),
        curve: _curve == 'linear' ? Curves.linear : Curves.easeOut,
      );
    } else {
      setState(() {
        _page = _loop
            ? (_observed + 1) % _count
            : (_observed + 1).clamp(0, _count - 1);
        _pageCommandToken++;
      });
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeTimingsCallback(_recordTimings);
    _nativeTimer?.cancel();
    _nativeController.dispose();
    _stats.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final viewport = _native
        ? NotificationListener<ScrollNotification>(
            onNotification: (event) {
              if (event.depth != 0) return false;
              if (event is ScrollStartNotification) _nativeTimer?.cancel();
              if (event is ScrollEndNotification) {
                scheduleMicrotask(_scheduleNative);
              }
              return false;
            },
            child: PageView.builder(
              key: ValueKey(_generation),
              controller: _nativeController,
              itemCount: _loop ? null : _count,
              onPageChanged: (index) => _changed(index % _count),
              itemBuilder: (_, index) => ColoredBox(
                color: Colors.primaries[index % _count],
                child: Center(
                  child: Text(
                    '第 ${index % _count + 1} 页',
                    style: const TextStyle(fontSize: 48, color: Colors.white),
                  ),
                ),
              ),
            ),
          )
        : KeyedSubtree(
            key: ValueKey(_generation),
            child:
                JsUiRenderer(
                  onEvent: (event) => _changed(event['index']! as int),
                ).build(
                  JsUiNode.fromMap({
                    'type': 'PageView',
                    'loop': _loop,
                    'page': _page,
                    'pageCommandToken': _pageCommandToken,
                    'autoPlay': _playing,
                    'autoPlayIntervalMs': 3000,
                    'scrollDurationMs': 300,
                    'scrollCurve': _curve,
                    'onPageChanged': {'method': 'changed'},
                    'children': [
                      for (var i = 0; i < _count; i++)
                        {
                          'type': 'Container',
                          'color':
                              '#${Colors.primaries[i].toARGB32().toRadixString(16)}',
                          'child': {
                            'type': 'Center',
                            'child': {
                              'type': 'Text',
                              'data': '第 ${i + 1} 页',
                              'style': {'fontSize': 48, 'color': '#ffffffff'},
                            },
                          },
                        },
                    ],
                  }),
                ),
          );
    return Scaffold(
      appBar: AppBar(title: const Text('PageView · 循环与翻页对照')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Wrap(
              spacing: 12,
              runSpacing: 8,
              crossAxisAlignment: WrapCrossAlignment.center,
              children: [
                ChoiceChip(
                  label: const Text('JSUI 渲染器'),
                  selected: !_native,
                  onSelected: (_) => setState(() {
                    _native = false;
                    _reset();
                  }),
                ),
                ChoiceChip(
                  label: const Text('原生 PageView'),
                  selected: _native,
                  onSelected: (_) => setState(() {
                    _native = true;
                    _reset();
                  }),
                ),
                FilterChip(
                  label: const Text('回写 page'),
                  selected: _feedback,
                  onSelected: (value) => setState(() => _feedback = value),
                ),
                FilterChip(
                  label: const Text('循环'),
                  selected: _loop,
                  onSelected: (value) => setState(() {
                    _loop = value;
                    _reset();
                  }),
                ),
                DropdownButton<String>(
                  value: _curve,
                  items: const [
                    DropdownMenuItem(
                      value: 'easeOut',
                      child: Text('easeOut（减速）'),
                    ),
                    DropdownMenuItem(
                      value: 'linear',
                      child: Text('linear（匀速）'),
                    ),
                  ],
                  onChanged: (value) => setState(() => _curve = value!),
                ),
                ElevatedButton(
                  onPressed: () {
                    setState(() => _playing = !_playing);
                    _scheduleNative();
                  },
                  child: Text(_playing ? '暂停自动翻页' : '启动自动翻页'),
                ),
                OutlinedButton(onPressed: _next, child: const Text('下一页')),
                Text('实际索引 $_observed · 受控 page $_page'),
              ],
            ),
          ),
          Expanded(
            child: ScrollConfiguration(
              behavior: ScrollConfiguration.of(
                context,
              ).copyWith(dragDevices: PointerDeviceKind.values.toSet()),
              child: viewport,
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              children: [
                Text(
                  '${kReleaseMode
                      ? 'RELEASE'
                      : kProfileMode
                      ? 'PROFILE'
                      : 'DEBUG'} · ${_native ? '原生' : 'JSUI 渲染器'} · 300ms / 自动间隔 3s',
                ),
                const Text(
                  '先比较回写开/关，再比较原生。此页隔离渲染层，不经过 QuickJS。Windows 可按住拖动或使用触屏。',
                ),
                ValueListenableBuilder<String>(
                  valueListenable: _stats,
                  builder: (_, value, child) => Text(value),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
