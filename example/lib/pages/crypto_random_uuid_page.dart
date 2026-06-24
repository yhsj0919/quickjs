import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// Web Crypto preset 示例：显式安装 `crypto.randomUUID()` / `getRandomValues()` global。
class CryptoRandomUuidPage extends StatefulWidget {
  const CryptoRandomUuidPage({super.key});

  @override
  State<CryptoRandomUuidPage> createState() => _CryptoRandomUuidPageState();
}

class _CryptoRandomUuidPageState extends State<CryptoRandomUuidPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 Web Crypto 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 Web Crypto 的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[QuickjsWebCryptoMount(subtleDigest: true)],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：Web Crypto 已启用';
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
          'typeof crypto.randomUUID === "undefined" || '
          'typeof crypto.getRandomValues === "undefined"',
        );
        _log.insert(0, '默认 runtime 暴露 Web Crypto => ${result == 'false'}');
        _status = result == 'true'
            ? '默认 runtime 未暴露 Web Crypto'
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

  Future<void> _runGetRandomValues() async {
    await _capture('生成随机字节', () async {
      final result = await _requireRuntime().eval('''
(() => {
  const bytes = new Uint8Array(8);
  const returned = crypto.getRandomValues(bytes);
  return "same=" + (returned === bytes) + "\\nbytes=" + Array.from(bytes).join(",");
})()
''');
      _log.insert(0, result);
      _status = '已生成 crypto.getRandomValues()';
    });
  }

  Future<void> _runDigest() async {
    await _capture('SHA-256 摘要', () async {
      final result = await _requireRuntime().evalAsync('''
const data = new Uint8Array([104, 101, 108, 108, 111]);
const digest = await crypto.subtle.digest("SHA-256", data);
return Array.from(new Uint8Array(digest))
  .map((byte) => byte.toString(16).padStart(2, "0"))
  .join("");
''');
      _log.insert(0, 'SHA-256("hello")\n$result');
      _status = '已通过 Flutter 原生 crypto 生成 SHA-256';
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
        'typeof crypto.randomUUID() === "string" && '
        'crypto.getRandomValues(new Uint8Array(1)) instanceof Uint8Array && '
        'typeof crypto.subtle.digest === "function"',
      );
      _log.insert(0, 'stop 后 Web Crypto 可用 => $result');
      _status = 'stop 后 runtime 已恢复，Web Crypto 可用';
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
      appBar: AppBar(title: const Text('Web Crypto')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'QuickjsWebCryptoMount()：显式安装 crypto.randomUUID()、crypto.getRandomValues() 和 Flutter 原生 crypto.subtle.digest()。',
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
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _runGetRandomValues,
                  child: const Text('生成 getRandomValues()'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _runDigest,
                  child: const Text('生成 SHA-256'),
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
                    ? const Center(child: Text('点击按钮验证 Web Crypto 行为'))
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
