import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiNavigationPage extends StatefulWidget {
  const QuickjsUiNavigationPage({super.key});

  static const String detailPath =
      'assets/quickjs_ui/navigation_detail_page.mjs';
  static const String childPath = 'assets/quickjs_ui/navigation_child_page.mjs';

  @override
  State<QuickjsUiNavigationPage> createState() =>
      _QuickjsUiNavigationPageState();
}

class _QuickjsUiNavigationPageState extends State<QuickjsUiNavigationPage> {
  String _result = '等待 JSUI 页面返回';
  String _policyLog = '等待 JSUI 内部跳转请求';
  final Set<String> _trustedJsuiPaths = <String>{};

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('QuickJS UI 页面互通')),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: <Widget>[
          Text('原生列表页', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          const Text(
            '此页验证原生 Flutter -> JSUI -> 原生 Flutter -> route result 回传。',
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: <Widget>[
                  const Text('JSUI 内部跳转策略'),
                  const SizedBox(height: 6),
                  Text(_policyLog),
                  const SizedBox(height: 6),
                  Text(
                    _trustedJsuiPaths.isEmpty
                        ? '尚未记住任何页面授权'
                        : '已始终允许：${_trustedJsuiPaths.join(', ')}',
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          ListTile(
            title: const Text('打开 JSUI 详情页'),
            subtitle: const Text('itemId: 42'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _openDetail(context),
          ),
          const SizedBox(height: 12),
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text('返回结果：$_result'),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _openDetail(BuildContext context) async {
    final result = await QuickjsUiNavigator.pushAsset(
      context,
      title: 'JSUI 详情',
      path: QuickjsUiNavigationPage.detailPath,
      initialProps: const <String, Object?>{'itemId': 42, 'title': '来自原生列表页'},
      transition: const QuickjsUiRouteTransition.fade(
        duration: Duration(milliseconds: 180),
      ),
      onConsole: (event) {
        debugPrint(
          '[quickjs_ui navigation console.${event.level.name}] ${event.text}',
        );
      },
      routeRegistry: _routeRegistry(),
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _result = '$result';
    });
  }

  QuickjsUiRouteRegistry _routeRegistry() {
    return QuickjsUiRouteRegistry(
      nativeRoutes: <String, QuickjsUiNativeRouteBuilder>{
        'quickjs-ui.navigation.settings': (context, params) =>
            _NativeSettingsPage(params: params),
      },
      jsRoutePolicy: QuickjsUiJsRoutePolicy(
        allowedPaths: const <String>{QuickjsUiNavigationPage.childPath},
        onRequest: _handleJsRouteRequest,
      ),
    );
  }

  Future<bool> _handleJsRouteRequest(QuickjsUiJsRouteRequest request) async {
    if (_trustedJsuiPaths.contains(request.resolvedPath)) {
      final message =
          '已记住并允许 ${request.action}: '
          '${request.resolvedPath} <- ${request.from}';
      debugPrint('[quickjs_ui navigation policy] $message');
      if (mounted) {
        setState(() {
          _policyLog = message;
        });
      }
      return true;
    }

    final decision = await showDialog<_JsuiRouteDecision>(
      context: context,
      builder: (context) {
        return AlertDialog(
          title: const Text('允许 JSUI 内部跳转？'),
          content: Text(
            '来源：${request.from}\n'
            '目标：${request.resolvedPath}\n'
            '动作：${request.action}',
          ),
          actions: <Widget>[
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_JsuiRouteDecision.deny),
              child: const Text('禁止'),
            ),
            TextButton(
              onPressed: () =>
                  Navigator.of(context).pop(_JsuiRouteDecision.allowOnce),
              child: const Text('仅本次允许'),
            ),
            FilledButton(
              onPressed: () =>
                  Navigator.of(context).pop(_JsuiRouteDecision.allowPath),
              child: const Text('始终允许此页面'),
            ),
          ],
        );
      },
    );
    final allowed =
        decision == _JsuiRouteDecision.allowOnce ||
        decision == _JsuiRouteDecision.allowPath;
    if (decision == _JsuiRouteDecision.allowPath && mounted) {
      setState(() {
        _trustedJsuiPaths.add(request.resolvedPath);
      });
    }
    final message =
        '${allowed ? '允许' : '拒绝'} ${request.action}: '
        '${request.resolvedPath} <- ${request.from}'
        '${decision == _JsuiRouteDecision.allowPath ? '（已记住）' : ''}';
    debugPrint('[quickjs_ui navigation policy] $message');
    if (mounted) {
      setState(() {
        _policyLog = message;
      });
    }
    return allowed;
  }
}

enum _JsuiRouteDecision { deny, allowOnce, allowPath }

class _NativeSettingsPage extends StatelessWidget {
  const _NativeSettingsPage({required this.params});

  final Map<String, Object?> params;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('原生设置页')),
      body: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: <Widget>[
            const Text('此页由 JSUI navigationIntent 打开。'),
            const SizedBox(height: 12),
            SelectableText('params: $params'),
            const SizedBox(height: 12),
            FilledButton(
              onPressed: () {
                Navigator.of(context).pop(<String, Object?>{
                  'saved': true,
                  'itemId': params['itemId'],
                  'source': params['source'],
                });
              },
              child: const Text('保存并返回结果'),
            ),
          ],
        ),
      ),
    );
  }
}
