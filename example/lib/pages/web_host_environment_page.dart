import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// Web 风格宿主环境示例：最小 browser-like globals。
class WebHostEnvironmentPage extends StatefulWidget {
  const WebHostEnvironmentPage({super.key});

  @override
  State<WebHostEnvironmentPage> createState() => _WebHostEnvironmentPageState();
}

class _WebHostEnvironmentPageState extends State<WebHostEnvironmentPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 Web 宿主环境的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 Web 宿主环境的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          hostEnvironments: <QuickjsHostEnvironment>[
            QuickjsHostEnvironment.web(
              locationHref: 'https://example.com:8443/app?q=1#top',
              userAgent: 'quickjs-example',
            ),
          ],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：Web 宿主环境已显式启用';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '创建失败：$error';
      });
    }
  }

  Future<void> _runDefaultDisabledCheck() async {
    await _capture('默认未启用检查', () async {
      final quickjs = await Quickjs.create();
      try {
        final result = await quickjs.eval('''
[
  typeof window,
  typeof self,
  typeof location,
  typeof navigator,
  typeof localStorage,
  typeof sessionStorage
].join('/')
''');
        _log.insert(0, '默认 runtime => $result');
        _status = '默认 runtime 不暴露 Web 宿主环境';
      } finally {
        await quickjs.dispose();
      }
    });
  }

  Future<void> _runGlobalCheck() async {
    await _capture('全局对象检查', () async {
      final result = await _requireRuntime().eval('''
[
  window === globalThis,
  self === globalThis,
  location.origin,
  location.pathname,
  location.search,
  location.hash,
  navigator.userAgent
].join('\\n')
''');
      _log.insert(0, result);
      _status = 'window / self / location / navigator 可用';
    });
  }

  Future<void> _runStorageCheck() async {
    await _capture('Storage 检查', () async {
      final result = await _requireRuntime().eval('''
localStorage.clear();
sessionStorage.clear();
localStorage.setItem('answer', 42);
sessionStorage.setItem('answer', 7);
[
  localStorage.getItem('answer'),
  sessionStorage.getItem('answer'),
  localStorage.length,
  sessionStorage.length,
  localStorage.key(0)
].join('/')
''');
      _log.insert(0, 'storage => $result');
      _status = '内存版 localStorage / sessionStorage 可用';
    });
  }

  Future<void> _runUrlCheck() async {
    await _capture('URL 检查', () async {
      final result = await _requireRuntime().eval('''
(() => {
  const url = new URL('https://dart.dev/docs?tab=api#top');
  return [
    url.href,
    url.protocol,
    url.hostname,
    url.pathname,
    url.search,
    url.hash
  ].join('\\n');
})()
''');
      _log.insert(0, result);
      _status = '轻量 URL 构造器可用';
    });
  }

  Future<void> _runStopRecovery() async {
    await _capture('stop 后恢复', () async {
      final quickjs = _requireRuntime();
      final running = quickjs
          .eval('while (true) {}')
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await quickjs.stop();
      await running;
      final result = await quickjs.eval(
        'window === globalThis && location.hostname === "example.com"',
      );
      _log.insert(0, 'stop 后 Web 宿主环境可用 => $result');
      _status = 'stop / rebuild 后 Web 宿主环境已重新安装';
    });
  }

  Future<void> _capture(String name, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '正在运行：$name';
    });

    try {
      await action();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$name 失败：${_describeError(error)}';
        _log.insert(0, '$name => ${_describeError(error)}');
      });
    }
  }

  Quickjs _requireRuntime() {
    final quickjs = _quickjs;
    if (quickjs == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return quickjs;
  }

  String _describeError(Object error) {
    if (error is QuickjsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Web 宿主环境')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'QuickjsHostEnvironment.web(locationHref: ..., userAgent: ...)',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runGlobalCheck,
                  child: const Text('检查全局对象'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStorageCheck,
                  child: const Text('检查 Storage'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runUrlCheck,
                  child: const Text('检查 URL'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runDefaultDisabledCheck,
                  child: const Text('验证默认未启用'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStopRecovery,
                  child: const Text('stop 后恢复'),
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
                    ? const Center(child: Text('点击按钮验证 Web 宿主环境行为'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_log[index]),
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
