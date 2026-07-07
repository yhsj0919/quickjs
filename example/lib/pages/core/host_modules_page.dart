import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

const _hostMathModule = QuickjsHostModule.esModule(
  specifier: 'app/math',
  source: '''
export const value = 41;
export function add(a, b) {
  return a + b;
}
''',
);

const _hostPackageMainModule = QuickjsHostModule.esModule(
  specifier: 'pkg/main',
  source: '''
import { value } from "./dep";
export const result = value + 1;
''',
);

const _hostPackageDepModule = QuickjsHostModule.esModule(
  specifier: 'pkg/dep',
  source: '''
export const value = 9;
''',
);

const _hostBufferModule = QuickjsHostModule.esModule(
  specifier: 'buffer',
  source: '''
export const label = "host-buffer";
export function byteLength(value) {
  return String(value).length;
}
''',
);

const _hostCommonJsModule = QuickjsHostModule.commonJs(
  specifier: 'app/cjs',
  source: '''
const local = require("./local");
module.exports = {
  value: local.value + 1,
};
''',
);

const _hostCommonJsLocalModule = QuickjsHostModule.commonJs(
  specifier: 'app/local',
  source: '''
module.exports = { value: 6 };
''',
);

const _hostCounterModule = QuickjsHostModule.esModule(
  specifier: 'app/counter',
  source: '''
globalThis.hostModuleImportCount = (globalThis.hostModuleImportCount || 0) + 1;
export const count = globalThis.hostModuleImportCount;
''',
);

const _hostCommonJsCounterModule = QuickjsHostModule.commonJs(
  specifier: 'app/cjs-counter',
  source: '''
globalThis.hostCommonJsImportCount = (globalThis.hostCommonJsImportCount || 0) + 1;
exports.count = globalThis.hostCommonJsImportCount;
''',
);

/// 宿主模块注册示例：ES module 与 CommonJS 注入。
class HostModulesPage extends StatefulWidget {
  const HostModulesPage({super.key});

  @override
  State<HostModulesPage> createState() => _HostModulesPageState();
}

class _HostModulesPageState extends State<HostModulesPage> {
  Quickjs? _quickjs;
  bool _disposed = false;
  bool _busy = false;
  String _status = '正在创建启用 modules 的 runtime...';
  final List<String> _log = <String>[];

  @override
  void initState() {
    super.initState();
    unawaited(_createRuntime());
  }

  Future<void> _createRuntime() async {
    setState(() {
      _busy = true;
      _status = '正在创建启用 modules 的 runtime...';
      _log.clear();
    });

    try {
      final previous = _quickjs;
      _quickjs = null;
      await previous?.dispose();

      final quickjs = await Quickjs.create(
        options: const QuickjsRuntimeOptions(
          modules: <QuickjsHostModule>[
            _hostMathModule,
            _hostPackageMainModule,
            _hostPackageDepModule,
            _hostBufferModule,
            _hostCommonJsModule,
            _hostCommonJsLocalModule,
            _hostCounterModule,
            _hostCommonJsCounterModule,
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
        _status = 'runtime 已就绪：modules 只能通过 import / require 使用';
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

  Future<void> _runEsModule() async {
    await _capture('ES module 导入', () async {
      await _requireRuntime().evalModule('''
import { value, add } from "app/math";
globalThis.hostModuleDemo = add(value, 1);
''', name: 'example:host-module-esm.js');
      final result = await _requireRuntime().eval('globalThis.hostModuleDemo');
      _log.insert(0, '导入 "app/math" => $result');
      _status = 'ES host module 已加载';
    });
  }

  Future<void> _runRelativeDependency() async {
    await _capture('相对依赖', () async {
      await _requireRuntime().evalModule('''
import { result } from "pkg/main";
globalThis.hostPackageDemo = result;
''', name: 'example:host-module-relative.js');
      final result = await _requireRuntime().eval('globalThis.hostPackageDemo');
      _log.insert(0, '导入 "pkg/main"，内部依赖 ./dep => $result');
      _status = '相对 host module 依赖已加载';
    });
  }

  Future<void> _runNodePrefix() async {
    await _capture('node: 前缀', () async {
      await _requireRuntime().evalModule('''
import { label, byteLength } from "node:buffer";
globalThis.hostNodeBufferDemo = label + "/" + byteLength("demo");
''', name: 'example:host-module-node-prefix.js');
      final result = await _requireRuntime().eval(
        'globalThis.hostNodeBufferDemo',
      );
      _log.insert(0, '导入 "node:buffer" => $result');
      _status = 'node: 前缀已归一化到 canonical host module';
    });
  }

  Future<void> _runCommonJs() async {
    await _capture('CommonJS require', () async {
      final result = await _requireRuntime().evalCommonJs(
        'const cjs = require("app/cjs"); module.exports = cjs.value;',
        name: 'example:host-module-cjs.js',
      );
      _log.insert(0, 'require("app/cjs") => $result');
      _status = 'CommonJS host module 已加载';
    });
  }

  Future<void> _runGlobalCheck() async {
    await _capture('全局污染检查', () async {
      final result = await _requireRuntime().eval('''
typeof Buffer === "undefined" &&
typeof hostBuffer === "undefined" &&
typeof add === "undefined" &&
typeof value === "undefined" &&
typeof label === "undefined" &&
typeof byteLength === "undefined"
''');
      _log.insert(0, 'host modules 默认不会安装全局变量 => $result');
      _status = 'host modules 在 import / require 之前保持模块作用域';
    });
  }

  Future<void> _runCacheCheck() async {
    await _capture('模块缓存检查', () async {
      final quickjs = _requireRuntime();
      final suffix = DateTime.now().microsecondsSinceEpoch;
      await quickjs.evalModule('''
import { count as first } from "app/counter";
import { count as second } from "app/counter";
globalThis.hostModuleCacheDemo = first + "/" + second + "/" + globalThis.hostModuleImportCount;
''', name: 'example:host-module-cache-$suffix.js');
      final esm = await quickjs.eval('globalThis.hostModuleCacheDemo');
      final cjs = await quickjs.evalCommonJs('''
const first = require("app/cjs-counter");
const second = require("app/cjs-counter");
module.exports = first.count + "/" + second.count + "/" + globalThis.hostCommonJsImportCount;
''', name: 'example:host-module-cache-$suffix.cjs');
      _log.insert(0, 'ESM 缓存 => $esm\nCommonJS 缓存 => $cjs');
      _status = '同一 runtime 内同名 host module 只执行一次';
    });
  }

  Future<void> _runDebugSnapshot() async {
    await _capture('debugInspect 模块列表', () async {
      final snapshot = await _requireRuntime().debugInspect();
      final names = snapshot.moduleNames
          .where(
            (name) =>
                name.startsWith('app/') ||
                name.startsWith('pkg/') ||
                name == 'buffer',
          )
          .toList();
      _log.insert(0, 'debugInspect().moduleNames:\n${names.join('\n')}');
      _status = 'debugInspect 可看到已注册和已加载的 host modules';
    });
  }

  Future<void> _runEssentialBuffer() async {
    await _capture('essential Buffer', () async {
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.essential(globalBuffer: true),
          ],
        ),
      );
      try {
        await quickjs.evalModule('''
import { Buffer } from "node:buffer";
globalThis.essentialBufferModuleDemo =
  Buffer.isBuffer(Buffer.from("module")) + "/" +
  Buffer.from("module").toString() + "/" +
  Buffer.byteLength("module");
''', name: 'example:essential-buffer.mjs');
        final moduleResult = await quickjs.eval(
          'globalThis.essentialBufferModuleDemo',
        );
        final globalResult = await quickjs.eval(
          'Buffer.isBuffer(Buffer.from("global")) + "/" + Buffer.from("global").toString()',
        );
        _log.insert(
          0,
          'essential import "node:buffer" => $moduleResult\n'
          'essential global Buffer => $globalResult',
        );
        _status = 'QuickjsHostMount.essential() 的 Buffer 可用';
      } finally {
        await quickjs.dispose();
      }
    });
  }

  Future<void> _runNodePreset() async {
    await _capture('node preset', () async {
      final quickjs = await Quickjs.create(
        options: QuickjsRuntimeOptions(
          mounts: <QuickjsHostMount>[
            QuickjsHostMount.node(
              globalBuffer: true,
              globalProcess: true,
              env: <String, String>{'APP_ENV': 'example'},
              cwd: '/example',
            ),
          ],
        ),
      );
      try {
        await quickjs.evalModule('''
import { Buffer } from "node:buffer";
import path from "node:path";
import process from "node:process";
import { setTimeout } from "node:timers";
globalThis.nodePresetDemo = [
  Buffer.from("node").toString(),
  path.join("/app", "src", "..", "main.js"),
  process.env.APP_ENV,
  process.cwd(),
  typeof setTimeout,
  typeof globalThis.Buffer,
  typeof globalThis.process
].join("/");
''', name: 'example:node-preset.mjs');
        final result = await quickjs.eval('globalThis.nodePresetDemo');
        _log.insert(0, 'QuickjsHostMount.node() => $result');
        _status = 'node preset provides buffer/path/process/timers modules';
      } finally {
        await quickjs.dispose();
      }
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
      await quickjs.evalModule('''
import { value, add } from "app/math";
globalThis.hostModuleAfterStop = add(value, 1);
''', name: 'example:host-module-after-stop.js');
      final result = await quickjs.eval('globalThis.hostModuleAfterStop');
      _log.insert(0, 'stop 后再次导入 "app/math" => $result');
      _status = 'stop / rebuild 后 modules 已重新可用';
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
      appBar: AppBar(title: const Text('宿主模块')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(_status),
            const SizedBox(height: 8),
            const Text(
              'QuickjsRuntimeOptions.modules + '
              'QuickjsHostModule.esModule/commonJs',
            ),
            const SizedBox(height: 16),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                FilledButton(
                  onPressed: _busy || !hasRuntime ? null : _runEsModule,
                  child: const Text('导入 app/math'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime
                      ? null
                      : _runRelativeDependency,
                  child: const Text('相对导入'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runNodePrefix,
                  child: const Text('导入 node:buffer'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runCommonJs,
                  child: const Text('require app/cjs'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runGlobalCheck,
                  child: const Text('检查全局变量'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runCacheCheck,
                  child: const Text('检查缓存'),
                ),
                OutlinedButton(
                  onPressed: _busy || !hasRuntime ? null : _runDebugSnapshot,
                  child: const Text('查看模块列表'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runEssentialBuffer,
                  child: const Text('essential Buffer'),
                ),
                OutlinedButton(
                  onPressed: _busy ? null : _runNodePreset,
                  child: const Text('node preset'),
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
                    ? const Center(child: Text('点击按钮验证宿主模块行为'))
                    : ListView.builder(
                        padding: const EdgeInsets.all(12),
                        itemCount: _log.length,
                        itemBuilder: (context, index) {
                          return Padding(
                            padding: const EdgeInsets.only(bottom: 8),
                            child: Text(_log[index]),
                          );
                        },
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
