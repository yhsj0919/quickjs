import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:lemon_js/lemon_js.dart';

/// NPM Bundle Demo：加载 esbuild 打包的单文件 asset，注册为 ES module，
/// 并调用选定的导出方法。
class NpmBundlePage extends StatefulWidget {
  const NpmBundlePage({super.key});

  @override
  State<NpmBundlePage> createState() => _NpmBundlePageState();
}

class _NpmBundlePageState extends State<NpmBundlePage> {
  JsEngine? _engine;
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
      final previous = _engine;
      _engine = null;
      _callCount = 0;
      await previous?.dispose();

      final source = await rootBundle.loadString('assets/js/npm_bundle.mjs');
      final engine = await JsEngine.create(
        modules: <JsModule>[
          JsModule(name: 'example/npm-bundle', source: source),
        ],
      );
      if (!mounted || _disposed) {
        await engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
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
    final engine = _engine;
    if (engine == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在调用 compareValues()...';
    });
    try {
      await engine.runModule('''
import { bundledDependency, compareValues } from 'example/npm-bundle';
globalThis.npmBundleResult = bundledDependency + '/' + [
  compareValues({ answer: 42 }, { answer: 42 }),
  compareValues({ answer: 42 }, { answer: 7 })
].join('/');
''', name: 'example/call-npm-bundle-${++_callCount}.mjs');
      final result = await engine.eval('globalThis.npmBundleResult');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'compareValues() 调用完成';
        _result = result.toString();
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
    unawaited(_engine?.dispose() ?? Future<void>.value());
    _engine = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _engine != null;
    return Scaffold(
      appBar: AppBar(title: const Text('NPM 打包模块')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'asset → JsOptions.modules → '
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
