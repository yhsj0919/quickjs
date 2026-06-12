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

      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          moduleLoader: (name) => switch (name) {
            'example/dep.mjs' => 'export const value = 40;',
            'shared/add.mjs' => 'export function add(a, b) { return a + b; }',
            'shared/counter.mjs' =>
              'globalThis.moduleImportCount = (globalThis.moduleImportCount || 0) + 1;'
                  'export const count = globalThis.moduleImportCount;',
            'common/dep.js' => 'exports.value = 40;',
            'shared/add.js' =>
              'module.exports = function add(a, b) { return a + b; };',
            'shared/counter.js' =>
              'globalThis.commonJsImportCount = (globalThis.commonJsImportCount || 0) + 1;'
                  'exports.count = globalThis.commonJsImportCount;',
            _ => null,
          },
        ),
      );
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

  Future<void> _runModuleImport() async {
    await _capture('module import/cache', () async {
      await _requireRuntime().evalModule('''
import { value } from './dep.mjs';
import { add } from '../shared/add.mjs';
import { count } from '../shared/counter.mjs';
globalThis.moduleImportResult = add(value, 2);
globalThis.moduleImportFirstCount = count;
''', name: 'example/main-${++_moduleRunCount}.mjs');
      await _requireRuntime().evalModule('''
import { count } from './counter.mjs';
globalThis.moduleImportSecondCount = count;
''', name: 'shared/second-${++_moduleRunCount}.mjs');
      final value = await _requireRuntime().eval(
        'globalThis.moduleImportResult + "/" + '
        'globalThis.moduleImportFirstCount + "/" + '
        'globalThis.moduleImportSecondCount',
      );
      _appendLog('relative import/cache => result/first/second = $value');
    });
  }

  Future<void> _runCommonJs() async {
    await _capture('CommonJS require/cache', () async {
      await _requireRuntime().evalCommonJs('''
const dep = require('./dep.js');
const add = require('../shared/add.js');
const counter = require('../shared/counter.js');
globalThis.commonJsResult = add(dep.value, 2);
globalThis.commonJsFirstCount = counter.count;
exports.value = globalThis.commonJsResult;
''', name: 'common/main-${++_moduleRunCount}.js');
      await _requireRuntime().evalCommonJs('''
const counter = require('./counter.js');
globalThis.commonJsSecondCount = counter.count;
''', name: 'shared/second-${++_moduleRunCount}.js');
      final value = await _requireRuntime().eval(
        'globalThis.commonJsResult + "/" + '
        'globalThis.commonJsFirstCount + "/" + '
        'globalThis.commonJsSecondCount',
      );
      _appendLog('CommonJS require/cache => result/first/second = $value');
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
      appBar: AppBar(title: const Text('Module')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('执行 ES module、CommonJS、相对路径解析与 runtime module cache。'),
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
                  onPressed: _busy || !hasRuntime ? null : _runModuleImport,
                  child: const Text('Import/cache'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runCommonJs,
                  child: const Text('CommonJS'),
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
