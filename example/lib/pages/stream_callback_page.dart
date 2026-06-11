import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class StreamCallbackPage extends StatefulWidget {
  const StreamCallbackPage({super.key});

  @override
  State<StreamCallbackPage> createState() => _StreamCallbackPageState();
}

class _StreamCallbackPageState extends State<StreamCallbackPage> {
  Quickjs? _quickjs;
  StreamSubscription<Object?>? _sinkSubscription;
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
      await _sinkSubscription?.cancel();
      _sinkSubscription = null;
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create();
      await _bindCallbacks(quickjs);
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

  Future<void> _bindCallbacks(Quickjs quickjs) async {
    await quickjs.bind('hostCount', (args) {
      final max = (args.single as num).toInt();
      return Stream<Object?>.periodic(
        const Duration(milliseconds: 80),
        (index) => index + 1,
      ).take(max);
    });

    final sinkStream = await quickjs.bindSink('progress');
    _sinkSubscription = sinkStream.listen(
      (value) => _appendLog('Dart 收到 JS sink: $value'),
      onError: (Object error) => _appendLog('JS sink error: $error'),
      onDone: () => _appendLog('JS sink closed'),
    );
  }

  Future<void> _runDartStream() async {
    await _capture('Dart Stream -> JS for-await', () async {
      final result = await _requireRuntime().evalAsync('''
const values = [];
const stream = await hostCount(5);
for await (const value of stream) {
  values.push(value);
}
return values.join(',');
''');
      _appendLog('JS for-await hostCount(5) => $result');
    });
  }

  Future<void> _runJsSink() async {
    await _capture('JS sink -> Dart Stream', () async {
      final result = await _requireRuntime().evalAsync('''
let n = 0;
while (n < 3) {
  await new Promise((resolve) => setTimeout(resolve, 1000));
  await progress.emit(++n);
}
await progress.close();
return 'done';
''');
      _appendLog('JS sink 推送完成 => $result');
    });
  }

  Future<void> _runJsSinkError() async {
    await _capture('JS sink error', () async {
      final result = await _requireRuntime().evalAsync('''
await progress.error('stream failed from JS');
return 'error sent';
''');
      _appendLog('JS sink error 推送完成 => $result');
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

  @override
  void dispose() {
    _disposed = true;
    unawaited(_sinkSubscription?.cancel() ?? Future<void>.value());
    _sinkSubscription = null;
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('流式 Callback')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'Dart Stream 可被 JS for-await 消费；JS sink 可分片推送到 Dart Stream。',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runDartStream,
                  child: const Text('运行 Dart Stream'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runJsSink,
                  child: const Text('运行 JS sink'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runJsSinkError,
                  child: const Text('运行 sink error'),
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
                    ? const Center(child: Text('点击按钮查看流式 callback 结果'))
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
