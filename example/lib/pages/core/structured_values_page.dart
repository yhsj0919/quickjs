import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

/// 结构化返回演示：对比 eval 字符串结果和 evaluateValue Dart 值结果。
class StructuredValuesPage extends StatefulWidget {
  const StructuredValuesPage({super.key});

  @override
  State<StructuredValuesPage> createState() => _StructuredValuesPageState();
}

class _StructuredValuesPageState extends State<StructuredValuesPage> {
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
      await previous?.dispose();

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

  Future<void> _runPrimitiveValues() async {
    setState(() {
      _busy = true;
      _status = '正在执行 evaluateValue...';
      _log.clear();
    });

    try {
      final quickjs = _requireRuntime();
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
        final value = await quickjs.evaluateValue(code);
        rows.add('$code => ${_describeValue(value)}');
      }
      try {
        await quickjs.evaluateValue('[1, Symbol("id")]');
      } on JsValueConversionException catch (error) {
        rows.add('[1, Symbol("id")] => ${error.runtimeType}: ${error.message}');
      }
      final globalsValue = await quickjs.evaluateValue(
        '({ total: count + price, bytes: Array.from(bytes), date: date.toISOString() })',
        globals: {
          'count': 40,
          'price': 2.5,
          'bytes': Uint8List.fromList([1, 2, 255]),
          'date': DateTime.utc(2026, 6, 10),
        },
      );
      rows.add('globals => ${_describeValue(globalsValue)}');
      rows.add('eval("undefined") => ${await quickjs.eval('undefined')}');

      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'evaluateValue 已完成';
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

  Quickjs _requireRuntime() {
    final quickjs = _quickjs;
    if (quickjs == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return quickjs;
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
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null;

    return Scaffold(
      appBar: AppBar(title: const Text('结构化返回')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('evaluateValue 返回 Dart 值；eval 保持字符串兼容语义。'),
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
