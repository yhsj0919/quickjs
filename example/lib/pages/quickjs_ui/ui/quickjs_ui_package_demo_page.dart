import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 发布包加载来源：asset 目录、zip 压缩包或本地开发服务器。
enum _PackageSource {
  asset('Asset', 'assets/quickjs_ui/package_demo/'),
  zip('Zip', 'assets/quickjs_ui/package_demo.zip'),
  network('Network', 'http://127.0.0.1:8765/package_demo/');

  const _PackageSource(this.label, this.location);

  final String label;
  final String location;
}

/// 0.5 发布包 Demo：固定包根 `main.mjs` + `manifest.json` 的加载与校验。
class QuickjsUiPackageDemoPage extends StatefulWidget {
  const QuickjsUiPackageDemoPage({super.key});

  @override
  State<QuickjsUiPackageDemoPage> createState() =>
      _QuickjsUiPackageDemoPageState();
}

class _QuickjsUiPackageDemoPageState extends State<QuickjsUiPackageDemoPage> {
  QuickjsUiBundle? _bundle;
  Object? _error;
  _PackageSource _source = _PackageSource.asset;
  int _loadVersion = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load([_PackageSource? source]) async {
    final nextSource = source ?? _source;
    setState(() {
      _source = nextSource;
      _error = null;
    });
    try {
      final bundle = switch (nextSource) {
        _PackageSource.asset => await QuickjsUiBundle.assetPackage(
          root: nextSource.location,
        ),
        _PackageSource.zip => await QuickjsUiBundle.assetZipPackage(
          assetKey: nextSource.location,
        ),
        _PackageSource.network => await QuickjsUiBundle.networkPackage(
          root: Uri.parse(nextSource.location),
        ),
      };
      if (!mounted) {
        return;
      }
      setState(() {
        _bundle = bundle;
        _loadVersion += 1;
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _error = error;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bundle = _bundle;
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickJS UI Package'),
        actions: <Widget>[
          IconButton(
            tooltip: 'Reload package',
            onPressed: () => _load(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          _PackageHeader(
            source: _source,
            bundle: bundle,
            error: _error,
            onSourceChanged: _load,
          ),
          const Divider(height: 1),
          Expanded(
            child: _error != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: SelectableText(
                        _source == _PackageSource.network
                            ? 'Load failed: $_error\n\n'
                                  'Run: dart run tool/quickjs_ui_dev_server.dart'
                            : 'Load failed: $_error',
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : bundle == null
                ? const Center(child: CircularProgressIndicator())
                : QuickjsUiView.plugin(
                    bundle.toPlugin(),
                    key: ValueKey<String>(
                      '${bundle.id}:${bundle.version}:$_loadVersion',
                    ),
                    initialProps: <String, Object?>{
                      'packageId': bundle.id,
                      'packageVersion': bundle.version,
                      'moduleCount': bundle.modules.length,
                      'resourceCount': bundle.resources.length,
                    },
                    loadingBuilder: (_) =>
                        const Center(child: CircularProgressIndicator()),
                  ),
          ),
        ],
      ),
    );
  }
}

class _PackageHeader extends StatelessWidget {
  const _PackageHeader({
    required this.source,
    required this.bundle,
    required this.error,
    required this.onSourceChanged,
  });

  final _PackageSource source;
  final QuickjsUiBundle? bundle;
  final Object? error;
  final ValueChanged<_PackageSource> onSourceChanged;

  @override
  Widget build(BuildContext context) {
    final textTheme = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: <Widget>[
          SegmentedButton<_PackageSource>(
            segments: <ButtonSegment<_PackageSource>>[
              for (final source in _PackageSource.values)
                ButtonSegment<_PackageSource>(
                  value: source,
                  label: Text(source.label),
                ),
            ],
            selected: <_PackageSource>{source},
            onSelectionChanged: (selected) => onSourceChanged(selected.single),
          ),
          const SizedBox(height: 12),
          Text('Package source', style: textTheme.titleSmall),
          const SizedBox(height: 4),
          SelectableText(source.location),
          const SizedBox(height: 12),
          if (bundle != null) ...<Widget>[
            Text('${bundle!.id}@${bundle!.version}'),
            Text('entry: ${bundle!.entry}'),
            Text(
              'modules: ${bundle!.modules.length}, '
              'resources: ${bundle!.resources.length}',
            ),
          ],
          if (error != null)
            Text(
              '$error',
              style: TextStyle(color: Theme.of(context).colorScheme.error),
            ),
        ],
      ),
    );
  }
}
