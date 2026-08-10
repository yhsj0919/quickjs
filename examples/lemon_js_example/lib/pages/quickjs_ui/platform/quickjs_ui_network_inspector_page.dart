import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 网络调试 Demo：bundle 网络加载请求列表、缓存命中、耗时与 Inspector 网络面板。
class QuickjsUiNetworkInspectorPage extends StatefulWidget {
  const QuickjsUiNetworkInspectorPage({super.key});

  /// 远程入口脚本的 URL（需先启动本地静态文件服务器）。
  static final Uri url = Uri.parse(
    'http://127.0.0.1:8765/bundle_counter/pages/main.mjs',
  );

  @override
  State<QuickjsUiNetworkInspectorPage> createState() =>
      _QuickjsUiNetworkInspectorPageState();
}

class _QuickjsUiNetworkInspectorPageState
    extends State<QuickjsUiNetworkInspectorPage> {
  late final QuickjsUiInspector _inspector;
  late final QuickjsUiController _controller;

  @override
  void initState() {
    super.initState();
    _inspector = QuickjsUiInspector();
    _controller = QuickjsUiController(
      devOptions: const QuickjsUiDevOptions(logDiff: false, logResources: true),
      inspector: _inspector,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('网络请求调试'),
        actions: <Widget>[
          IconButton(
            tooltip: '重新加载',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: QuickjsUiView.network(
              url: QuickjsUiNetworkInspectorPage.url,
              controller: _controller,
              initialProps: const <String, Object?>{
                'title': '网络调试',
                'initialCount': 3,
              },
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  '网络页面加载失败：$error\n'
                  '请先运行 quickjs_ui_dev_server.dart',
                ),
              ),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: QuickjsUiInspectorPanel(
              controller: _controller,
              inspector: _inspector,
            ),
          ),
        ],
      ),
    );
  }
}
