import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 网络能力 Demo：注入 [FetchFeatures] 与 Axios，在 JS 页面内请求远程 JSON。
class JsUiNetworkCapabilityPage extends StatefulWidget {
  const JsUiNetworkCapabilityPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/network_capability_page.mjs';

  /// 允许访问的远程 API 源（用于 Fetch features 白名单）。
  static const String _apiOrigin = 'https://jsonplaceholder.typicode.com';

  /// 传给 JS 页面根组件的初始 props（含默认 API URL）。
  static const Map<String, Object?> _initialProps = <String, Object?>{
    'apiUrl': 'https://jsonplaceholder.typicode.com/posts?_limit=5',
  };

  @override
  State<JsUiNetworkCapabilityPage> createState() =>
      _JsUiNetworkCapabilityPageState();
}

/// 创建带源白名单的 Axios features，并管理 [JsUiController] 生命周期。
class _JsUiNetworkCapabilityPageState extends State<JsUiNetworkCapabilityPage> {
  late final JsUiController _controller;

  /// 业务 JS 能力：限制只能访问 [_apiOrigin] 的 Axios + Fetch features。
  late final List<JsFeatures> _features;
  final String _status =
      'Fetch/XHR + Axios 1.6.2 已就绪，JS 页面将通过 axios 请求 ${JsUiNetworkCapabilityPage._apiOrigin}';

  @override
  void initState() {
    super.initState();
    _controller = JsUiController(
      onConsole: (event) {
        debugPrint('quickjs_ui console.${event.level.name}: ${event.text}');
      },
    );
    _features = <JsFeatures>[
      AxiosFeatures(
        allowedOrigins: const <String>{JsUiNetworkCapabilityPage._apiOrigin},
        maxRedirects: 5,
        maxRequestBytes: 1024 * 1024,
        maxResponseBytes: 10 * 1024 * 1024,
        timeout: const Duration(seconds: 15),
        defaultHeaders: const <String, String>{
          'x-quickjs-example': 'from-features',
        },
      ),
    ];
  }

  @override
  void dispose() {
    unawaited(
      _controller
          .lifecycle(JsUiLifecycle.dispose, render: false)
          .whenComplete(_controller.dispose),
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('网络请求能力')),
      body: Column(
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Align(
                alignment: Alignment.centerLeft,
                child: Text(_status),
              ),
            ),
          ),
          Expanded(
            child: JsUiView.asset(
              path: JsUiNetworkCapabilityPage.path,
              controller: _controller,
              features: _features,
              initialProps: JsUiNetworkCapabilityPage._initialProps,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              errorBuilder: (_, error) => Padding(
                padding: const EdgeInsets.all(16),
                child: SelectableText(
                  'QuickJS UI network capability error: $error',
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
