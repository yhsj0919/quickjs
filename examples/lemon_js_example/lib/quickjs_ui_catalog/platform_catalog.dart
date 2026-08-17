import '../example_page_spec.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_custom_components_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_dev_panel_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_diff_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_error_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_host_capabilities_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_navigation_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_network_capability_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_network_inspector_page.dart';
import '../pages/quickjs_ui/platform/quickjs_ui_permission_page.dart';
import 'catalog_helpers.dart';

// Repository rule: append newly created demos to the end of this list.
final List<ExamplePageSpec> jsUiPlatformExamplePages = [
  jsUiPageSpec(
    category: ExampleCategory.platform,
    title: '宿主能力调用',
    description: '通过 JsUiHostFeatures 组合系统默认能力和自定义宿主调用。',
    tags: const ['host', 'capability'],
    builder: (_) => const JsUiHostCapabilitiesPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    title: '自定义组件',
    description: '演示 JS Component()、Dart 自定义 renderer、事件描述符和基础隐式动画。',
    tags: const ['component', 'renderer'],
    builder: (_) => const JsUiCustomComponentsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    title: '原生与 JS 页面互通',
    description: '演示原生 Flutter 页面、JSUI 页面之间的参数和结果回传。',
    tags: const ['navigation', 'route'],
    builder: (_) => const JsUiNavigationPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    title: '网络请求能力',
    description: '注入 FetchFeatures 与 Axios，在 JS 页面内加载远程 JSON。',
    tags: const ['network', 'axios', 'features'],
    builder: (_) => const JsUiNetworkCapabilityPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    title: '页面权限策略',
    description: '测试页面 permissions 声明、unrestricted 策略和 restricted 授权拦截。',
    tags: const ['permission', 'security'],
    builder: (_) => const JsUiPermissionPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    kind: ExampleKind.diagnostic,
    title: '错误诊断浮层',
    description: '展示 quickjs_ui schema、resource、route 和 action 错误定位信息。',
    tags: const ['error', 'diagnostic'],
    builder: (_) => const JsUiErrorPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    kind: ExampleKind.diagnostic,
    title: '局部刷新诊断',
    description: '可视化 stable key 节点在局部刷新中被跳过、变化节点重新构建。',
    tags: const ['diff', 'renderer'],
    builder: (_) => const JsUiDiffPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    kind: ExampleKind.diagnostic,
    title: '开发调试面板',
    description: '演示 Inspector、页面快照、diff/resource 日志和保留 state 的热重载。',
    tags: const ['inspector', 'devtools'],
    builder: (_) => const JsUiDevPanelPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.platform,
    kind: ExampleKind.diagnostic,
    title: '网络请求调试',
    description: '演示 bundle 网络请求、缓存命中、耗时和 Inspector 网络面板。',
    tags: const ['network', 'inspector'],
    builder: (_) => const JsUiNetworkInspectorPage(),
  ),
];
