import 'example_page_spec.dart';
import 'pages/quickjs_ui/integrated/quickjs_ui_weather_demo_page.dart';
import 'pages/quickjs_ui/integrated/quickjs_ui_weather_background_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_anchored_overlay_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_bundle_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_adaptive_performance_lab_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_canvas_clock_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_controls_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_custom_components_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_dev_panel_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_diff_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_error_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_host_capabilities_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_huge_list_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_infinite_list_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_navigation_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_capability_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_counter_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_network_inspector_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_package_demo_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_particle_demo_pages.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_permission_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_profile_form_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_schema_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_scroll_transition_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_large_list_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_todo_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_video_player_plugin_page.dart';
import 'pages/quickjs_ui/ui/quickjs_ui_widgets_demo_page.dart';

final List<ExamplePageSpec> quickjsUiExamplePages = [
  ...quickjsUiCoreExamplePages,
  ...quickjsUiWidgetExamplePages,
  ...quickjsUiIntegratedExamplePages,
  ...quickjsUiParticleExamplePages,
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
    title: 'QuickJS UI Shared Runtime Counter',
    description:
        'Uses the same counter page with the application-scoped preheated runtime.',
    builder: (_) => const QuickjsUiSharedRuntimeCounterPage(),
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
  ExamplePageSpec(
    title: 'QuickJS UI 大列表测试',
    description: '独立测试 2,000 个列表项的按需构建和滚动性能。',
    builder: (_) => const QuickjsUiLargeListPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 超长列表测试',
    description: '使用 ListView.builder 分批渲染并连续滚动 100,000 个列表项。',
    builder: (_) => const QuickjsUiHugeListPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 无限加载测试',
    description: '专门测试列表分页追加、加载提示、防重复请求和系统下拉刷新。',
    builder: (_) => const QuickjsUiInfiniteListPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI 基础能力',
    description: '渐变阴影、鼠标指针、焦点键盘，以及原生 Overlay 锚定与滚动跟随。',
    builder: (_) => const QuickjsUiAnchoredOverlayPage(),
  ),
];

final List<ExamplePageSpec> quickjsUiIntegratedExamplePages = [
  ExamplePageSpec(
    title: 'QuickJS UI 天气综合 Demo',
    description: '实际天气卡片场景：IP 定位、刷新、当前天气、小时预报和生活提示。',
    builder: (_) => const QuickjsUiWeatherDemoPage(),
  ),
  ExamplePageSpec(
    title: 'QuickJS UI Weather Background Library',
    description:
        'Portable image-layered weather backgrounds with native VSync effects and Canvas rain/snow.',
    builder: (_) => const QuickjsUiWeatherBackgroundPage(),
  ),
];

// Repository rule: newly created demos are appended to the final example
// group so they always appear after every existing demo.
final List<ExamplePageSpec> quickjsUiParticleExamplePages = [
  ExamplePageSpec(
    title: 'QuickJS UI Canvas 模拟时钟',
    description: '由 JS Canvas 2D 风格生成绘图场景，并由 Flutter VSync 本地驱动。',
    builder: (_) => const QuickjsUiCanvasClockPage(),
  ),
  ExamplePageSpec(
    title: 'Particle FX · 星际穿梭',
    description: '520 条带景深和加色混合的高速星轨，本地 VSync 动画。',
    builder: (_) => const QuickjsUiStarfieldPage(),
  ),
  ExamplePageSpec(
    title: 'Particle FX · 霓虹星系',
    description: '300 个粒子组成多旋臂星系，静态轨道缓存并在宿主本地旋转。',
    builder: (_) => const QuickjsUiNeonGalaxyPage(),
  ),
  ExamplePageSpec(
    title: 'Particle FX · 萤火虫花园',
    description: '260 个独立缓动粒子，以不同周期漂移、呼吸和发光。',
    builder: (_) => const QuickjsUiFirefliesPage(),
  ),
  ExamplePageSpec(
    title: 'Particle FX · 能量爆发',
    description: '360 个径向粒子和脉冲核心组成循环能量爆发。',
    builder: (_) => const QuickjsUiEnergyBurstPage(),
  ),
  ExamplePageSpec(
    title: 'Canvas 控件 · 弧形功率仪表盘',
    description: '可拖动调节的分段渐变进度弧，包含刻度、指针、数值和语义信息。',
    builder: (_) => const QuickjsUiArcGaugePage(),
  ),
  ExamplePageSpec(
    title: 'Canvas 特效 · Snappable 灰飞烟灭',
    description: '参考 Snappable 的 16 层错峰消散算法，点击卡片触发粒子化并可再次点击恢复。',
    builder: (_) => const QuickjsUiSnappableDustPage(),
  ),
  ExamplePageSpec(
    title: 'Universal FX · 任意控件本地动画',
    description:
        '任意 Flutter/JS 节点统一使用 opacity、transform、clip、blur 和 colorFilter，并由 VSync 本地驱动。',
    builder: (_) => const QuickjsUiUniversalEffectsPage(),
  ),
  ExamplePageSpec(
    title: 'Control System · 状态与结构插槽',
    description: '统一控件状态模型，并演示 Button、Switch、Slider 和输入框的内部结构插槽。',
    builder: (_) => const QuickjsUiControlStatesSlotsPage(),
  ),
  ExamplePageSpec(
    title: 'Control Motion · 状态过渡动画',
    description:
        'Button、Switch、Slider 和输入框共享 Flutter VSync 本地状态插值，支持颜色、边框、尺寸、透明度与缩放。',
    builder: (_) => const QuickjsUiControlStateTransitionsPage(),
  ),
  ExamplePageSpec(
    title: 'Control Motion · 性能压力测试',
    description: '同时驱动 1、10 或 40 个控件状态动画，测试 120Hz 与 60Hz 流畅度。',
    builder: (_) => const QuickjsUiControlMotionStressPage(),
  ),
  ExamplePageSpec(
    title: 'Overlay System · 任意浮层',
    description: '统一测试任意 JSUI 内容、遮罩、定位、进出动画和关闭生命周期。',
    builder: (_) => const QuickjsUiOverlaySystemPage(),
  ),
  ExamplePageSpec(
    title: 'Performance Lab · 自适应效果质量',
    description:
        '综合测试 1k/5k/10k Canvas 图元、Snapshot 粒子、滤镜与组件动画，并实时展示刷新率、帧耗和自动降级指标。',
    builder: (_) => const QuickjsUiAdaptivePerformanceLabPage(),
  ),
];
