import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class FunctionHandlePage extends StatefulWidget {
  const FunctionHandlePage({super.key});

  @override
  State<FunctionHandlePage> createState() => _FunctionHandlePageState();
}

class _FunctionHandlePageState extends State<FunctionHandlePage> {
  Quickjs? _quickjs;
  QuickjsFunctionHandle? _add;
  QuickjsFunctionHandle? _asyncAdd;
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
      _add = null;
      _asyncAdd = null;
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create();
      final add = await quickjs.evaluateHandle('''
function add(a, b) {
  return a + b;
}
add
''');
      final asyncAdd = await quickjs.evaluateHandle('''
async (a, b) => {
  await new Promise((resolve) => setTimeout(resolve, 1));
  return a + b;
}
''');
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _add = add;
        _asyncAdd = asyncAdd;
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

  Future<void> _callAdd() async {
    await _capture('handle.call', () async {
      final result = await _requireHandle().call([20, 22]);
      _appendLog('add.call([20, 22]) => $result');
    });
  }

  Future<void> _callAsyncAdd() async {
    await _capture('handle.callAsync', () async {
      final result = await _requireAsyncHandle().callAsync([20, 22]);
      _appendLog('asyncAdd.callAsync([20, 22]) => $result');
    });
  }

  Future<void> _runTimeout() async {
    await _capture('handle timeout', () async {
      final loop = await _requireRuntime().evaluateHandle(
        '() => { while (true) {} }',
      );
      await loop.call(const [], timeout: const Duration(milliseconds: 50));
    });
  }

  Future<void> _disposeHandles() async {
    await _capture('handle.dispose', () async {
      final add = _requireHandle();
      final asyncAdd = _requireAsyncHandle();
      await add.dispose();
      await asyncAdd.dispose();
      _appendLog('function handles disposed');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _add = null;
        _asyncAdd = null;
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

  QuickjsFunctionHandle _requireHandle() {
    final handle = _add;
    if (handle == null) {
      throw JsRuntimeClosedException('QuickJS function handle is not ready');
    }
    return handle;
  }

  QuickjsFunctionHandle _requireAsyncHandle() {
    final handle = _asyncAdd;
    if (handle == null) {
      throw JsRuntimeClosedException(
        'QuickJS async function handle is not ready',
      );
    }
    return handle;
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
    _add = null;
    _asyncAdd = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null && _add != null && _asyncAdd != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Function Handle')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              '使用 evaluateHandle 获取 JS function，并通过 handle.call 重复调用。',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callAdd,
                  child: const Text('调用 add handle'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _callAsyncAdd,
                  child: const Text('Call async handle'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runTimeout,
                  child: const Text('触发 timeout'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _disposeHandles,
                  child: const Text('Dispose handles'),
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
                    ? const Center(child: Text('点击按钮查看 function handle 结果'))
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
