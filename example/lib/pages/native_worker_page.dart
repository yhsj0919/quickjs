import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class NativeWorkerPage extends StatefulWidget {
  const NativeWorkerPage({super.key});

  @override
  State<NativeWorkerPage> createState() => _NativeWorkerPageState();
}

class _NativeWorkerPageState extends State<NativeWorkerPage> {
  Quickjs? _quickjs;
  Timer? _ticker;
  bool _disposed = false;
  bool _running = false;
  int _ticks = 0;
  String _status = '正在创建 runtime...';
  String _result = '';

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(milliseconds: 100), (_) {
      if (mounted && !_disposed) {
        setState(() {
          _ticks += 1;
        });
      }
    });
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    try {
      final quickjs = await Quickjs.create();
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _status = 'runtime 已就绪（${quickjs.quickjsVersion}）';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _status = '创建失败：$error';
      });
    }
  }

  Future<void> _runBusyLoop() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _running = true;
      _result = '';
      _status = '正在执行 3 秒 JS 忙循环...';
    });

    final beforeTicks = _ticks;
    final stopwatch = Stopwatch()..start();
    try {
      final result = await quickjs.eval('''
        (() => {
          const start = Date.now();
          while (Date.now() - start < 3000) {}
          return "done";
        })();
      ''');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result = '$result，eval 期间 Dart 计数：${_ticks - beforeTicks}';
        _status = '执行完成，用时 ${stopwatch.elapsedMilliseconds} ms';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result = '$error';
        _status = 'eval 执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _ticker?.cancel();
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final ready = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('运行时 Worker')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (kIsWeb) ...[
              const Text('Web 使用 Worker，native 使用 Dart isolate。'),
              const SizedBox(height: 12),
            ],
            Text(_status),
            const SizedBox(height: 8),
            Text('Dart UI 计数器：$_ticks'),
            if (_result.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(_result),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _running || !ready ? null : _runBusyLoop,
              child: const Text('执行忙循环'),
            ),
          ],
        ),
      ),
    );
  }
}
