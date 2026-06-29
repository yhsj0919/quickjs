import 'dart:async';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

final _singleFilePlugin = QuickjsPlugin.singleFile(
  id: 'api1',
  version: '1.0.0',
  exports: const <String>['hello', 'bytes'],
  source: '''
export async function hello(name, profile) {
  return {
    message: 'hello ' + name,
    nested: profile.nested.ok,
    count: profile.count + 1,
  };
}

export function bytes(input) {
  return new Uint8Array([input[0], input[1], 255]);
}
''',
);

final _packagePlugin = QuickjsPlugin(
  manifest: const QuickjsPluginManifest(
    id: 'api2',
    version: '1.0.0',
    entry: 'api2/main',
    exports: <String>['hello'],
  ),
  modules: const <QuickjsPluginModule>[
    QuickjsPluginModule(
      specifier: 'api2/main',
      source: '''
import { suffix } from './modules/helper';

export function hello(name) {
  return 'hello ' + name + suffix;
}
''',
    ),
    QuickjsPluginModule(
      specifier: 'api2/modules/helper',
      source: "export const suffix = ' from package module';",
    ),
  ],
);

final _invalidPlugin = QuickjsPlugin.singleFile(
  id: 'api3',
  version: '1.0.0',
  exports: const <String>['hello'],
  source: 'export const hello = 1;',
);

final _missingDependencyPlugin = QuickjsPlugin.singleFile(
  id: 'api4',
  version: '1.0.0',
  exports: const <String>['hello'],
  source: '''
import './missing';

export function hello() {
  return 'unreachable';
}
''',
);

class PluginPage extends StatefulWidget {
  const PluginPage({super.key});

  @override
  State<PluginPage> createState() => _PluginPageState();
}

class _PluginPageState extends State<PluginPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 JS 插件的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 JS 插件的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();
      final assetPlugin = await QuickjsPlugin.singleFileAsset(
        id: 'assetApi',
        version: '1.0.0',
        assetKey: 'assets/js/js_call_dart_plugin.mjs',
        exports: const <String>['test', 'test2'],
      );
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            _singleFilePlugin.asMount(),
            _packagePlugin.asMount(),
            _invalidPlugin.asMount(),
            _missingDependencyPlugin.asMount(),
            assetPlugin.asMount(),
          ],
        ),
        onConsole: (event) {
          if (!mounted || _disposed) {
            return;
          }
          setState(() {
            _log.insert(0, 'console.${event.level.name} => ${event.text}');
          });
        },
      );
      await _bindDartMethods(quickjs);
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }

      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：asset 插件和 4 个内置插件已注册';
      });
    } catch (error) {
      if (!mounted || _disposed) {
        return;
      }
      setState(() {
        _busy = false;
        _status = '创建失败：${_describeError(error)}';
      });
    }
  }

  Future<void> _bindDartMethods(Quickjs quickjs) async {
    await quickjs.bind('alert', (args) async {
      final output = args.join(' ');
      if (!mounted || _disposed) {
        return null;
      }
      setState(() {
        _log.insert(0, 'alert() <= $output');
      });
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (context) {
          return AlertDialog(
            title: const Text('JS Alert'),
            content: SingleChildScrollView(child: Text(output)),
            actions: <Widget>[
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text('OK'),
              ),
            ],
          );
        },
      );
      return null;
    });
    await quickjs.bind('getDataAsync', (args) {
      _log.insert(0, 'getDataAsync() <= $args');
      return '来自 Dart 的消息';
    });
    await quickjs.bind('dartMethod', (args) {
      _log.insert(0, 'dartMethod() <= $args');
      return '这是静态消息';
    });
    await quickjs.bind('asyncWithError', (_) async {
      await Future<void>.delayed(const Duration(milliseconds: 100));
      throw StateError('Some error');
    });
  }

  Future<void> _validatePlugins() async {
    await _capture('校验插件契约', () async {
      final quickjs = _requireRuntime();
      await quickjs.validatePlugin(_singleFilePlugin);
      await quickjs.validatePlugin(_packagePlugin);
      _log.insert(0, 'validatePlugin => api1/api2 exports 均为 function');
      _status = 'manifest exports 已完成显式校验';
    });
  }

  Future<void> _callSingleFilePlugin() async {
    await _capture('调用单文件插件', () async {
      final result = await _requireRuntime().callPlugin(
        _singleFilePlugin,
        'hello',
        <Object?>[
          'QuickJS',
          {
            'nested': {'ok': true},
            'count': 41,
          },
        ],
      );
      _log.insert(0, 'api1.hello() => $result');
      _status = '单文件插件调用完成';
    });
  }

  Future<void> _callPackagePlugin() async {
    await _capture('调用插件包', () async {
      final result = await _requireRuntime().invokePlugin(
        'hello',
        const <Object?>['package'],
        pluginId: 'api2',
      );
      _log.insert(0, 'api2.hello() => $result');
      _status = '多模块插件包调用完成';
    });
  }

  Future<void> _callBytesPlugin() async {
    await _capture('调用 Uint8List 返回', () async {
      final result = await _requireRuntime().callPlugin(
        _singleFilePlugin,
        'bytes',
        <Object?>[
          Uint8List.fromList(<int>[1, 2]),
        ],
      );
      final bytes = result as Uint8List;
      _log.insert(0, 'api1.bytes() => ${bytes.join(',')}');
      _status = 'Uint8List 参数和返回值已通过 structured codec';
    });
  }

  Future<void> _callAssetPlugin() async {
    await _capture('调用 asset 插件 test2', () async {
      final result = await _requireRuntime().invokePlugin('test2', <Object?>[
        'ss\'·\$`"dd"}{s',
        99,
        {'aa': 'vv""`\'v'},
        ['sss', 'dd]dd'],
      ]);
      _log.insert(0, 'assetApi.test2() => $result');
      _status = 'asset 插件已通过 Dart 注入方法完成调用';
    });
  }

  Future<void> _checkErrors() async {
    await _capture('检查插件错误', () async {
      final quickjs = _requireRuntime();
      final messages = <String>[];
      try {
        await quickjs.validatePlugin(_invalidPlugin);
      } catch (error) {
        messages.add('非函数导出：${_describeError(error)}');
      }
      try {
        await quickjs.validatePlugin(_missingDependencyPlugin);
      } catch (error) {
        messages.add('缺失依赖：${_describeError(error)}');
      }
      if (messages.length != 2) {
        throw StateError('插件错误检查未覆盖所有预期错误');
      }
      _log.insert(0, messages.join('\n'));
      _status = '插件导出和模块图错误已按预期返回';
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
      final result = await quickjs.callPlugin(
        _packagePlugin,
        'hello',
        const <Object?>['after stop'],
      );
      _log.insert(0, 'stop 后 api2.hello() => $result');
      _status = 'stop 重建后插件 mount 已恢复';
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
      appBar: AppBar(title: const Text('JS 插件')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'QuickjsPlugin → QuickjsHostMount → validatePlugin() / invokePlugin()',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _validatePlugins,
                  child: const Text('校验插件'),
                ),
                FilledButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _callSingleFilePlugin,
                  child: const Text('单文件 hello'),
                ),
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callPackagePlugin,
                  child: const Text('插件包 hello'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _callBytesPlugin,
                  child: const Text('Uint8List'),
                ),
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _callAssetPlugin,
                  child: const Text('asset test2'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _checkErrors,
                  child: const Text('错误检查'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStopRecovery,
                  child: const Text('stop 恢复'),
                ),
                TextButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
                ),
              ],
            ),
            const SizedBox(height: 24),
            Expanded(
              child: _log.isEmpty
                  ? const Center(child: Text('点击按钮验证插件行为'))
                  : ListView.separated(
                      itemCount: _log.length,
                      separatorBuilder: (_, _) => const Divider(height: 16),
                      itemBuilder: (context, index) {
                        return SelectableText(_log[index]);
                      },
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
