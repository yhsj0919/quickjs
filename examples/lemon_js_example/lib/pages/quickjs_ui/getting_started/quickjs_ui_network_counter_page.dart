import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 网络计数器 Demo：通过本地开发服务器按 network URL 加载 quickjs_ui 页面。
class QuickjsUiNetworkCounterPage extends StatefulWidget {
  const QuickjsUiNetworkCounterPage({super.key});

  /// 远程发布包根目录，目录内包含 manifest.json 和清单声明的模块。
  static final Uri packageRoot = Uri.parse(
    'https://ad.palsmon.com/plugin/wather/',
  );

  @override
  State<QuickjsUiNetworkCounterPage> createState() =>
      _QuickjsUiNetworkCounterPageState();
}

class _QuickjsUiNetworkCounterPageState
    extends State<QuickjsUiNetworkCounterPage> {
  final QuickjsUiController _controller = QuickjsUiController();
  final Stopwatch _stopwatch = Stopwatch()..start();
  QuickjsUiBundle? _bundle;
  Widget? _view;
  Object? _loadError;
  Duration? _firstRenderElapsed;
  int _loadRequest = 0;

  @override
  void initState() {
    super.initState();
    _loadPackage();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络加载计数器')),
      body: Stack(
        children: <Widget>[
          DecoratedBox(
            decoration: const BoxDecoration(color: Color(0xfff4f7fb)),
            child: SizedBox.expand(child: _buildContent()),
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
                  onReload: () => _loadPackage(force: true),
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

  Widget _buildContent() {
    final error = _loadError;
    if (error != null) {
      return _NetworkErrorMessage(error: error);
    }
    return _view ?? const _DelayedLoadingIndicator();
  }

  Widget _createView(QuickjsUiBundle bundle) {
    return QuickjsUiView.plugin(
      bundle.toPlugin(),
      controller: _controller,
      initialProps: <String, Object?>{
        'packageId': bundle.id,
        'packageVersion': bundle.version,
        'moduleCount': bundle.modules.length,
        'resourceCount': bundle.resources.length,
      },
      loadingBuilder: (_) => const _DelayedLoadingIndicator(),
      errorBuilder: (_, error) => _NetworkErrorMessage(error: error),
      onFirstRender: _handleFirstRender,
    );
  }

  Future<void> _loadPackage({bool force = false}) async {
    final request = ++_loadRequest;
    if (_bundle == null) {
      _stopwatch
        ..reset()
        ..start();
    }
    setState(() {
      _loadError = null;
      if (_bundle == null) {
        _firstRenderElapsed = null;
      }
    });
    try {
      final bundle = await QuickjsUiBundle.networkPackage(
        root: QuickjsUiNetworkCounterPage.packageRoot,
        refreshMode: force
            ? QuickjsUiNetworkRefreshMode.force
            : QuickjsUiNetworkRefreshMode.conditional,
        onLog: _handleNetworkLog,
      );
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _view = _createView(bundle);
      });
    } catch (error) {
      if (!mounted || request != _loadRequest) {
        return;
      }
      setState(() {
        _loadError = error;
      });
    }
  }

  void _handleFirstRender() {
    if (_firstRenderElapsed != null) {
      return;
    }
    _stopwatch.stop();
    final elapsed = _stopwatch.elapsed;
    debugPrint(
      'QuickJS UI network first render: ${elapsed.inMilliseconds}ms '
      '(${QuickjsUiNetworkCounterPage.packageRoot})',
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
        FilledButton(onPressed: onReload, child: const Text('Reload source')),
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
    final hint = kIsWeb
        ? '请确认发布包允许浏览器跨域访问，并且 manifest.json 与模块文件均可访问。'
        : '请确认网络连接以及远程发布包的 manifest.json。';
    return Padding(
      padding: const EdgeInsets.all(16),
      child: SelectableText('QuickJS UI network error: $error\n\n$hint'),
    );
  }
}
