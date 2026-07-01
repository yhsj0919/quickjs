import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiCounterPage extends StatefulWidget {
  const QuickjsUiCounterPage({super.key});

  static const String path = 'assets/quickjs_ui/counter_page.mjs';

  @override
  State<QuickjsUiCounterPage> createState() => _QuickjsUiCounterPageState();
}

class _QuickjsUiCounterPageState extends State<QuickjsUiCounterPage> {
  late final QuickjsUiController _controller;
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _firstRenderElapsed;
  String _status = 'Waiting for first render';

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController()..addListener(_handleControllerChanged);
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
        title: const Text('QuickJS UI Counter'),
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
          QuickjsUiView.asset(
            path: QuickjsUiCounterPage.path,
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
      'QuickJS UI first render: ${elapsed.inMilliseconds}ms '
      '(${QuickjsUiCounterPage.path})',
    );
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

class _DelayedLoadingIndicator extends StatefulWidget {
  const _DelayedLoadingIndicator();

  @override
  State<_DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<_DelayedLoadingIndicator> {
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    Future<void>.delayed(const Duration(milliseconds: 180), () {
      if (mounted) {
        setState(() {
          _visible = true;
        });
      }
    });
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
