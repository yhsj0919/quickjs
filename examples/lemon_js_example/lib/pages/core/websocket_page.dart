import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

class WebSocketPage extends StatefulWidget {
  const WebSocketPage({super.key});

  @override
  State<WebSocketPage> createState() => _WebSocketPageState();
}

class _WebSocketPageState extends State<WebSocketPage> {
  static const _defaultEchoUrl = 'wss://ws.postman-echo.com/raw';

  JsEngine? _engine;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建 WebSocket runtime...';
  final List<String> _log = <String>[];
  late final TextEditingController _urlController;

  @override
  void initState() {
    super.initState();
    _urlController = TextEditingController(text: _defaultEchoUrl);
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    final url = _currentUrl;
    final origin = _originForWebSocketUrl(url);
    setState(() {
      _busy = true;
      _status = '正在创建 WebSocket runtime...';
      _log.clear();
    });
    try {
      if (origin == null) {
        throw ArgumentError.value(
          url,
          'url',
          'must be an absolute ws:// or wss:// URL',
        );
      }
      final previous = _engine;
      _engine = null;
      await previous?.dispose();
      final engine = await JsEngine.create(
        features: <JsFeatures>[
          WebSocketFeatures(
            allowedOrigins: <String>{origin},
            connectTimeout: const Duration(seconds: 15),
          ),
        ],
      );
      if (!mounted || _disposed) {
        await engine.dispose();
        return;
      }
      setState(() {
        _engine = engine;
        _busy = false;
        _status = 'runtime 已就绪：WebSocket 全局对象已安装，允许 $origin';
      });
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _busy = false;
        _status = '创建失败：$error';
      });
    }
  }

  Future<void> _runEcho() async {
    await _capture('文本回显', () async {
      final encodedUrl = jsonEncode(_currentUrl);
      final result = await _requireRuntime().runRaw('''
return await new Promise((resolve, reject) => {
  const ws = new WebSocket($encodedUrl);
  const started = Date.now();
  ws.onopen = () => ws.send('quickjs websocket');
  ws.onmessage = (event) => {
    ws.close(1000, 'done');
    resolve(`PASS message=\${event.data}, elapsedMs=\${Date.now() - started}`);
  };
  ws.onerror = (event) => reject(new Error(event.message || 'websocket error'));
  ws.onclose = (event) => {
    if (event.code !== 1000 && event.code !== 1005) {
      reject(new Error(`closed early: \${event.code} \${event.reason}`));
    }
  };
});
''', name: 'example:websocket-echo.js');
      _log.insert(0, result);
      _status = '文本回显完成';
    });
  }

  Future<void> _runProtocolCheck() async {
    await _capture('协议检查', () async {
      final result = await _requireRuntime().run('''
return [
  typeof WebSocket,
  WebSocket.CONNECTING,
  WebSocket.OPEN,
  WebSocket.CLOSING,
  WebSocket.CLOSED
].join('/');
''', name: 'example:websocket-protocol.js');
      _log.insert(0, '协议 => $result');
      _status = 'WebSocket 常量可用';
    });
  }

  Future<void> _runPolicyCheck() async {
    await _capture('策略检查', () async {
      try {
        await _requireRuntime().run('''
return await new Promise((resolve, reject) => {
  const ws = new WebSocket('wss://example.com/socket');
  ws.onopen = () => resolve('unexpected open');
  ws.onerror = (event) => reject(new Error(event.message || 'blocked'));
});
''', name: 'example:websocket-policy.js');
        _log.insert(0, '策略 => 意外连接成功');
      } catch (error) {
        _log.insert(0, '策略 => 已拦截：${_describeError(error)}');
      }
      _status = 'Origin 白名单已生效';
    });
  }

  Future<void> _capture(String name, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '正在运行：$name';
    });
    try {
      await action();
      if (!mounted || _disposed) return;
      setState(() => _busy = false);
    } catch (error) {
      if (!mounted || _disposed) return;
      setState(() {
        _busy = false;
        _status = '$name 失败：${_describeError(error)}';
        _log.insert(0, '$name => ${_describeError(error)}');
      });
    }
  }

  JsEngine _requireRuntime() {
    final engine = _engine;
    if (engine == null) {
      throw JsRuntimeClosedException('QuickJS runtime 尚未就绪');
    }
    return engine;
  }

  String get _currentUrl => _urlController.text.trim();

  String? _originForWebSocketUrl(String value) {
    final uri = Uri.tryParse(value);
    if (uri == null ||
        (uri.scheme != 'ws' && uri.scheme != 'wss') ||
        uri.host.isEmpty ||
        uri.userInfo.isNotEmpty) {
      return null;
    }
    final defaultPort = uri.scheme == 'ws' ? 80 : 443;
    final port = uri.hasPort && uri.port != defaultPort ? ':${uri.port}' : '';
    return '${uri.scheme}://${uri.host}$port';
  }

  String _describeError(Object error) {
    if (error is JsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_engine?.dispose() ?? Future<void>.value());
    _engine = null;
    _urlController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _engine != null;
    return Scaffold(
      appBar: AppBar(title: const Text('WebSocket 通信')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(_status),
            const SizedBox(height: 8),
            const Text('WebSocketFeatures 会安装 globalThis.WebSocket。'),
            const SizedBox(height: 12),
            TextField(
              controller: _urlController,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: '回显 WebSocket 地址',
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) {
                if (!_busy) unawaited(_createRuntime());
              },
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: <Widget>[
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runEcho,
                  child: const Text('运行回显'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runProtocolCheck,
                  child: const Text('检查协议'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runPolicyCheck,
                  child: const Text('检查策略'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Expanded(
              child: DecoratedBox(
                decoration: BoxDecoration(
                  border: Border.all(color: Theme.of(context).dividerColor),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: _log.isEmpty
                    ? const Center(child: Text('运行一个 WebSocket 场景'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: SelectableText(_log[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
