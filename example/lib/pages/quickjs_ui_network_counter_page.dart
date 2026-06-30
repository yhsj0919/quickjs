import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiNetworkCounterPage extends StatefulWidget {
  const QuickjsUiNetworkCounterPage({super.key});

  static final Uri url = Uri.parse(
    'http://127.0.0.1:8765/bundle_counter/pages/main.mjs',
  );

  @override
  State<QuickjsUiNetworkCounterPage> createState() =>
      _QuickjsUiNetworkCounterPageState();
}

class _QuickjsUiNetworkCounterPageState
    extends State<QuickjsUiNetworkCounterPage> {
  final QuickjsUiController _controller = QuickjsUiController();
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _firstRenderElapsed;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Network Counter')),
      body: Stack(
        children: <Widget>[
          DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xfff4f7fb)),
            child: SizedBox.expand(
              child: QuickjsUiView.network(
                url: QuickjsUiNetworkCounterPage.url,
                controller: _controller,
                initialProps: const <String, Object?>{
                  'title': 'Network QuickJS UI',
                  'initialCount': 10,
                },
                loadingBuilder: (_) => const _DelayedLoadingIndicator(),
                errorBuilder: (_, error) => _NetworkErrorMessage(error: error),
                onNetworkLog: _handleNetworkLog,
                onFirstRender: _handleFirstRender,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: <Widget>[
                _NetworkActions(
                  onRefresh: _controller.refresh,
                  onReload: _controller.reload,
                ),
                const SizedBox(height: 8),
                _RenderTimingBanner(elapsed: _firstRenderElapsed),
              ],
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
      'QuickJS UI network first render: ${elapsed.inMilliseconds}ms '
      '(${QuickjsUiNetworkCounterPage.url})',
    );
    setState(() {
      _firstRenderElapsed = elapsed;
    });
  }

  void _handleNetworkLog(QuickjsUiNetworkLogEvent event) {
    debugPrint(
      'QuickJS UI ${event.type}: ${event.uri} '
      'status=${event.statusCode ?? '-'} '
      'etag=${event.etag ?? '-'} '
      'cache=${event.fromCache}',
    );
  }
}

class _NetworkActions extends StatelessWidget {
  const _NetworkActions({required this.onRefresh, required this.onReload});

  final VoidCallback onRefresh;
  final VoidCallback onReload;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 8,
      children: <Widget>[
        FilledButton.tonal(onPressed: onRefresh, child: const Text('Refresh')),
        FilledButton(onPressed: onReload, child: const Text('Reload')),
      ],
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
  const _RenderTimingBanner({required this.elapsed});

  final Duration? elapsed;

  @override
  Widget build(BuildContext context) {
    final text = elapsed == null
        ? 'QuickJS UI network rendering...'
        : 'QuickJS UI network first render: ${elapsed!.inMilliseconds} ms';
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

class _NetworkErrorMessage extends StatelessWidget {
  const _NetworkErrorMessage({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText(
        'QuickJS UI network error: $error\n\n'
        'Run: dart run tool/quickjs_ui_dev_server.dart',
      ),
    );
  }
}
