import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 资源限制演示：验证 memoryLimitBytes / stackLimitBytes 的错误语义。
class MemoryLimitPage extends StatefulWidget {
  const MemoryLimitPage({super.key});

  @override
  State<MemoryLimitPage> createState() => _MemoryLimitPageState();
}

class _MemoryLimitPageState extends State<MemoryLimitPage> {
  static const int _memoryLimitBytes = 256 * 1024;
  static const int _stackLimitBytes = 64 * 1024;

  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建受限 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建受限 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          memoryLimitBytes: _memoryLimitBytes,
          stackLimitBytes: _stackLimitBytes,
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status =
            'runtime 已就绪：memoryLimitBytes=$_memoryLimitBytes, '
            'stackLimitBytes=$_stackLimitBytes';
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

  Future<void> _runOversizedAllocation() async {
    setState(() {
      _busy = true;
      _status = '正在触发超限分配...';
    });

    try {
      await _requireRuntime().eval(
        'new Array(1000000).fill("quickjs").join("")',
      );
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '超限分配未抛出异常';
        _log.insert(0, 'oversized allocation => no error');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '捕获到 ${error.runtimeType}';
        _log.insert(0, 'oversized allocation => ${_describeError(error)}');
      });
    }
  }

  Future<void> _runSmallEvaluation() async {
    setState(() {
      _busy = true;
      _status = '正在执行小脚本...';
    });

    try {
      final result = await _requireRuntime().eval('1 + 1');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '小脚本执行成功：$result';
        _log.insert(0, '1 + 1 => $result');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '小脚本执行失败：${error.runtimeType}';
        _log.insert(0, '1 + 1 => ${_describeError(error)}');
      });
    }
  }

  Future<void> _runDeepRecursion() async {
    setState(() {
      _busy = true;
      _status = '正在触发递归栈溢出...';
    });

    try {
      await _requireRuntime().eval(
        'function recurse() { return recurse() + 1; } recurse();',
      );
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '递归栈溢出未抛出异常';
        _log.insert(0, 'deep recursion => no error');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '捕获到 ${error.runtimeType}';
        _log.insert(0, 'deep recursion => ${_describeError(error)}');
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
      appBar: AppBar(title: const Text('资源限制')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'memoryLimitBytes=262144 bytes (256 KiB), '
              'stackLimitBytes=65536 bytes (64 KiB)',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _runOversizedAllocation,
                  child: const Text('触发 JsOutOfMemoryException'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runDeepRecursion,
                  child: const Text('触发 JsStackOverflowException'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runSmallEvaluation,
                  child: const Text('执行 1 + 1'),
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
                    ? const Center(child: Text('点击按钮查看资源限制行为'))
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
