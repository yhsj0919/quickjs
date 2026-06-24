import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs/quickjs.dart';

/// Loads one pre-bundled npm asset and calls a selected ESM export.
class NpmBundlePage extends StatefulWidget {
  const NpmBundlePage({super.key});

  @override
  State<NpmBundlePage> createState() => _NpmBundlePageState();
}

class _NpmBundlePageState extends State<NpmBundlePage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  int _callCount = 0;
  String _status = '正在加载 npm bundle asset...';
  String _result = '尚未调用 compareValues()';

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在加载 npm bundle asset...';
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      _callCount = 0;
      await previous?.dispose();

      final source = await rootBundle.loadString('assets/js/npm_bundle.mjs');
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[
            QuickjsHostModule.esModule(
              specifier: 'example/npm-bundle',
              source: source,
            ),
          ],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'bundle 已注册：example/npm-bundle';
        _result = '尚未调用 compareValues()';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '加载失败：$error';
      });
    }
  }

  Future<void> _callCompareValues() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在调用 compareValues()...';
    });
    try {
      await quickjs.evalModule('''
import { bundledDependency, compareValues } from 'example/npm-bundle';
globalThis.npmBundleResult = bundledDependency + '/' + [
  compareValues({ answer: 42 }, { answer: 42 }),
  compareValues({ answer: 42 }, { answer: 7 })
].join('/');
''', name: 'example/call-npm-bundle-${++_callCount}.mjs');
      final result = await quickjs.eval('globalThis.npmBundleResult');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'compareValues() 调用完成';
        _result = result;
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '调用失败：$error';
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
      appBar: AppBar(title: const Text('NPM Bundle')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'asset → QuickjsRuntimeOptions.modules → '
              "import { compareValues } from 'example/npm-bundle'",
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callCompareValues,
                  child: const Text('调用 compareValues()'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重新加载 bundle'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SelectableText('result: $_result'),
          ],
        ),
      ),
    );
  }
}
