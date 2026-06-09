import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 多 runtime 隔离演示：验证 globals 隔离和 dispose 隔离。
class RuntimeIsolationPage extends StatefulWidget {
  const RuntimeIsolationPage({super.key});

  @override
  State<RuntimeIsolationPage> createState() => _RuntimeIsolationPageState();
}

class _RuntimeIsolationPageState extends State<RuntimeIsolationPage> {
  Quickjs? _first;
  Quickjs? _second;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntimes());
  }

  Future<void> _createRuntimes() async {
    setState(() {
      _busy = true;
      _status = '正在创建两个 runtime...';
      _log.clear();
    });

    try {
      await _first?.dispose();
      await _second?.dispose();
      _first = null;
      _second = null;

      final first = await Quickjs.create();
      final second = await Quickjs.create();
      if (!mounted || _disposed) {
        await first.dispose();
        await second.dispose();
        return;
      }

      setState(() {
        _first = first;
        _second = second;
        _busy = false;
        _status = '两个 runtime 已就绪（${first.quickjsVersion}）';
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

  Future<void> _runGlobalIsolationTest() async {
    final first = _first;
    final second = _second;
    if (first == null || second == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在验证 globals 隔离...';
      _log.clear();
    });

    try {
      final firstSet = await first.eval('globalThis.sharedName = "first"');
      // 第二个 runtime 初次读取应为 undefined，证明 globalThis 没有共享。
      final secondBefore = await second.eval('globalThis.sharedName');
      final secondSet = await second.eval('globalThis.sharedName = "second"');
      final firstAfter = await first.eval('globalThis.sharedName');
      final secondAfter = await second.eval('globalThis.sharedName');
      final isolated =
          firstSet == 'first' &&
          secondBefore == 'undefined' &&
          secondSet == 'second' &&
          firstAfter == 'first' &&
          secondAfter == 'second';

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = isolated ? 'globals 已隔离' : 'globals 隔离异常';
        _log
          ..add('runtime A 设置：$firstSet')
          ..add('runtime B 初始读取：$secondBefore')
          ..add('runtime B 设置：$secondSet')
          ..add('runtime A 再次读取：$firstAfter')
          ..add('runtime B 再次读取：$secondAfter');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'globals 隔离测试失败：$error';
      });
    }
  }

  Future<void> _runDisposeIsolationTest() async {
    final first = _first;
    final second = _second;
    if (first == null || second == null) {
      return;
    }

    setState(() {
      _busy = true;
      _status = '正在验证 dispose 隔离...';
      _log.clear();
    });

    try {
      await first.eval('globalThis.disposedPeer = 1');
      await second.eval('globalThis.alivePeer = 2');
      await first.dispose();
      _first = null;

      // A 已关闭应报错；B 必须保留自己的状态并继续可用。
      final firstClosed = await first
          .eval('1 + 1')
          .then(
            (value) => 'runtime A 意外执行：$value',
            onError: (Object error) => 'runtime A 已关闭：${error.runtimeType}',
          );
      final secondValue = await second.eval('globalThis.alivePeer');
      final secondEval = await second.eval('40 + 2');
      final isolated = secondValue == '2' && secondEval == '42';

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = isolated ? 'dispose 未影响另一个 runtime' : 'dispose 隔离异常';
        _log
          ..add(firstClosed)
          ..add('runtime B 保留状态：$secondValue')
          ..add('runtime B 后续 eval：$secondEval');
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'dispose 隔离测试失败：$error';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // 两个 runtime 都归属当前页面，退出时一起释放。
    unawaited(_first?.dispose() ?? Future<void>.value());
    unawaited(_second?.dispose() ?? Future<void>.value());
    _first = null;
    _second = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _first != null && _second != null;

    return Scaffold(
      appBar: AppBar(title: const Text('Runtime 隔离')),
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
                  onPressed: _busy || !ready ? null : _runGlobalIsolationTest,
                  child: const Text('验证 globals 隔离'),
                ),
                OutlinedButton(
                  onPressed: _busy || !ready ? null : _runDisposeIsolationTest,
                  child: const Text('验证 dispose 隔离'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntimes,
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
