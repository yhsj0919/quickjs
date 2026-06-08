import 'dart:async';

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
        _status = 'runtime 已就绪（${quickjs.quickjsVersion}）';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _quickjs = null;
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

  Future<void> _runTimeoutLoop() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _running = true;
      _result = '';
      _status = '正在执行带 timeout 的无限循环...';
    });

    final beforeTicks = _ticks;
    final stopwatch = Stopwatch()..start();
    try {
      await quickjs.eval(
        'while (true) {}',
        timeout: const Duration(milliseconds: 100),
      );
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result = '无限循环意外完成';
        _status = 'timeout 测试失败';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      final recoveryResult = error is JsTimeoutException
          ? await quickjs.eval('40 + 2')
          : null;
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result =
            '$error；eval 期间 Dart 计数：${_ticks - beforeTicks}；用时 ${stopwatch.elapsedMilliseconds} ms';
        _status = error is JsTimeoutException
            ? 'timeout 已触发，后续 eval 结果：$recoveryResult'
            : 'eval 执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _runStopLoop() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }

    setState(() {
      _running = true;
      _result = '';
      _status = '正在执行无限循环并手动 stop...';
    });

    final beforeTicks = _ticks;
    final stopwatch = Stopwatch()..start();
    final evalFuture = quickjs.eval('while (true) {}');
    final stopFuture = Future<void>.delayed(
      const Duration(milliseconds: 100),
      quickjs.stop,
    );

    try {
      await evalFuture;
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result = '无限循环意外完成';
        _status = 'stop 测试失败';
      });
    } catch (error) {
      await stopFuture;
      if (!mounted || _disposed) {
        return;
      }
      final recoveryResult = error is JsCancelledException
          ? await quickjs.eval('6 * 7')
          : null;
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result =
            '$error；eval 期间 Dart 计数：${_ticks - beforeTicks}；用时 ${stopwatch.elapsedMilliseconds} ms';
        _status = error is JsCancelledException
            ? 'stop 已触发，后续 eval 结果：$recoveryResult'
            : 'eval 执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _startInfiniteLoop() async {
    final quickjs = _quickjs;
    if (quickjs == null || _running) {
      return;
    }

    setState(() {
      _running = true;
      _result = '';
      _status = '无限循环运行中，可快速点击 Stop 当前 eval';
    });

    final beforeTicks = _ticks;
    final stopwatch = Stopwatch()..start();
    try {
      await quickjs.eval('while (true) {}');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result = '无限循环意外完成';
        _status = '手动 stop 测试失败';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      final recoveryResult = error is JsCancelledException
          ? await quickjs.eval('6 * 7')
          : null;
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _result =
            '$error；eval 期间 Dart 计数：${_ticks - beforeTicks}；用时 ${stopwatch.elapsedMilliseconds} ms';
        _status = error is JsCancelledException
            ? '手动 stop 已触发，后续 eval 结果：$recoveryResult'
            : 'eval 执行失败';
      });
    } finally {
      if (mounted && !_disposed) {
        setState(() {
          _running = false;
        });
      }
    }
  }

  Future<void> _stopCurrentEval() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }
    try {
      await quickjs.stop();
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _status = 'stop 失败：$error';
      });
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
            const Text('Web 使用 Worker，native 使用 Dart isolate。'),
            const SizedBox(height: 12),
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
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running || !ready ? null : _runTimeoutLoop,
              child: const Text('验证 timeout'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: _running || !ready ? null : _runStopLoop,
              child: const Text('验证 stop'),
            ),
            const SizedBox(height: 8),
            FilledButton.tonal(
              onPressed: _running || !ready ? null : _startInfiniteLoop,
              child: const Text('启动无限循环'),
            ),
            const SizedBox(height: 8),
            OutlinedButton(
              onPressed: !_running || !ready ? null : _stopCurrentEval,
              child: const Text('Stop 当前 eval'),
            ),
          ],
        ),
      ),
    );
  }
}
