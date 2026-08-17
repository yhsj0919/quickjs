import 'dart:async';

import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';

const _initialFeatures = JsFeatures(
  name: 'example-initial',
  scripts: <JsScript>[
    JsScript(
      name: 'features:example-initial.js',
      globals: <String>['initialFeaturesValue'],
      source: 'globalThis.initialFeaturesValue = 21;',
    ),
  ],
  modules: <JsModule>[
    JsModule(name: 'example/initial', source: 'export const value = 21;'),
  ],
);

/// 基础功能 Demo：通过 [JsEngine.create] 的 `features` 参数与 [JsEngine.loadFeatures]
/// 组合加载环境补全、模块与宿主方法。
class FeaturesPage extends StatefulWidget {
  const FeaturesPage({super.key});

  @override
  State<FeaturesPage> createState() => _FeaturesPageState();
}

class _FeaturesPageState extends State<FeaturesPage> {
  JsEngine? _engine;
  bool _disposed = false;
  bool _busy = false;
  bool _runtimeFeaturesLoaded = false;
  String _status = '正在创建带初始化 features 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _runtimeFeaturesLoaded = false;
      _status = '正在创建带初始化 features 的 runtime...';
      _log.clear();
    });

    try {
      final previous = _engine;
      _engine = null;
      await previous?.dispose();
      final engine = await JsEngine.create(
        features: <JsFeatures>[_initialFeatures],
      );
      if (!mounted || _disposed) {
        await engine.dispose();
        return;
      }
      setState(() {
        _engine = engine;
        _busy = false;
        _status = 'runtime 已就绪：example-initial 已加载';
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

  Future<void> _checkInitialFeatures() async {
    await _capture('检查初始化功能', () async {
      final engine = _requireRuntime();
      await engine.runModule('''
import { value } from "example/initial";
globalThis.initialModuleValue = value;
''', name: 'example:features-initial.mjs');
      final result = await engine.eval(
        'initialFeaturesValue + "/" + initialModuleValue',
      );
      _log.insert(0, '初始化 features => $result');
      _status = '环境补全和 ES module 已通过 features 组合加载';
    });
  }

  Future<void> _loadRuntimeFeatures() async {
    await _capture('运行时加载功能', () async {
      final engine = _requireRuntime();
      await engine.loadFeatures(_runtimeFeatures(2));
      final result = await _evaluateRuntimeFeatures(engine);
      _runtimeFeaturesLoaded = true;
      _log.insert(0, 'JsEngine.loadFeatures() => $result');
      _status = '运行时 features 已通过重建生效，初始化 features 同时恢复';
    });
  }

  Future<void> _replaceRuntimeBundle() async {
    await _capture('替换运行时功能', () async {
      final engine = _requireRuntime();
      await engine.loadFeatures(
        _runtimeFeatures(3),
        conflictPolicy: JsFeaturesConflictPolicy.replace,
      );
      final result = await _evaluateRuntimeFeatures(engine);
      _log.insert(0, 'replace features => $result');
      _status = '同名 runtime features 已原子替换并通过重建生效';
    });
  }

  JsFeatures _runtimeFeatures(int multiplier) {
    return JsFeatures(
      name: 'example-runtime',
      methods: <JsHostMethod>[
        JsHostMethod(
          name: 'example.double',
          callback: (args, _) => (args.single! as num).toInt() * multiplier,
        ),
      ],
      scripts: const <JsScript>[
        JsScript(
          name: 'features:example-runtime.js',
          globals: <String>['runtimeApi'],
          source: '''
globalThis.runtimeApi = {
  double(value) {
    return globalThis.__jsHostMethods['example.double'](value);
  },
};
''',
        ),
      ],
      modules: <JsModule>[
        JsModule(
          name: 'example/runtime',
          source: 'export const label = "runtime-module-$multiplier";',
        ),
      ],
    );
  }

  Future<String> _evaluateRuntimeFeatures(JsEngine engine) async {
    await engine.runModule('''
import { label } from "example/runtime";
globalThis.runtimeModuleLabel = label;
''', name: 'example:features-runtime.mjs');
    return engine.runRaw(
      'return initialFeaturesValue + "/" + runtimeModuleLabel + "/" + await runtimeApi.double(21);',
    );
  }

  Future<void> _checkConflictRollback() async {
    await _capture('检查冲突回滚', () async {
      final engine = _requireRuntime();
      try {
        await engine.loadFeatures(const JsFeatures(name: 'example-initial'));
        throw StateError('重复 features 未被拒绝');
      } on JsValueConversionException catch (error) {
        final value = await engine.eval('initialFeaturesValue');
        _log.insert(
          0,
          '重复 features 被拒绝：${error.message}\nruntime 仍可用 => $value',
        );
        _status = '冲突在重建前被拒绝，当前 runtime 未受影响';
      }
    });
  }

  Future<void> _showDebugSnapshot() async {
    await _capture('查看功能列表', () async {
      final snapshot = await _requireRuntime().debugInspect();
      final methods = snapshot.methodDetails
          .map((method) => '${method.name} [${method.implementation.name}]')
          .join('\n');
      _log.insert(
        0,
        'registeredFeatures:\n${snapshot.registeredFeatures.join('\n')}'
        '\nmethods:\n${methods.isEmpty ? '(none)' : methods}',
      );
      _status = 'debugInspect 可查看 features 和 method 来源';
    });
  }

  Future<void> _runStopRecovery() async {
    await _capture('stop 后恢复', () async {
      final engine = _requireRuntime();
      final running = engine
          .eval('while (true) {}')
          .then<Object?>((_) => null, onError: (Object error) => error);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await engine.restart();
      await running;
      final expression = _runtimeFeaturesLoaded
          ? 'initialFeaturesValue + "/" + typeof runtimeApi.double'
          : 'initialFeaturesValue + "/" + typeof runtimeApi';
      final result = await engine.eval(expression);
      _log.insert(0, 'stop 后 features => $result');
      _status = 'stop 重建后已加载功能自动恢复';
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

  JsEngine _requireRuntime() {
    final engine = _engine;
    if (engine == null) {
      throw JsRuntimeClosedException('QuickJS runtime is not ready');
    }
    return engine;
  }

  String _describeError(Object error) {
    if (error is JsException) {
      return '${error.runtimeType}: ${error.message}';
    }
    return '${error.runtimeType}: $error';
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
      appBar: AppBar(title: const Text('基础功能加载')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text('JsEngine.create(features: ...) + loadFeatures()'),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _checkInitialFeatures,
                  child: const Text('检查初始化功能'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime || _runtimeFeaturesLoaded
                      ? null
                      : _loadRuntimeFeatures,
                  child: const Text('运行时加载'),
                ),
                FilledButton.tonal(
                  onPressed: _busy || !hasRuntime || !_runtimeFeaturesLoaded
                      ? null
                      : _replaceRuntimeBundle,
                  child: const Text('替换运行时功能'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _checkConflictRollback,
                  child: const Text('检查冲突回滚'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _showDebugSnapshot,
                  child: const Text('查看功能列表'),
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
                    ? const Center(child: Text('点击按钮验证基础功能加载行为'))
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
