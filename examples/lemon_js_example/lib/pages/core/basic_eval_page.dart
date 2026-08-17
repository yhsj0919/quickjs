import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

/// 最小用法演示：创建 runtime、执行一段 JS、页面销毁时释放 runtime。
class BasicEvalPage extends StatefulWidget {
  const BasicEvalPage({super.key});

  @override
  State<BasicEvalPage> createState() => _BasicEvalPageState();
}

class _BasicEvalPageState extends State<BasicEvalPage> {
  static const String _code = '1 + 2 * 3';

  JsEngine? _engine;
  String _engineVersion = '加载中';
  String _evalResult = '加载中';
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _createAndRun();
  }

  Future<void> _createAndRun() async {
    try {
      final engine = await JsEngine.create();
      final result = await engine.evalRaw(_code);

      // 页面可能在 async create/eval 完成前被关闭，必须及时释放刚创建的 runtime。
      if (_disposed) {
        await engine.dispose();
        return;
      }

      setState(() {
        _engine = engine;
        _engineVersion = engine.engineVersion;
        _evalResult = result;
      });
    } catch (e) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _engineVersion = '错误';
        _evalResult = '$e';
      });
    }
  }

  @override
  void dispose() {
    _disposed = true;
    // dispose 不阻塞 Flutter 页面销毁流程，但必须触发底层 runtime 释放。
    unawaited(_engine?.dispose() ?? Future<void>.value());
    _engine = null;
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
            Text('QuickJS 版本：$_engineVersion'),
            const SizedBox(height: 8),
            Text('执行 "$_code" => $_evalResult'),
          ],
        ),
      ),
    );
  }
}
