import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class BasicEvalPage extends StatefulWidget {
  const BasicEvalPage({super.key});

  @override
  State<BasicEvalPage> createState() => _BasicEvalPageState();
}

class _BasicEvalPageState extends State<BasicEvalPage> {
  static const String _code = '1 + 2 * 3';

  Quickjs? _quickjs;
  String _quickjsVersion = '加载中';
  String _evalResult = '加载中';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _createAndRun();
  }

  Future<void> _createAndRun() async {
    try {
      final quickjs = await Quickjs.create();
      final result = await quickjs.evaluate(_code);

      if (_disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _quickjsVersion = quickjs.quickjsVersion;
        _evalResult = result;
      });
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _quickjsVersion = '错误';
        _evalResult = '$e';
      });
    }
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
    return Scaffold(
      appBar: AppBar(title: const Text('基础执行')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('QuickJS 版本：$_quickjsVersion'),
            const SizedBox(height: 8),
            Text('执行 "$_code" => $_evalResult'),
          ],
        ),
      ),
    );
  }
}
