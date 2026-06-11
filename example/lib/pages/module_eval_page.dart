import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

class ModuleEvalPage extends StatefulWidget {
  const ModuleEvalPage({super.key});

  @override
  State<ModuleEvalPage> createState() => _ModuleEvalPageState();
}

class _ModuleEvalPageState extends State<ModuleEvalPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建 runtime...';
  int _moduleRunCount = 0;
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
      _moduleRunCount = 0;
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

  Future<void> _runModule() async {
    await _capture('evalModule', () async {
      final moduleName = 'example-module-${++_moduleRunCount}.mjs';
      final result = await _requireRuntime().evalModule('''
export const answer = 42;
globalThis.moduleAnswer = answer;
''', name: moduleName);
      final value = await _requireRuntime().eval('globalThis.moduleAnswer');
      _appendLog('evalModule($moduleName) => $result, moduleAnswer => $value');
    });
  }

  Future<void> _runModuleError() async {
    await _capture('module error', () async {
      final moduleName = 'module-error-${++_moduleRunCount}.mjs';
      await _requireRuntime().evalModule(
        'throw new Error("module failed");',
        name: moduleName,
      );
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

  Future<void> _copyLog() async {
    if (_log.isEmpty) {
      return;
    }
    await Clipboard.setData(ClipboardData(text: _log.join('\n')));
    if (!mounted || _disposed) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('Log copied')));
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
      appBar: AppBar(title: const Text('ES Module')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              '执行单个 ES module source；import resolver 与 module cache 后续实现。',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runModule,
                  child: const Text('运行 evalModule'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runModuleError,
                  child: const Text('触发 module error'),
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
                    ? const Center(child: Text('点击按钮查看 module 执行结果'))
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Align(
                            alignment: Alignment.centerRight,
                            child: IconButton(
                              tooltip: 'Copy log',
                              onPressed: _copyLog,
                              icon: const Icon(Icons.copy),
                            ),
                          ),
                          Expanded(
                            child: SelectionArea(
                              child: ListView.builder(
                                padding: const EdgeInsets.fromLTRB(
                                  12,
                                  0,
                                  12,
                                  12,
                                ),
                                itemCount: _log.length,
                                itemBuilder: (context, index) =>
                                    SelectableText(_log[index]),
                              ),
                            ),
                          ),
                        ],
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
