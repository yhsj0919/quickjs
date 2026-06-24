import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

const _initialMount = QuickjsHostMount(
  name: 'example-initial',
  environmentPatches: <QuickjsHostScript>[
    QuickjsHostScript(
      name: 'mount:example-initial.js',
      globals: <String>['initialMountValue'],
      source: 'globalThis.initialMountValue = 21;',
    ),
  ],
  modules: <QuickjsHostModule>[
    QuickjsHostModule.esModule(
      specifier: 'example/initial',
      source: 'export const value = 21;',
    ),
  ],
);

class HostMountsPage extends StatefulWidget {
  const HostMountsPage({super.key});

  @override
  State<HostMountsPage> createState() => _HostMountsPageState();
}

class _HostMountsPageState extends State<HostMountsPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  bool _runtimeMounted = false;
  String _status = '正在创建带初始化 mount 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _runtimeMounted = false;
      _status = '正在创建带初始化 mount 的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();
      final quickjs = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[_initialMount],
        ),
      );
      if (!mounted || _disposed) {
        await quickjs.dispose();
        return;
      }
      setState(() {
        _quickjs = quickjs;
        _busy = false;
        _status = 'runtime 已就绪：example-initial 已挂载';
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

  Future<void> _checkInitialMount() async {
    await _capture('检查初始化挂载', () async {
      final quickjs = _requireRuntime();
      await quickjs.evalModule('''
import { value } from "example/initial";
globalThis.initialModuleValue = value;
''', name: 'example:mount-initial.mjs');
      final result = await quickjs.eval(
        'initialMountValue + "/" + initialModuleValue',
      );
      _log.insert(0, '初始化 mount => $result');
      _status = '环境补全和 ES module 已通过 mounts 批量安装';
    });
  }

  Future<void> _mountRuntimeBundle() async {
    await _capture('运行时批量挂载', () async {
      final quickjs = _requireRuntime();
      await quickjs.mount(_runtimeMount(2));
      final result = await _evaluateRuntimeMount(quickjs);
      _runtimeMounted = true;
      _log.insert(0, 'Quickjs.mount() => $result');
      _status = '运行时 mount 已通过重建生效，初始化 mount 同时恢复';
    });
  }

  Future<void> _replaceRuntimeBundle() async {
    await _capture('替换运行时挂载', () async {
      final quickjs = _requireRuntime();
      await quickjs.mount(
        _runtimeMount(3),
        conflictPolicy: QuickjsHostMountConflictPolicy.replace,
      );
      final result = await _evaluateRuntimeMount(quickjs);
      _log.insert(0, 'replace mount => $result');
      _status = '同名 runtime mount 已原子替换并通过重建生效';
    });
  }

  QuickjsHostMount _runtimeMount(int multiplier) {
    return QuickjsHostMount(
      name: 'example-runtime',
      providers: <QuickjsHostProvider>[
        QuickjsHostProvider.async(
          name: 'example.double',
          callback: (args, _) => (args.single! as num).toInt() * multiplier,
        ),
      ],
      environmentPatches: const <QuickjsHostScript>[
        QuickjsHostScript(
          name: 'mount:example-runtime.js',
          globals: <String>['runtimeApi'],
          source: '''
globalThis.runtimeApi = {
  double(value) {
    return globalThis.__quickjsHostProviders['example.double'](value);
  },
};
''',
        ),
      ],
      modules: <QuickjsHostModule>[
        QuickjsHostModule.esModule(
          specifier: 'example/runtime',
          source: 'export const label = "runtime-module-$multiplier";',
        ),
      ],
    );
  }

  Future<String> _evaluateRuntimeMount(Quickjs quickjs) async {
    await quickjs.evalModule('''
import { label } from "example/runtime";
globalThis.runtimeModuleLabel = label;
''', name: 'example:mount-runtime.mjs');
    return quickjs.evalAsync(
      'return initialMountValue + "/" + runtimeModuleLabel + "/" + await runtimeApi.double(21);',
    );
  }

  Future<void> _checkConflictRollback() async {
    await _capture('检查冲突回滚', () async {
      final quickjs = _requireRuntime();
      try {
        await quickjs.mount(const QuickjsHostMount(name: 'example-initial'));
        throw StateError('重复 mount 未被拒绝');
      } on JsValueConversionException catch (error) {
        final value = await quickjs.eval('initialMountValue');
        _log.insert(0, '重复 mount 被拒绝：${error.message}\nruntime 仍可用 => $value');
        _status = '冲突在重建前被拒绝，当前 runtime 未受影响';
      }
    });
  }

  Future<void> _showDebugSnapshot() async {
    await _capture('查看挂载列表', () async {
      final snapshot = await _requireRuntime().debugInspect();
      final providers = snapshot.providerDetails
          .map(
            (provider) => '${provider.name} [${provider.implementation.name}]',
          )
          .join('\n');
      _log.insert(
        0,
        'registeredMounts:\n${snapshot.registeredMounts.join('\n')}'
        '\nproviders:\n${providers.isEmpty ? '(none)' : providers}',
      );
      _status = 'debugInspect 可查看 mounts 和 provider 来源';
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
      final expression = _runtimeMounted
          ? 'initialMountValue + "/" + typeof runtimeApi.double'
          : 'initialMountValue + "/" + typeof runtimeApi';
      final result = await quickjs.eval(expression);
      _log.insert(0, 'stop 后 mounts => $result');
      _status = 'stop 重建后已挂载能力自动恢复';
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
      appBar: AppBar(title: const Text('能力批量挂载')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('QuickjsRuntimeOptions.mounts + Quickjs.mount()'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _checkInitialMount,
                  child: const Text('检查初始化挂载'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime || _runtimeMounted
                      ? null
                      : _mountRuntimeBundle,
                  child: const Text('运行时挂载'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime || !_runtimeMounted
                      ? null
                      : _replaceRuntimeBundle,
                  child: const Text('替换运行时挂载'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _checkConflictRollback,
                  child: const Text('检查冲突回滚'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _showDebugSnapshot,
                  child: const Text('查看挂载列表'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runStopRecovery,
                  child: const Text('stop 后恢复'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _createRuntime,
                  child: const Text('重建 runtime'),
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
                    ? const Center(child: Text('点击按钮验证批量挂载行为'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Text(_log[index]),
                        ),
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
