import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiNetworkCapabilityPage extends StatefulWidget {
  const QuickjsUiNetworkCapabilityPage({super.key});

  static const String path = 'assets/quickjs_ui/network_capability_page.mjs';
  static const String _apiOrigin = 'https://jsonplaceholder.typicode.com';
  static const Map<String, Object?> _initialProps = <String, Object?>{
    'apiUrl': 'https://jsonplaceholder.typicode.com/posts?_limit=5',
  };

  @override
  State<QuickjsUiNetworkCapabilityPage> createState() =>
      _QuickjsUiNetworkCapabilityPageState();
}

class _QuickjsUiNetworkCapabilityPageState
    extends State<QuickjsUiNetworkCapabilityPage> {
  late final QuickjsUiController _controller;
  List<QuickjsHostMount>? _mounts;
  String _status = '正在准备 Fetch/XHR + Axios runtime...';

  @override
  void initState() {
    super.initState();
    _controller = QuickjsUiController(
      onConsole: (event) {
        debugPrint('quickjs_ui console.${event.level.name}: ${event.text}');
      },
    );
    unawaited(_prepareMounts());
  }

  @override
  void dispose() {
    unawaited(
      _controller
          .lifecycle('dispose', render: false)
          .whenComplete(_controller.dispose),
    );
    super.dispose();
  }

  Future<void> _prepareMounts() async {
    try {
      final axiosSource = await rootBundle.loadString('assets/js/axios.js');
      if (!mounted) {
        return;
      }
      setState(() {
        _mounts = <QuickjsHostMount>[
          QuickjsFetchMount(
            allowedOrigins: const <String>{
              QuickjsUiNetworkCapabilityPage._apiOrigin,
            },
            maxRedirects: 5,
            maxRequestBytes: 1024 * 1024,
            maxResponseBytes: 10 * 1024 * 1024,
            timeout: const Duration(seconds: 15),
            defaultHeaders: const <String, String>{
              'x-quickjs-example': 'from-mount',
            },
          ),
          QuickjsHostMount(
            name: 'axios',
            environmentPatches: <QuickjsHostScript>[
              QuickjsHostScript.js(
                name: 'quickjs_ui:axios.js',
                source: axiosSource,
                globals: const <String>['axios'],
              ),
            ],
          ),
        ];
        _status =
            'Fetch/XHR + Axios 1.6.2 已就绪，JS 页面将通过 axios 请求 ${QuickjsUiNetworkCapabilityPage._apiOrigin}';
      });
    } catch (error) {
      if (!mounted) {
        return;
      }
      setState(() {
        _status = '准备 Axios runtime 失败：$error';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final mounts = _mounts;
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 网络能力')),
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
            child: mounts == null
                ? const Center(child: CircularProgressIndicator())
                : QuickjsUiView.asset(
                    path: QuickjsUiNetworkCapabilityPage.path,
                    controller: _controller,
                    mounts: mounts,
                    initialProps: QuickjsUiNetworkCapabilityPage._initialProps,
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
