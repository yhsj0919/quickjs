import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import '../../../example_quickjs_ui_runtime.dart';

/// QuickJS UI 计数器 Demo：加载单文件 Page（.mjs）并用原生 Flutter Widget 渲染。
class JsUiCounterPage extends StatefulWidget {
  const JsUiCounterPage({
    super.key,
    this.runtime,
    this.title = '单文件计数器',
    this.timingLabel = 'QuickJS UI first render',
  });

  /// Optional application-scoped runtime. A null value preserves the original
  /// cold-start behavior and lets the controller own its engine.
  final JsUiRuntime? runtime;
  final String title;
  final String timingLabel;

  /// 单文件入口脚本的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/counter_page.mjs';

  @override
  State<JsUiCounterPage> createState() => _JsUiCounterPageState();
}

/// 记录首帧渲染耗时，并演示 [JsUiController] 状态监听。
class _JsUiCounterPageState extends State<JsUiCounterPage> {
  late final JsUiController _controller;
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _firstRenderElapsed;
  String _status = 'Waiting for first render';

  @override
  void initState() {
    super.initState();
    _controller = JsUiController(runtime: widget.runtime)
      ..addListener(_handleControllerChanged);
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final canControl = _controller.plugin != null && !_controller.isLoading;
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title),
        actions: <Widget>[
          IconButton(
            tooltip: 'Refresh render',
            icon: const Icon(Icons.refresh),
            onPressed: canControl
                ? () => _runControllerCommand('refresh', _controller.refresh)
                : null,
          ),
          IconButton(
            tooltip: 'Restart page',
            icon: const Icon(Icons.restart_alt),
            onPressed: canControl
                ? () => _runControllerCommand('restart', _controller.restart)
                : null,
          ),
          IconButton(
            tooltip: 'Reload source',
            icon: const Icon(Icons.sync),
            onPressed: canControl
                ? () => _runControllerCommand('reload', _controller.reload)
                : null,
          ),
        ],
      ),
      body: Stack(
        children: <Widget>[
          JsUiView.asset(
            path: JsUiCounterPage.path,
            controller: _controller,
            initialProps: const <String, Object?>{
              'title': 'QuickJS UI',
              'initialCount': 0,
            },
            loadingBuilder: (_) => const _DelayedLoadingIndicator(),
            emptyBuilder: (_) => const Center(child: Text('Preparing page...')),
            errorBuilder: (_, error) {
              return Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText('QuickJS UI error: $error'),
              );
            },
            onFirstRender: _handleFirstRender,
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _RenderTimingBanner(
              elapsed: _firstRenderElapsed,
              status: _status,
            ),
          ),
        ],
      ),
    );
  }

  void _handleFirstRender() {
    if (_firstRenderElapsed != null) {
      return;
    }
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsed;
    debugPrint(
      '${widget.timingLabel}: ${elapsed.inMilliseconds}ms '
      '(${JsUiCounterPage.path})',
    );
    final metrics = _controller.lastLoadMetrics;
    if (metrics != null) {
      final flutterTail = elapsed - metrics.totalToSchema;
      debugPrint(
        '${widget.timingLabel} stages: ${metrics.format()}, '
        'flutterFirstFrame=${flutterTail.inMicroseconds / 1000}ms',
      );
    }
    setState(() {
      _firstRenderElapsed = elapsed;
      _status = 'rendered';
    });
  }

  Future<void> _runControllerCommand(
    String label,
    Future<void> Function() command,
  ) async {
    setState(() {
      _status = '$label running';
    });
    try {
      await command();
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '$label done';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '$label failed: $error';
      });
    }
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

/// Warm-runtime variant of the counter used for an apples-to-apples benchmark.
/// It delegates to the same widget and JS asset as the cold counter.
class JsUiSharedRuntimeCounterPage extends StatelessWidget {
  const JsUiSharedRuntimeCounterPage({super.key});

  @override
  Widget build(BuildContext context) {
    return JsUiCounterPage(
      runtime: exampleJsUiRuntime,
      title: '共享运行时计数器',
      timingLabel: 'QuickJS UI shared runtime first render',
    );
  }
}

class _DelayedLoadingIndicator extends StatefulWidget {
  const _DelayedLoadingIndicator();

  @override
  State<_DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<_DelayedLoadingIndicator> {
  bool _visible = false;
  Timer? _showTimer;

  @override
  void initState() {
    super.initState();
    _showTimer = Timer(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    });
  }

  @override
  void dispose() {
    _showTimer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedOpacity(
      opacity: _visible ? 1 : 0,
      duration: const Duration(milliseconds: 120),
      child: const Center(child: CircularProgressIndicator()),
    );
  }
}

class _RenderTimingBanner extends StatelessWidget {
  const _RenderTimingBanner({required this.elapsed, required this.status});

  final Duration? elapsed;
  final String status;

  @override
  Widget build(BuildContext context) {
    final timing = elapsed == null
        ? 'QuickJS UI rendering...'
        : 'QuickJS UI first render: ${elapsed!.inMilliseconds} ms';
    final text = '$timing | $status';
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.surface.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(8),
        boxShadow: const <BoxShadow>[
          BoxShadow(blurRadius: 12, color: Color(0x33000000)),
        ],
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        child: Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelMedium,
        ),
      ),
    );
  }
}
