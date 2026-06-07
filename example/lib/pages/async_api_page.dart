import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

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
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "A"'),
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "B"'),
      quickjs.eval('globalThis.queue = (globalThis.queue || "") + "C"'),
    ];

    for (var index = 0; index < futures.length; index += 1) {
      try {
        final result = await futures[index];
        if (!mounted || _disposed) {
          return;
        }
        setState(() {
          _log.add('请求 ${index + 1}：$result');
        });
      } catch (error) {
        if (!mounted || _disposed) {
          return;
        }
        setState(() {
          _log.add('请求 ${index + 1} 失败：$error');
        });
      }
    }

    if (mounted && !_disposed) {
      setState(() {
        _busy = false;
        _status = '队列已执行完毕';
      });
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

    await quickjs.dispose();
    try {
      await quickjs.eval('1 + 1');
    } catch (error) {
      _log.add('销毁后继续 eval：${error.runtimeType}');
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
                  child: const Text('执行排队 eval'),
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
