import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 异常模型演示：手动触发并展示公开异常类型。
class ExceptionModelPage extends StatefulWidget {
  const ExceptionModelPage({super.key});

  @override
  State<ExceptionModelPage> createState() => _ExceptionModelPageState();
}

class _ExceptionModelPageState extends State<ExceptionModelPage> {
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

  Future<void> _runJsThrow() async {
    await _capture('JS throw', () async {
      await _requireRuntime().eval('throw new Error("demo boom")');
    });
  }

  Future<void> _runTimeout() async {
    await _capture('timeout', () async {
      await _requireRuntime().eval(
        'while (true) {}',
        timeout: const Duration(milliseconds: 50),
      );
    });
  }

  Future<void> _runStop() async {
    await _capture('stop / cancel', () async {
      final quickjs = _requireRuntime();
      final running = quickjs
          .eval('while (true) {}')
          // 先把 running eval 的错误捕获下来，避免 stop 前后出现未处理错误。
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await quickjs.stop();
      final error = await running;
      if (error != null) {
        throw error;
      }
    });
  }

  Future<void> _runClosed() async {
    await _capture('closed runtime', () async {
      final quickjs = _requireRuntime();
      await quickjs.dispose();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _quickjs = null;
      });
      await quickjs.eval('1 + 1');
    });
  }

  Future<void> _capture(String name, Future<void> Function() action) async {
    setState(() {
      _busy = true;
      _status = '正在运行：$name';
    });

    try {
      await action();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$name 未抛出异常';
        _log.insert(0, '$name => no error');
      });
    } catch (error) {
      // 页面统一展示异常类型，便于核对 ROADMAP 中的错误模型要求。
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$name 捕获到 ${error.runtimeType}';
        _log.insert(0, '$name => ${_describeError(error)}');
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
    // 公开 QuickjsException 都有 message，可以比普通 Object 输出更稳定。
    if (error is QuickjsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
  }

  @override
  void dispose() {
    _disposed = true;
    // 页面退出时释放 runtime，避免后续页面复用到异常状态。
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('基础错误模型')),
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
                  onPressed: _busy || !hasRuntime ? null : _runJsThrow,
                  child: const Text('触发 JsException'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runTimeout,
                  child: const Text('触发 JsTimeoutException'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStop,
                  child: const Text('触发 JsCancelledException'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runClosed,
                  child: const Text('触发 JsRuntimeClosedException'),
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
                    ? const Center(child: Text('点击按钮查看异常类型'))
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
