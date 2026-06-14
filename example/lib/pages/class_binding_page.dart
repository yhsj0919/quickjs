import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

class ClassBindingPage extends StatefulWidget {
  const ClassBindingPage({super.key});

  @override
  State<ClassBindingPage> createState() => _ClassBindingPageState();
}

final class _ExampleUser {
  _ExampleUser(this.name);

  String name;
}

class _ClassBindingPageState extends State<ClassBindingPage> {
  Quickjs? _quickjs;
  QuickjsClassHandle? _userClass;
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
      _userClass = null;
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create();
      final userClass = await quickjs.bindClass<_ExampleUser>(
        'User',
        QuickjsClass<_ExampleUser>(
          constructor: (args) => _ExampleUser(args.single as String),
          accessors: {
            'name': QuickjsInstanceAccessor<_ExampleUser>(
              get: (user) => user.name,
              set: (user, value) {
                user.name = value as String;
              },
            ),
          },
          methods: {
            'greet': (user, args) => '你好 ${args.single}，我是 ${user.name}',
          },
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _userClass = userClass;
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

  Future<void> _constructAndRead() async {
    await _capture('构造并读取实例', () async {
      final result = await _requireRuntime().evalAsync('''
globalThis.currentUser = new User('Tom');
return await currentUser.name;
''');
      _appendLog("new User('Tom'); await user.name => $result");
    });
  }

  Future<void> _changeName() async {
    await _capture('修改动态属性', () async {
      final result = await _requireRuntime().evalAsync('''
globalThis.currentUser ??= new User('Tom');
const before = await currentUser.name;
currentUser.name = 'Jerry';
const after = await currentUser.name;
return before + ' -> ' + after;
''');
      _appendLog('user.name = "Jerry" => $result');
    });
  }

  Future<void> _callMethod() async {
    await _capture('调用实例方法', () async {
      final result = await _requireRuntime().evalAsync('''
globalThis.currentUser ??= new User('Tom');
return await currentUser.greet('Alice');
''');
      _appendLog("await user.greet('Alice') => $result");
    });
  }

  Future<void> _disposeClass() async {
    await _capture('释放 class binding', () async {
      final handle = _userClass;
      if (handle == null) {
        throw JsRuntimeClosedException('QuickJS class binding is not ready');
      }
      await _requireRuntime().evalAsync('''
globalThis.leakedUser = globalThis.currentUser ?? new User('Tom');
return await leakedUser.name;
''');
      await handle.dispose();
      _appendLog('QuickjsClassHandle.dispose() 已释放 constructor 和实例表');
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _userClass = null;
      });
    });
  }

  Future<void> _checkDisposedInstance() async {
    await _capture('检查释放后的实例', () async {
      await _requireRuntime().evalAsync('return await leakedUser.name;');
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
    unawaited(_quickjs?.dispose() ?? Future<void>.value());
    _quickjs = null;
    _userClass = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasRuntime = _quickjs != null && _userClass != null;
    final canCheckDisposed = _quickjs != null && _userClass == null;

    return Scaffold(
      appBar: AppBar(title: const Text('Class Binding')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              '使用 bindClass 注册 Dart class；JS 可以 new User(...)，getter 和 method 通过 Promise await 访问。',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _constructAndRead,
                  child: const Text('构造并读取'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _changeName,
                  child: const Text('修改属性'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime ? null : _callMethod,
                  child: const Text('调用方法'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _disposeClass,
                  child: const Text('释放 class binding'),
                ),
                OutlinedButton(
                  onPressed: _busy || !canCheckDisposed
                      ? null
                      : _checkDisposedInstance,
                  child: const Text('检查泄漏实例'),
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
                    ? const Center(child: Text('点击按钮查看 class binding 结果'))
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
