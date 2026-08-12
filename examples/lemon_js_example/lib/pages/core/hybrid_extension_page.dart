import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:lemon_js_extensions/lemon_js_extensions.dart';

const _assetRoot = 'assets/extensions/hybrid_demo';

class HybridExtensionPage extends StatefulWidget {
  const HybridExtensionPage({super.key});

  @override
  State<HybridExtensionPage> createState() => _HybridExtensionPageState();
}

class _HybridExtensionPageState extends State<HybridExtensionPage> {
  late final QuickjsExtensionManager _manager = QuickjsExtensionManager(
    store: InMemoryQuickjsExtensionStore(),
    compatibilityRegistry: QuickjsExtensionCompatibilityRegistry(
      <QuickjsExtensionCompatibilityPolicy>[
        QuickjsExtensionCompatibilityPolicy(
          compatibilityCode: 'lemon-content-source-v1',
          requiredPublicExports: const <String>{'getHome'},
        ),
      ],
    ),
  );
  late final Future<_LoadedHybridDemo> _loading = _load();
  InstalledQuickjsExtension? _installed;
  bool _disposed = false;
  bool _callingCore = false;
  bool _hasCoreResult = false;
  Object? _home;
  Object? _coreError;

  Future<_LoadedHybridDemo> _load() async {
    final managed = await _manager.installAsset(
      manifestAsset: '$_assetRoot/manifest.json',
      grantedPermissions: const <String>['storage'],
    );
    final installed = managed.installed!;
    _installed = installed;
    if (_disposed) {
      await _manager.uninstall(installed.id);
      throw StateError('混合插件示例页面已关闭');
    }
    return _LoadedHybridDemo(installed: installed);
  }

  Future<void> _callCore(InstalledQuickjsExtension installed) async {
    setState(() {
      _callingCore = true;
      _coreError = null;
    });
    try {
      final home = await _manager.call(installed.id, 'getHome');
      if (!mounted) return;
      setState(() {
        _home = home;
        _hasCoreResult = true;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _coreError = error);
    } finally {
      if (mounted) setState(() => _callingCore = false);
    }
  }

  @override
  void dispose() {
    _disposed = true;
    final installed = _installed;
    if (installed != null) {
      unawaited(_manager.uninstall(installed.id));
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('混合插件')),
      body: FutureBuilder<_LoadedHybridDemo>(
        future: _loading,
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(child: SelectableText('加载失败：${snapshot.error}'));
          }
          final demo = snapshot.data;
          if (demo == null) {
            return const Center(child: CircularProgressIndicator());
          }
          final flow = _manager.findFlow(demo.installed.id, 'login');
          return ListView(
            padding: const EdgeInsets.all(24),
            children: <Widget>[
              Text(
                '同一安装单元：${demo.installed.extension.kind.name}',
                style: Theme.of(context).textTheme.titleLarge,
              ),
              const SizedBox(height: 12),
              const Text('当前页面由 Flutter 原生渲染，下面两个按钮分别验证 Core 与 JSUI 能力。'),
              const SizedBox(height: 8),
              const Text(
                '调用方向：Flutter → Core / JSUI，JSUI → Core；Core 不可调用 UI。',
              ),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: _callingCore
                    ? null
                    : () => _callCore(demo.installed),
                icon: const Icon(Icons.data_object),
                label: Text(_callingCore ? '调用中…' : '调用插件 Core 方法'),
              ),
              const SizedBox(height: 12),
              OutlinedButton.icon(
                onPressed: flow == null
                    ? null
                    : () => Navigator.of(context).push<void>(
                        MaterialPageRoute<void>(
                          builder: (_) => QuickjsExtensionView.route(
                            session: demo.installed.session,
                            route: flow.route,
                          ),
                        ),
                      ),
                icon: const Icon(Icons.login),
                label: const Text('打开插件 JSUI 登录页'),
              ),
              if (_hasCoreResult || _coreError != null) ...<Widget>[
                const SizedBox(height: 20),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText(
                      _coreError == null
                          ? const JsonEncoder.withIndent('  ').convert(_home)
                          : 'Core 调用失败：$_coreError',
                    ),
                  ),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

final class _LoadedHybridDemo {
  const _LoadedHybridDemo({required this.installed});

  final InstalledQuickjsExtension installed;
}
