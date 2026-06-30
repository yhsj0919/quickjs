import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiBundleCounterPage extends StatefulWidget {
  const QuickjsUiBundleCounterPage({super.key});

  static const String path = 'assets/quickjs_ui/bundle_counter/pages/main.mjs';

  @override
  State<QuickjsUiBundleCounterPage> createState() =>
      _QuickjsUiBundleCounterPageState();
}

class _QuickjsUiBundleCounterPageState
    extends State<QuickjsUiBundleCounterPage> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _firstRenderElapsed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Bundle Counter')),
      body: Stack(
        children: <Widget>[
          DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xffeef3f7)),
            child: SizedBox.expand(
              child: QuickjsUiView.asset(
                path: QuickjsUiBundleCounterPage.path,
                initialProps: const <String, Object?>{
                  'title': 'Multi-file QuickJS UI',
                  'initialCount': 3,
                },
                loadingBuilder: (_) => const _DelayedLoadingIndicator(),
                errorBuilder: (_, error) => _ErrorMessage(error: error),
                onFirstRender: _handleFirstRender,
              ),
            ),
          ),
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _RenderTimingBanner(elapsed: _firstRenderElapsed),
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
      'QuickJS UI bundle first render: ${elapsed.inMilliseconds}ms '
      '(${QuickjsUiBundleCounterPage.path})',
    );
    setState(() {
      _firstRenderElapsed = elapsed;
    });
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
        ? 'QuickJS UI bundle rendering...'
        : 'QuickJS UI bundle first render: ${elapsed!.inMilliseconds} ms';
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

class _ErrorMessage extends StatelessWidget {
  const _ErrorMessage({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText('QuickJS UI bundle error: $error'),
    );
  }
}
