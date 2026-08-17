import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

/// 0.6 基础控件 Demo：Scaffold、AppBar、TabBar、GridView、PageView、
/// RefreshIndicator、AlertDialog 等内置控件。
class JsUiWidgetsDemoPage extends StatefulWidget {
  const JsUiWidgetsDemoPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/widgets_demo_page.mjs';

  @override
  State<JsUiWidgetsDemoPage> createState() => _JsUiWidgetsDemoPageState();
}

/// 为 Demo 页面注入自定义 `jsUiDemo.back()` 宿主能力。
class _JsUiWidgetsDemoPageState extends State<JsUiWidgetsDemoPage> {
  /// 业务 JS 能力：提供 JS 侧调用原生返回导航的 method。
  late final List<JsFeatures> _features = <JsFeatures>[_backFeatures()];

  @override
  Widget build(BuildContext context) {
    return JsUiView.asset(
      path: JsUiWidgetsDemoPage.path,
      features: _features,
      loadingBuilder: (_) =>
          const Scaffold(body: Center(child: CircularProgressIndicator())),
      errorBuilder: (_, error) => Scaffold(
        appBar: AppBar(title: const Text('页面结构与导航')),
        body: Padding(
          padding: const EdgeInsets.all(16),
          child: SelectableText('QuickJS UI 0.6 error: $error'),
        ),
      ),
    );
  }

  /// 构建 Demo 专用 features：注册 `jsUiDemo.back` 全局对象与对应 method。
  JsFeatures _backFeatures() {
    return JsFeatures(
      name: 'quickjs_ui.example.widgets_demo',
      methods: <JsHostMethod>[
        JsHostMethod(
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
      scripts: const <JsScript>[
        JsScript(
          name: 'quickjs_ui.example.widgets_demo.globals.js',
          globals: <String>['jsUiDemo'],
          source: '''
globalThis.jsUiDemo = Object.freeze({
  back(payload = {}) {
    return globalThis.__jsHostMethods['quickjs_ui.example.widgets_demo.back'](payload);
  }
});
''',
        ),
      ],
    );
  }
}
