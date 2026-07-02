import 'package:flutter/material.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

class QuickjsUiNavigationPage extends StatefulWidget {
  const QuickjsUiNavigationPage({super.key});

  static const String detailPath =
      'assets/quickjs_ui/navigation_detail_page.mjs';

  @override
  State<QuickjsUiNavigationPage> createState() =>
      _QuickjsUiNavigationPageState();
}

class _QuickjsUiNavigationPageState extends State<QuickjsUiNavigationPage> {
  String _result = '等待 JSUI 页面返回';

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
    final registry = _routeRegistry(context);
    final result = await QuickjsUiNavigator.pushAsset(
      context,
      title: 'JSUI 详情',
      path: QuickjsUiNavigationPage.detailPath,
      initialProps: const <String, Object?>{'itemId': 42, 'title': '来自原生列表页'},
      routeRegistry: registry,
    );
    if (!mounted) {
      return;
    }
    setState(() {
      _result = '$result';
    });
  }
}

QuickjsUiRouteRegistry _routeRegistry(BuildContext context) {
  return QuickjsUiRouteRegistry(
    nativeRoutes: <String, QuickjsUiNativeRouteBuilder>{
      'quickjs-ui.navigation.settings': (context, params) =>
          _NativeSettingsPage(params: params),
    },
  );
}

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
