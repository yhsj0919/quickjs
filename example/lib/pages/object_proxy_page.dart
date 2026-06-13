import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class ObjectProxyPage extends StatefulWidget {
  const ObjectProxyPage({super.key});

  @override
  State<ObjectProxyPage> createState() => _ObjectProxyPageState();
}

class _ObjectProxyPageState extends State<ObjectProxyPage> {
  Quickjs? _quickjs;
  QuickjsObjectHandle? _userHandle;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建 runtime...';
      _log.clear();
      _userHandle = null;
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create();
      final userHandle = await quickjs.bindObject(
        'user',
        QuickjsObjectProxy(
          properties: const {'name': 'Tom', 'role': 'admin'},
          methods: {
            'greet': (args) => '你好 ${args.single}，我是 Tom',
            'save': (_) async => '已保存',
          },
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _userHandle = userHandle;
        _busy = false;
        _status = 'runtime 已就绪（${quickjs.quickjsVersion}）';
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

  Future<void> _readProperties() async {
    await _capture('读取属性', () async {
      final result = await _requireRuntime().eval(
        'user.name + ":" + user.role',
      );
      _appendLog('user.name:user.role => $result');
    });
  }

  Future<void> _callMethods() async {
    await _capture('调用方法', () async {
      final result = await _requireRuntime().evalAsync('''
const greeting = await user.greet('Jerry');
const saved = await user.save();
return greeting + ':' + saved;
''');
      _appendLog('user.greet/save => $result');
    });
  }

  Future<void> _checkReadonly() async {
    await _capture('检查只读属性', () async {
      final result = await _requireRuntime().eval(
        'Reflect.set(user, "name", "Jerry") + ":" + user.name',
      );
      _appendLog('Reflect.set(user.name) => $result');
    });
  }

  Future<void> _disposeProxy() async {
    await _capture('释放对象代理', () async {
      final handle = _userHandle;
      if (handle == null) {
        throw JsRuntimeClosedException('QuickJS object proxy is not ready');
      }
      await handle.dispose();
      _appendLog('对象代理已释放');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _userHandle = null;
      });
    });
  }

  Future<void> _capture(String label, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '正在执行：$label';
    });

    try {
      await action();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$label 已完成';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$label 捕获到 ${error.runtimeType}';
        _log.insert(0, '$label => $error');
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

  void _appendLog(String message) {
    if (!mounted || _disposed) {
      return;
    }
    setState(() {
      _log.insert(0, message);
    });
  }

  @override
  void dispose() {
    _disposed = true;
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    _userHandle = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null && _userHandle != null;

    return Scaffold(
      appBar: AppBar(title: const Text('对象代理')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('使用 bindObject 绑定 Dart 对象代理，暴露只读属性和 Promise 方法。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _readProperties,
                  child: const Text('读取属性'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _callMethods,
                  child: const Text('调用方法'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _checkReadonly,
                  child: const Text('检查只读'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _disposeProxy,
                  child: const Text('释放对象代理'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重新创建 runtime'),
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
                    ? const Center(child: Text('点击按钮查看对象代理结果'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Text(_log[index]),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
