import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// JS timer/event-loop 演示：setTimeout / setInterval 与 Promise job pump。
class TimerEventLoopPage extends StatefulWidget {
  const TimerEventLoopPage({super.key});

  @override
  State<TimerEventLoopPage> createState() => _TimerEventLoopPageState();
}

class _TimerEventLoopPageState extends State<TimerEventLoopPage> {
  Quickjs? _quickjs;
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
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create();
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
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

  Future<void> _runTimeout() async {
    await _capture('setTimeout', () async {
      final result = await _requireRuntime().evalAsync(
        'const value = await new Promise((resolve) => '
        'setTimeout(() => resolve(42), 5000));'
        'return value;',
      );
      _appendLog('setTimeout resolve => $result');
    });
  }

  Future<void> _runClearTimeout() async {
    await _capture('clearTimeout', () async {
      final result = await _requireRuntime().evalAsync(
        'let called = false;'
        'const id = setTimeout(() => { called = true; }, 10);'
        'clearTimeout(id);'
        'await new Promise((resolve) => setTimeout(resolve, 20));'
        'return called;',
      );
      _appendLog('clearTimeout 后 callback 是否执行 => $result');
    });
  }

  Future<void> _runInterval() async {
    await _capture('setInterval', () async {
      final result = await _requireRuntime().evalAsync(
        'let count = 0;'
        'await new Promise((resolve) => {'
        '  const id = setInterval(() => {'
        '    count++;'
        '    if (count === 3) {'
        '      clearInterval(id);'
        '      resolve();'
        '    }'
        '  }, 1000);'
        '});'
        'return count;',
      );
      _appendLog('setInterval count => $result');
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
      appBar: AppBar(title: const Text('Timer 与事件循环')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('JS timer 会驱动 Promise job pump，需要通过 evalAsync await。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runTimeout,
                  child: const Text('运行 setTimeout(5秒)'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runClearTimeout,
                  child: const Text('运行 clearTimeout'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runInterval,
                  child: const Text('运行 setInterval(3秒)'),
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
                    ? const Center(child: Text('点击按钮查看 timer 调用结果'))
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
