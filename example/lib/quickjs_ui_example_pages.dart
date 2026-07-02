import 'example_page_spec.dart';
import 'pages/quickjs_ui_bundle_counter_page.dart';
import 'pages/quickjs_ui_counter_page.dart';
import 'pages/quickjs_ui_controls_page.dart';
import 'pages/quickjs_ui_diff_page.dart';
import 'pages/quickjs_ui_error_page.dart';
import 'pages/quickjs_ui_host_capabilities_page.dart';
import 'pages/quickjs_ui_navigation_page.dart';
import 'pages/quickjs_ui_network_counter_page.dart';
import 'pages/quickjs_ui_permission_page.dart';
import 'pages/quickjs_ui_profile_form_page.dart';
import 'pages/quickjs_ui_schema_page.dart';
import 'pages/quickjs_ui_todo_page.dart';

final List<ExamplePageSpec> quickjsUiExamplePages = [
  ExamplePageSpec(
    title: 'QuickJS UI 计数器',
    description: '加载单文件 quickjs_ui Page(.mjs)，并使用原生 Flutter Widget 渲染。',
    builder: (_) => const QuickjsUiCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 多文件计数器',
    description: '从入口 .mjs 加载多文件 quickjs_ui 页面，自动解析相对 import 后渲染。',
    builder: (_) => const QuickjsUiBundleCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 控件演示',
    description:
        '测试 Image、ListView、TextField、Stack、Padding、Center、SizedBox 等 0.2 控件。',
    builder: (_) => const QuickjsUiControlsPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 待办列表',
    description: '使用 JS 页面测试 ListView、TextField、事件、受控输入和 ThemeData token。',
    builder: (_) => const QuickjsUiTodoPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 资料表单',
    description: '使用 JS 页面测试 profile 表单、受控输入、focus/blur、submit 和预览。',
    builder: (_) => const QuickjsUiProfileFormPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI JSON Schema',
    description: '从纯 JSON UI schema asset 解析 QuickjsUiNode，并不经过 JS 直接渲染。',
    builder: (_) => const QuickjsUiSchemaPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 错误浮层',
    description: '展示 quickjs_ui schema、resource、route 和 action 错误定位信息。',
    builder: (_) => const QuickjsUiErrorPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 网络计数器',
    description: '通过本地开发服务器按 network URL 加载 quickjs_ui 页面并渲染。',
    builder: (_) => const QuickjsUiNetworkCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 局部刷新',
    description: '可视化 stable key 节点在局部刷新中被跳过、变化节点重新构建。',
    builder: (_) => const QuickjsUiDiffPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 宿主能力',
    description: '通过 QuickjsUiHostCapabilities 组合系统默认能力和自定义宿主调用。',
    builder: (_) => const QuickjsUiHostCapabilitiesPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 权限策略',
    description: '单独测试页面声明 permissions、unrestricted 策略和 restricted 授权拦截。',
    builder: (_) => const QuickjsUiPermissionPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 页面互通',
    description: '测试原生 Flutter 页面、JSUI 页面、原生设置页之间的参数和结果回传。',
    builder: (_) => const QuickjsUiNavigationPage(),
  ),
];
