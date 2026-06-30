import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiCounterPage extends StatefulWidget {
  const QuickjsUiCounterPage({super.key});

  static const String path = 'assets/quickjs_ui/counter_page.mjs';

  @override
  State<QuickjsUiCounterPage> createState() => _QuickjsUiCounterPageState();
}

class _QuickjsUiCounterPageState extends State<QuickjsUiCounterPage> {
  final Stopwatch _stopwatch = Stopwatch()..start();
  Duration? _firstRenderElapsed;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI Counter')),
      body: Stack(
        children: <Widget>[
          QuickjsUiView.asset(
            path: QuickjsUiCounterPage.path,
            initialProps: const <String, Object?>{
              'title': 'QuickJS UI',
              'initialCount': 0,
            },
            loadingBuilder: (_) => const _DelayedLoadingIndicator(),
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
      'QuickJS UI first render: ${elapsed.inMilliseconds}ms '
      '(${QuickjsUiCounterPage.path})',
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
        ? 'QuickJS UI rendering...'
        : 'QuickJS UI first render: ${elapsed!.inMilliseconds} ms';
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
