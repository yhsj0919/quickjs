import 'example_page_spec.dart';
import 'pages/quickjs_ui_bundle_counter_page.dart';
import 'pages/quickjs_ui_counter_page.dart';
import 'pages/quickjs_ui_network_counter_page.dart';

final List<ExamplePageSpec> quickjsUiExamplePages = [
  ExamplePageSpec(
    title: 'QuickJS UI Counter',
    description: '加载单文件 quickjs_ui Page(.mjs)，并使用原生 Flutter Widget 渲染。',
    builder: (_) => const QuickjsUiCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI Bundle Counter',
    description: '从入口 .mjs 加载多文件 quickjs_ui 页面，自动解析相对 import 后渲染。',
    builder: (_) => const QuickjsUiBundleCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI Network Counter',
    description: '通过本地开发服务器按 network URL 加载 quickjs_ui 页面并渲染。',
    builder: (_) => const QuickjsUiNetworkCounterPage(),
  ),
];
