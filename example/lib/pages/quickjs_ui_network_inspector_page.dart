import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiNetworkInspectorPage extends StatefulWidget {
  const QuickjsUiNetworkInspectorPage({super.key});

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
      devOptions: const QuickjsUiDevOptions(
        logDiff: false,
        logResources: true,
      ),
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
        title: const Text('QuickJS UI 网络调试'),
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
              loadingBuilder: (_) => const Center(
                child: CircularProgressIndicator(),
              ),
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
