import 'example_page_spec.dart';
import 'pages/quickjs_ui/integrated/quickjs_ui_weather_demo_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_bundle_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_controls_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_custom_components_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_dev_panel_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_diff_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_error_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_host_capabilities_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_navigation_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_capability_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_inspector_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_package_demo_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_permission_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_profile_form_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_schema_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_scroll_transition_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_todo_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_video_player_plugin_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_widgets_demo_page.dart';

final List<ExamplePageSpec> quickjsUiExamplePages = [
  ...quickjsUiCoreExamplePages,
  ...quickjsUiWidgetExamplePages,
  ...quickjsUiIntegratedExamplePages,
];

final List<ExamplePageSpec> quickjsUiCoreExamplePages =
    const <ExamplePageSpec>[];

final List<ExamplePageSpec> quickjsUiWidgetExamplePages = [
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
    title: 'QuickJS UI 局部刷新',
    description: '可视化 stable key 节点在局部刷新中被跳过、变化节点重新构建。',
    builder: (_) => const QuickjsUiDiffPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 权限策略',
    description: '单独测试页面声明 permissions、unrestricted 策略和 restricted 授权拦截。',
    builder: (_) => const QuickjsUiPermissionPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 0.4.3 开发调试',
    description: '演示 Inspector 面板、页面快照导出、diff/resource 日志和保留 state 的热重载。',
    builder: (_) => const QuickjsUiDevPanelPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 0.5 发布包',
    description: '演示固定包根 main.mjs + manifest.json 的 asset 发布包加载和校验。',
    builder: (_) => const QuickjsUiPackageDemoPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 控件演示',
    description:
        '测试 Image、ListView、TextField、Stack、Padding、Center、SizedBox 等 0.2 控件。',
    builder: (_) => const QuickjsUiControlsPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 自定义组件',
    description: '演示 JS Component()、Dart 自定义 renderer、表单控件、事件描述符和基础隐式动画。',
    builder: (_) => const QuickjsUiCustomComponentsPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI VideoPlayer 插件',
    description:
        '演示第三方 quickjs_ui 插件，通过 quickjs_ui/video_player 暴露 VideoPlayer 组件。',
    builder: (_) => const QuickjsUiVideoPlayerPluginPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 0.4.2 滚动与过渡',
    description:
        '演示 scrollTo key/offset、drag/swipe 事件、SingleChildScrollView 和 keyed 列表项过渡。',
    builder: (_) => const QuickjsUiScrollTransitionPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 0.6 基础控件',
    description:
        '演示 Scaffold、AppBar、TabBar、GridView、PageView、RefreshIndicator、AlertDialog 等 0.6 内置控件。',
    builder: (_) => const QuickjsUiWidgetsDemoPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 待办列表',
    description: '实际列表场景：ListView、TextField、事件、受控输入和 ThemeData token。',
    builder: (_) => const QuickjsUiTodoPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 资料表单',
    description: '实际表单场景：受控输入、focus/blur、submit 和预览。',
    builder: (_) => const QuickjsUiProfileFormPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 网络计数器',
    description: '通过本地开发服务器按 network URL 加载 quickjs_ui 页面并渲染。',
    builder: (_) => const QuickjsUiNetworkCounterPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 网络能力',
    description:
        '注入 QuickjsFetchMount 与 Axios 1.6.2，在 JS 页面内用 axios 加载远程 JSON 并展示。',
    builder: (_) => const QuickjsUiNetworkCapabilityPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 宿主能力',
    description: '通过 QuickjsUiHostCapabilities 组合系统默认能力和自定义宿主调用。',
    builder: (_) => const QuickjsUiHostCapabilitiesPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 页面互通',
    description: '测试原生 Flutter 页面、JSUI 页面、原生设置页之间的参数和结果回传。',
    builder: (_) => const QuickjsUiNavigationPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 网络调试',
    description: '演示 bundle 网络加载请求列表、缓存命中、耗时和 Inspector 网络面板。',
    builder: (_) => const QuickjsUiNetworkInspectorPage(),
  ),
];

final List<ExamplePageSpec> quickjsUiIntegratedExamplePages = [
  ExamplePageSpec(
    title: 'QuickJS UI 天气综合 Demo',
    description: '实际天气卡片场景：IP 定位、刷新、当前天气、小时预报和生活提示。',
    builder: (_) => const QuickjsUiWeatherDemoPage(),
  ),
];
