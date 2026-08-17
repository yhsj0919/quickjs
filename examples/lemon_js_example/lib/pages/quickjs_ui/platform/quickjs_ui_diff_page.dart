import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 局部刷新 Demo：可视化 stable key 节点在 diff 中被跳过、变化节点重新构建。
class JsUiDiffPage extends StatefulWidget {
  const JsUiDiffPage({super.key});

  @override
  State<JsUiDiffPage> createState() => _JsUiDiffPageState();
}

class _JsUiDiffPageState extends State<JsUiDiffPage> {
  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/diff_page.mjs';

  late final JsUiComponentRegistry _registry;
  late final JsUiRenderer _renderer;
  late final JsUiController _controller;
  final Map<String, int> _buildCounts = <String, int>{};

  @override
  void initState() {
    super.initState();
    _registry = JsUiComponentRegistry.defaults()
      ..register('Probe', _buildProbe);
    _controller = JsUiController()..addListener(_handleControllerChanged);
    _renderer = JsUiRenderer(
      registry: _registry,
      onEvent: _controller.dispatch,
    );
    _load();
  }

  @override
  void dispose() {
    _controller.removeListener(_handleControllerChanged);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final error = _controller.error;
    final node = _controller.node;
    final content = error != null
        ? SelectableText('QuickJS UI diff error: $error')
        : node == null
        ? const Center(child: CircularProgressIndicator())
        : _renderer.build(node, buildContext: context);
    return Scaffold(
      appBar: AppBar(title: const Text('局部刷新诊断')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              'Stable builds: ${_buildCounts['stable'] ?? 0}',
              key: const ValueKey<String>('stable-build-count'),
            ),
            Text(
              'Changed builds: ${_buildCounts['changed'] ?? 0}',
              key: const ValueKey<String>('changed-build-count'),
            ),
            const SizedBox(height: 12),
            Expanded(child: content),
          ],
        ),
      ),
    );
  }

  Widget _buildProbe(JsUiRenderContext context, JsUiNode node) {
    final id = '${node.props['id']}';
    _buildCounts[id] = (_buildCounts[id] ?? 0) + 1;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: context.color(node.props['color']) ?? Colors.transparent,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Theme.of(context.buildContext!).dividerColor),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text('${node.props['label']}'),
      ),
    );
  }

  Future<void> _load() async {
    await _controller.load(() async {
      final bundle = await JsUiBundle.asset(path: path);
      return bundle.toPlugin();
    });
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}
