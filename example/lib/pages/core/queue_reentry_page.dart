import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 执行队列演示：验证 FIFO、dispose 取消队列、排队 timeout。
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
      await quickjs.eval('globalThis.queue = ""');
      final results = await Future.wait([
        // 100 个 eval 同时提交，期望底层严格按提交顺序串行执行。
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
      // 这些请求应被 dispose 取消，不能继续进入 runtime 修改 globalThis。
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

  Future<void> _runQueuedTimeoutTest() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在验证排队任务 timeout 取消...';
      _log.clear();
    });

    final running = quickjs.eval('''
      (() => {
        const start = Date.now();
        while (Date.now() - start < 300) {}
        return "running finished";
      })();
    ''');
    final queued = quickjs.eval(
      // timeout 小于前一个任务耗时，因此它应在队列中被取消。
      'globalThis.queuedTimeout = "should not run"',
      timeout: const Duration(milliseconds: 30),
    );

    try {
      final queuedResult = await queued.then(
        (value) => '排队请求意外执行：$value',
        onError: (Object error) => '排队请求已 timeout：${error.runtimeType}',
      );
      final runningResult = await running;
      final marker = await quickjs.eval('globalThis.queuedTimeout');

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = marker == 'undefined'
            ? '排队 timeout 已取消任务，runtime 仍可继续使用'
            : '排队 timeout 测试异常';
        _log
          ..add('正在执行的 eval：$runningResult')
          ..add(queuedResult)
          ..add('排队任务副作用：$marker');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '排队 timeout 测试失败：$error';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // 页面级 runtime 退出时必须释放，保持 example 页面之间互不污染。
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
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _runQueuedTimeoutTest,
                  child: const Text('验证 timeout 取消队列'),
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
