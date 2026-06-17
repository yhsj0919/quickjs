import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// Host capability demo for opt-in `crypto.randomUUID()`.
class CryptoRandomUuidPage extends StatefulWidget {
  const CryptoRandomUuidPage({super.key});

  @override
  State<CryptoRandomUuidPage> createState() => _CryptoRandomUuidPageState();
}

class _CryptoRandomUuidPageState extends State<CryptoRandomUuidPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 crypto.randomUUID 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 crypto.randomUUID 的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          hostCapabilities: QuickjsHostCapabilities(
            crypto: QuickjsCryptoCapabilities(randomUUID: true),
          ),
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：crypto.randomUUID 已启用';
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

  Future<void> _runDefaultDisabledCheck() async {
    await _capture('默认未启用检查', () async {
      final quickjs = await Quickjs.create();
      try {
        final result = await quickjs.eval(
          'typeof crypto === "undefined" || '
          'typeof crypto.randomUUID === "undefined"',
        );
        _log.insert(
          0,
          '默认 runtime 暴露 crypto.randomUUID => ${result == 'false'}',
        );
        _status = result == 'true'
            ? '默认 runtime 未暴露 crypto.randomUUID'
            : '默认 runtime 检查失败';
      } finally {
        await quickjs.dispose();
      }
    });
  }

  Future<void> _runRandomUuid() async {
    await _capture('生成 UUID', () async {
      final result = await _requireRuntime().eval('''
(() => {
  const first = crypto.randomUUID();
  const second = crypto.randomUUID();
  const pattern = /^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\$/;
  return first + "\\n" + second + "\\nvalid=" +
    pattern.test(first) + "/" + pattern.test(second) +
    "\\ndifferent=" + (first !== second);
})()
''');
      _log.insert(0, result);
      _status = '已生成 crypto.randomUUID()';
    });
  }

  Future<void> _runStopRecovery() async {
    await _capture('stop 后恢复', () async {
      final quickjs = _requireRuntime();
      final running = quickjs
          .eval('while (true) {}')
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await quickjs.stop();
      await running;
      final result = await quickjs.eval(
        'typeof crypto.randomUUID() === "string"',
      );
      _log.insert(0, 'stop 后 crypto.randomUUID 可用 => $result');
      _status = 'stop 后 runtime 已恢复，crypto.randomUUID 可用';
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
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '$name 失败：${_describeError(error)}';
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
      appBar: AppBar(title: const Text('Crypto randomUUID')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'QuickjsHostCapabilities.crypto + '
              'QuickjsCryptoCapabilities(randomUUID: true)',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runRandomUuid,
                  child: const Text('生成 crypto.randomUUID()'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runDefaultDisabledCheck,
                  child: const Text('验证默认未启用'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStopRecovery,
                  child: const Text('验证 stop 后恢复'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
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
                    ? const Center(child: Text('点击按钮验证 crypto.randomUUID 行为'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_log[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
