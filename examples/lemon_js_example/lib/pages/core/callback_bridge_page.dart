import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

/// Promise-based Dart callback 演示：JS await 调用 Dart 函数。
class CallbackBridgePage extends StatefulWidget {
  const CallbackBridgePage({super.key});

  @override
  State<CallbackBridgePage> createState() => _CallbackBridgePageState();
}

class _CallbackBridgePageState extends State<CallbackBridgePage> {
  JsEngine? _engine;
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
    });

    try {
      final previous = _engine;
      _engine = null;
      await previous?.dispose();

      final engine = await JsEngine.create();
      await _bindCallbacks(engine);
      if (!mounted || _disposed) {
        await engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
        _busy = false;
        _status = 'runtime 已就绪（${engine.engineVersion}）';
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

  Future<void> _bindCallbacks(JsEngine engine) async {
    await engine.injectFunction('hostAdd', (args) {
      final left = args[0] as num;
      final right = args[1] as num;
      _appendLog('Dart hostAdd($left, $right)');
      return left + right;
    });
    await engine.injectFunction('hostFail', (_) {
      _appendLog('Dart hostFail()');
      throw StateError('hostFail from Dart');
    });
  }

  Future<void> _runResolve() async {
    await _capture('resolve', () async {
      final result = await _requireRuntime().run(
        'return await hostAdd(20, 22);',
      );
      _appendLog('JS await hostAdd(20, 22) => $result');
    });
  }

  Future<void> _runReject() async {
    await _capture('reject', () async {
      await _requireRuntime().run('return await hostFail();');
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
        _log.insert(0, '$label => ${_describeError(error)}');
      });
    }
  }

  JsEngine _requireRuntime() {
    final engine = _engine;
    if (engine == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return engine;
  }

  void _appendLog(String message) {
    if (!mounted || _disposed) {
      return;
    }
    setState(() {
      _log.insert(0, message);
    });
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
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _engine != null;

    return Scaffold(
      appBar: AppBar(title: const Text('回调桥接')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('JS 调用 Dart callback 时返回 Promise，需要通过 run await。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runResolve,
                  child: const Text('运行 hostAdd'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runReject,
                  child: const Text('运行 hostFail'),
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
                    ? const Center(child: Text('点击按钮查看 callback 调用结果'))
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
