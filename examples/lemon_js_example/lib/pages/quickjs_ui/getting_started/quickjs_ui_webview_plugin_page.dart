import 'package:flutter/material.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';
import 'package:lemon_js_ui_webview/lemon_js_ui_webview.dart';

/// WebView 插件 Demo：网页方法调用与链式 DOM 查询隔离。
class JsUiWebViewPluginPage extends StatefulWidget {
  const JsUiWebViewPluginPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/webview_plugin_page.mjs';

  @override
  State<JsUiWebViewPluginPage> createState() => _JsUiWebViewPluginPageState();
}

class _JsUiWebViewPluginPageState extends State<JsUiWebViewPluginPage> {
  late final JsUiWebViewPlugin _webViewPlugin;

  @override
  void initState() {
    super.initState();
    _webViewPlugin = JsUiWebViewPlugin();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('WebView 插件')),
      body: JsUiView.asset(
        path: JsUiWebViewPluginPage.path,
        uiPlugins: <JsUiPlugin>[_webViewPlugin.plugin],
        loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
        errorBuilder: (_, error) => Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI WebView plugin error: $error'),
        ),
      ),
    );
  }
}
