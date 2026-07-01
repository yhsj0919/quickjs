import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiPermissionPage extends StatefulWidget {
  const QuickjsUiPermissionPage({super.key});

  static const String path = 'assets/quickjs_ui/permission_page.mjs';
  static const List<String> declaredPermissions = <String>[
    'toast',
    'app.customEcho',
  ];

  @override
  State<QuickjsUiPermissionPage> createState() =>
      _QuickjsUiPermissionPageState();
}

class _QuickjsUiPermissionPageState extends State<QuickjsUiPermissionPage> {
  final Map<_PermissionCase, _PermissionResult> _results =
      <_PermissionCase, _PermissionResult>{};

  @override
  void initState() {
    super.initState();
    unawaited(_runCases());
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 权限策略')),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            for (final permissionCase in _PermissionCase.values) ...<Widget>[
              _PermissionCaseCard(
                permissionCase: permissionCase,
                result: _results[permissionCase],
              ),
              if (permissionCase != _PermissionCase.values.last)
                const SizedBox(height: 12),
            ],
          ],
        ),
      ),
    );
  }

  Future<void> _runCases() async {
    for (final permissionCase in _PermissionCase.values) {
      final result = await _runCase(permissionCase);
      if (!mounted) {
        return;
      }
      setState(() {
        _results[permissionCase] = result;
      });
    }
  }

  Future<_PermissionResult> _runCase(_PermissionCase permissionCase) async {
    final controller = QuickjsUiController();
    try {
      final plugin = await QuickjsUiPagePlugin.asset(
        id: permissionCase.pluginId,
        version: '0.3.0',
        path: QuickjsUiPermissionPage.path,
        permissions: QuickjsUiPermissionPage.declaredPermissions,
      );
      await controller.loadPlugin(
        plugin,
        permissionPolicy: permissionCase.policy,
        grantedPermissions: permissionCase.grantedPermissions,
        initialProps: <String, Object?>{
          'policyName': permissionCase.policyName,
          'permissions': QuickjsUiPermissionPage.declaredPermissions,
        },
      );
      final error = controller.error;
      if (error != null) {
        return _PermissionResult.error(error);
      }
      return _PermissionResult.loaded(controller.node);
    } catch (error) {
      return _PermissionResult.error(error);
    } finally {
      controller.dispose();
    }
  }
}

class _PermissionCaseCard extends StatelessWidget {
  const _PermissionCaseCard({required this.permissionCase, this.result});

  final _PermissionCase permissionCase;
  final _PermissionResult? result;

  @override
  Widget build(BuildContext context) {
    final result = this.result;
    final node = result?.node;
    final error = result?.error;
    final resultText = error != null
        ? '已拦截'
        : node != null
        ? '已加载'
        : '等待加载';
    final preview = error != null
        ? _PermissionError(error: error)
        : node == null
        ? const Center(child: CircularProgressIndicator())
        : QuickjsUiRenderer(onEvent: (_) {}).build(node, buildContext: context);

    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            Text(
              permissionCase.title,
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: 4),
            Text(permissionCase.description),
            const SizedBox(height: 4),
            Text('结果：${permissionCase.title} $resultText'),
            const SizedBox(height: 12),
            SizedBox(height: 300, child: preview),
          ],
        ),
      ),
    );
  }
}

class _PermissionResult {
  const _PermissionResult.loaded(this.node) : error = null;
  const _PermissionResult.error(this.error) : node = null;

  final QuickjsUiNode? node;
  final Object? error;
}

class _PermissionError extends StatelessWidget {
  const _PermissionError({required this.error});

  final Object error;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.errorContainer,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Text(
          '权限拦截：$error',
          style: TextStyle(
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
        ),
      ),
    );
  }
}

enum _PermissionCase {
  unrestricted(
    title: '不限制策略',
    description: '不传 permissionPolicy，页面声明权限不会阻止加载。',
    policyName: 'unrestricted',
  ),
  allowed(
    title: '限制策略：允许',
    description: '页面声明权限同时存在于 allowed 和 grantedPermissions，加载成功。',
    policyName: 'restricted allowed',
  ),
  denied(
    title: '限制策略：拒绝',
    description: '页面声明了 app.customEcho，但宿主只授予 toast，加载会被拦截。',
    policyName: 'restricted denied',
  );

  const _PermissionCase({
    required this.title,
    required this.description,
    required this.policyName,
  });

  final String title;
  final String description;
  final String policyName;

  String get pluginId {
    final suffix = policyName.replaceAll(RegExp(r'[^a-zA-Z0-9_]'), '_');
    return 'quickjs_ui_permission_$suffix';
  }

  QuickjsUiPermissionPolicy? get policy {
    return switch (this) {
      _PermissionCase.unrestricted => null,
      _PermissionCase.allowed => QuickjsUiPermissionPolicy.restricted(
        allowed: QuickjsUiPermissionPage.declaredPermissions,
      ),
      _PermissionCase.denied => QuickjsUiPermissionPolicy.restricted(
        allowed: const <String>['toast'],
      ),
    };
  }

  Iterable<String> get grantedPermissions {
    return switch (this) {
      _PermissionCase.unrestricted => const <String>[],
      _PermissionCase.allowed => QuickjsUiPermissionPage.declaredPermissions,
      _PermissionCase.denied => const <String>['toast'],
    };
  }
}
