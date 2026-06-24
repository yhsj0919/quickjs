import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class FetchPage extends StatefulWidget {
  const FetchPage({super.key});

  @override
  State<FetchPage> createState() => _FetchPageState();
}

class _FetchPageState extends State<FetchPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 Fetch 的 runtime...';
  String _result = '尚未发起请求';

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 Fetch 的 runtime...';
    });
    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsFetchMount(
              allowedOrigins: const <String>{
                'https://jsonplaceholder.typicode.com',
              },
            ),
          ],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：仅允许 jsonplaceholder.typicode.com';
        _result = '尚未发起请求';
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

  Future<void> _runFetch() async {
    final quickjs = _quickjs;
    if (quickjs == null) {
      return;
    }
    setState(() {
      _busy = true;
      _status = '正在执行 fetch()...';
    });
    try {
      final result = await quickjs.evalAsync('''
const response = await fetch('https://jsonplaceholder.typicode.com/todos/1');
const todo = await response.json();
return [response.status, response.ok, todo.id, todo.title].join(' / ');
''');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'fetch() 已完成';
        _result = result;
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = 'fetch() 失败：$error';
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
    final hasRuntime = _quickjs != null;
    return Scaffold(
      appBar: AppBar(title: const Text('Fetch')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'Native: HttpClient · Web: browser fetch · '
              'Web 请求仍受浏览器 CORS 限制',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runFetch,
                  child: const Text('请求 TODO'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            SelectableText('result: $_result'),
          ],
        ),
      ),
    );
  }
}
