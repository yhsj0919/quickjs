import 'example_page_spec.dart';
import 'pages/quickjs_ui_bundle_counter_page.dart';
import 'pages/quickjs_ui_counter_page.dart';
import 'pages/quickjs_ui_controls_page.dart';
import 'pages/quickjs_ui_error_page.dart';
import 'pages/quickjs_ui_network_counter_page.dart';
import 'pages/quickjs_ui_schema_page.dart';

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
    title: 'QuickJS UI Controls',
    description:
        '测试 Image、ListView、TextField、Stack、Padding、Center、SizedBox 等 0.2 控件。',
    builder: (_) => const QuickjsUiControlsPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI JSON Schema',
    description: '从纯 JSON UI schema asset 解析 QuickjsUiNode，并不经过 JS 直接渲染。',
    builder: (_) => const QuickjsUiSchemaPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI Error Overlay',
    description: '展示 quickjs_ui schema、resource、route 和 action 错误定位信息。',
    builder: (_) => const QuickjsUiErrorPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI Network Counter',
    description: '通过本地开发服务器按 network URL 加载 quickjs_ui 页面并渲染。',
    builder: (_) => const QuickjsUiNetworkCounterPage(),
  ),
];
