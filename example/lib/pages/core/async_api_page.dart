import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 异步 API 演示：FIFO eval、Promise 求值和 runtime 生命周期错误。
class AsyncApiPage extends StatefulWidget {
  const AsyncApiPage({super.key});

  @override
  State<AsyncApiPage> createState() => _AsyncApiPageState();
}

class _AsyncApiPageState extends State<AsyncApiPage> {
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
      // 重新创建前先释放旧 runtime，避免 example 页面里残留状态。
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
        _status = 'runtime 已就绪（${quickjs.quickjsVersion}）';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _status = '创建失败：$error';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _runQueuedEvals() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '已提交 3 个 eval 请求...';
      _log.clear();
    });

    final futures = <Future<String>>[
      // 三个请求立即提交，底层应按 FIFO 串行进入同一个 runtime。
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "A"'),
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "B"'),
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "C"'),
    ];

    try {
      final results = await Future.wait(futures);
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        for (var index = 0; index < results.length; index += 1) {
          _log.add('请求 ${index + 1}：${results[index]}');
        }
        _status = results.join(' → ') == 'A → AB → ABC'
            ? 'FIFO 顺序验证通过'
            : 'FIFO 返回结果与预期不一致';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _log.add('队列执行失败：${_describeError(error)}');
        _status = '队列执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _runAsyncEvaluation() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在等待 JavaScript Promise...';
    });

    try {
      final result = await quickjs.evalAsync('''
await new Promise((resolve) => setTimeout(resolve, 100));
return { answer: 6 * 7, state: "resolved" };
''', name: 'example:async-api.js');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _log.add('evalAsync：$result');
        _status = 'JavaScript Promise 已完成';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _log.add('evalAsync 失败：${_describeError(error)}');
        _status = 'evalAsync 执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _busy = false;
        });
      }
    }
  }

  Future<void> _disposeRuntime() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在销毁 runtime...';
    });

    try {
      await quickjs.dispose();
      // 销毁后继续 eval 应返回 closed error，用于展示生命周期语义。
      await quickjs.eval('1 + 1');
      if (mounted && !_disposed) {
        _log.add('销毁后 eval 未返回预期错误');
      }
    } catch (error) {
      if (mounted && !_disposed) {
        _log.add('销毁后继续 eval：${_describeError(error)}');
      }
    }

    if (!mounted || _disposed) {
      return;
    }

    setState(() {
      _quickjs = null;
      _busy = false;
      _status = 'runtime 已销毁';
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
    // 页面退出时释放 runtime；不等待释放完成以免阻塞 Navigator pop。
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('异步 API')),
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
                  onPressed: _busy || !hasRuntime ? null : _runQueuedEvals,
                  child: const Text('验证 FIFO eval'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _runAsyncEvaluation,
                  child: const Text('等待 Promise'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _disposeRuntime,
                  child: const Text('销毁 runtime'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('创建 runtime'),
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
                    ? const Center(child: Text('点击按钮验证异步 API 行为'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_log[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
