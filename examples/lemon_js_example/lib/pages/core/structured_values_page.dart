import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

/// 结构化返回演示：对比 eval 字符串结果和 eval Dart 值结果。
class StructuredValuesPage extends StatefulWidget {
  const StructuredValuesPage({super.key});

  @override
  State<StructuredValuesPage> createState() => _StructuredValuesPageState();
}

class _StructuredValuesPageState extends State<StructuredValuesPage> {
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
      await previous?.dispose();

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

  Future<void> _runPrimitiveValues() async {
    setState(() {
      _busy = true;
      _status = '正在执行 eval...';
      _log.clear();
    });

    try {
      final engine = _requireRuntime();
      final cases = <String>[
        '1 + 2',
        '1.5 + 2',
        'true',
        '"hello"',
        'null',
        'undefined',
        '9007199254740993n',
        'new Uint8Array([1, 2, 255])',
        '[1, "two", true, null]',
        '({ nested: [1, { ok: true }, null] })',
      ];
      final rows = <String>[];
      for (final code in cases) {
        final value = await engine.eval(code);
        rows.add('$code => ${_describeValue(value)}');
      }
      try {
        await engine.eval('[1, Symbol("id")]');
      } on JsValueConversionException catch (error) {
        rows.add('[1, Symbol("id")] => ${error.runtimeType}: ${error.message}');
      }
      final globalsValue = await engine.eval(
        '({ total: count + price, bytes: Array.from(bytes), date: date.toISOString() })',
        tempGlobals: {
          'count': 40,
          'price': 2.5,
          'bytes': Uint8List.fromList([1, 2, 255]),
          'date': DateTime.utc(2026, 6, 10),
        },
      );
      rows.add('globals => ${_describeValue(globalsValue)}');
      rows.add('eval("undefined") => ${await engine.eval('undefined')}');

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'eval 已完成';
        _log.addAll(rows);
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '执行失败：$error';
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

  String _describeValue(Object? value) {
    if (value == null) {
      return 'null (Dart Null)';
    }
    if (value is Uint8List) {
      return '${value.toList()} (Uint8List)';
    }
    return '$value (${value.runtimeType})';
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
      appBar: AppBar(title: const Text('结构化值返回')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('eval 返回 Dart 值；eval 保持字符串兼容语义。'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runPrimitiveValues,
                  child: const Text('运行值映射'),
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
                    ? const Center(child: Text('点击按钮查看结构化返回结果'))
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
