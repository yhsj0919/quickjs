import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class QueueReentryPage extends StatefulWidget {
  const QueueReentryPage({super.key});

  @override
  State<QueueReentryPage> createState() => _QueueReentryPageState();
}

class _QueueReentryPageState extends State<QueueReentryPage> {
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
      if (previous != null) {
        await previous.dispose();
      }

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

  Future<void> _runHundredQueuedEvals() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在提交 100 个并发 eval...';
      _log.clear();
    });

    try {
      final results = await Future.wait([
        for (var i = 0; i < 100; i += 1)
          quickjs.eval(
            'globalThis.queue = (globalThis.queue || "") + "$i,"; globalThis.queue',
          ),
      ]);

      var expected = '';
      var stable = true;
      for (var i = 0; i < results.length; i += 1) {
        expected += '$i,';
        if (results[i] != expected) {
          stable = false;
          break;
        }
      }

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = stable ? '100 次 eval 已按 FIFO 顺序完成' : 'FIFO 顺序异常';
        _log
          ..add('首个结果：${results.first}')
          ..add('最后结果长度：${results.last.length}')
          ..add('最后结果尾部：${results.last.substring(results.last.length - 12)}');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '100 次队列测试失败：$error';
      });
    }
  }

  Future<void> _runDisposePriorityTest() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在验证 dispose 取消排队任务...';
      _log.clear();
    });

    final running = quickjs.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 300) {}
        return "running finished";
      })();
    ''');
    final queued = [
      quickjs.eval('globalThis.disposeQueue = "A"'),
      quickjs.eval('globalThis.disposeQueue = "B"'),
    ];
    final queuedResults = Future.wait([
      for (var i = 0; i < queued.length; i += 1)
        queued[i].then(
          (value) => '排队请求 ${i + 1} 意外执行：$value',
          onError: (Object error) => '排队请求 ${i + 1} 已取消：${error.runtimeType}',
        ),
    ]);

    final disposeFuture = quickjs.dispose();
    try {
      final runningResult = await running;
      final cancelled = await queuedResults;
      await disposeFuture;

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _quickjs = null;
        _busy = false;
        _status = 'dispose 已完成，排队任务没有继续进入 runtime';
        _log
          ..add('正在执行的 eval：$runningResult')
          ..addAll(cancelled);
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'dispose 队列测试失败：$error';
      });
    }
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
      appBar: AppBar(title: const Text('执行队列与重入策略')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _runHundredQueuedEvals,
                  child: const Text('运行 100 次 FIFO 测试'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _runDisposePriorityTest,
                  child: const Text('验证 dispose 取消队列'),
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
                child: ListView.builder(
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
