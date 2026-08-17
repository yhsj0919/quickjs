import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

/// 异常模型演示：手动触发并展示公开异常类型与结构化 JS 异常字段。
class ExceptionModelPage extends StatefulWidget {
  const ExceptionModelPage({super.key});

  @override
  State<ExceptionModelPage> createState() => _ExceptionModelPageState();
}

class _ExceptionModelPageState extends State<ExceptionModelPage> {
  JsEngine? _engine;
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
      final previous = _engine;
      _engine = null;
      if (previous != null) {
        await previous.dispose();
      }

      final engine = await JsEngine.create();
      if (!mounted || _disposed) {
        await engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
        _busy = false;
        _status = 'runtime 已就绪（${engine.engineVersion}）';
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
      final engine = _requireRuntime();
      final running = engine
          .eval('while (true) {}')
          // 先把 running eval 的错误捕获下来，避免 stop 前后出现未处理错误。
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.restart();
      final error = await running;
      if (error != null) {
        throw error;
      }
    });
  }

  Future<void> _runClosed() async {
    await _capture('closed runtime', () async {
      final engine = _requireRuntime();
      await engine.dispose();
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _engine = null;
      });
      await engine.eval('1 + 1');
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

  JsEngine _requireRuntime() {
    final engine = _engine;
    if (engine == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return engine;
  }

  String _describeError(Object error) {
    if (error is JsThrownException) {
      return [
        '${error.runtimeType}',
        'name: ${_formatNullable(error.name)}',
        'message: ${error.message}',
        'stack: ${_formatNullable(error.stack)}',
        'fileName: ${_formatNullable(error.fileName)}',
        'line: ${_formatNullable(error.line)}',
        'column: ${_formatNullable(error.column)}',
      ].join('\n');
    }

    // 公开 JsException 都有 message，可以比普通 Object 输出更稳定。
    if (error is JsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
  }

  String _formatNullable(Object? value) => value?.toString() ?? '<null>';

  @override
  void dispose() {
    _disposed = true;
    // 页面退出时释放 runtime，避免后续页面复用到异常状态。
    unawaited(_engine?.dispose() ?? Future<void>.value());
    _engine = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _engine != null;

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
                  child: const Text('触发 JsThrownException'),
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
                    ? const Center(child: Text('点击按钮查看异常类型与结构化字段'))
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
