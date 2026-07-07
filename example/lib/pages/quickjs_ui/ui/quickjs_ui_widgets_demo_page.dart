import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 0.6 基础控件 Demo：Scaffold、AppBar、TabBar、GridView、PageView、
/// RefreshIndicator、AlertDialog 等内置控件。
class QuickjsUiWidgetsDemoPage extends StatefulWidget {
  const QuickjsUiWidgetsDemoPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/widgets_demo_page.mjs';

  @override
  State<QuickjsUiWidgetsDemoPage> createState() =>
      _QuickjsUiWidgetsDemoPageState();
}

/// 为 Demo 页面注入自定义 `quickjsUiDemo.back()` 宿主能力。
class _QuickjsUiWidgetsDemoPageState extends State<QuickjsUiWidgetsDemoPage> {
  /// 业务 JS 能力：提供 JS 侧调用原生返回导航的 provider。
  late final List<QuickjsHostMount> _mounts = <QuickjsHostMount>[_backMount()];

  @override
  Widget build(BuildContext context) {
    return QuickjsUiView.asset(
      path: QuickjsUiWidgetsDemoPage.path,
      mounts: _mounts,
      loadingBuilder: (_) =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      errorBuilder: (_, error) => Scaffold(
        appBar: AppBar(title: const Text('QuickJS UI 0.6')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI 0.6 error: $error'),
        ),
      ),
    );
  }

  /// 构建 Demo 专用 mount：注册 `quickjsUiDemo.back` 全局对象与对应 provider。
  QuickjsHostMount _backMount() {
    return QuickjsHostMount(
      name: 'quickjs_ui.example.widgets_demo',
      providers: <QuickjsHostProvider>[
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.example.widgets_demo.back',
          callback: (_, _) {
            final navigator = Navigator.of(context);
            if (navigator.canPop()) {
              navigator.pop();
            }
            return true;
          },
        ),
      ],
      environmentPatches: const <QuickjsHostScript>[
        QuickjsHostScript.js(
          name: 'quickjs_ui.example.widgets_demo.globals.js',
          globals: <String>['quickjsUiDemo'],
          source: '''
globalThis.quickjsUiDemo = Object.freeze({
  back(payload = {}) {
    return globalThis.__quickjsHostProviders['quickjs_ui.example.widgets_demo.back'](payload);
  }
});
''',
        ),
      ],
    );
  }
}
