import '../example_page_spec.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_bundle_counter_page.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_counter_page.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_package_demo_page.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_schema_page.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_video_player_plugin_page.dart';
import '../pages/quickjs_ui/getting_started/quickjs_ui_webview_plugin_page.dart';
import 'catalog_helpers.dart';

// Repository rule: append newly created demos to the end of this list.
final List<ExamplePageSpec> jsUiGettingStartedExamplePages = [
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: '单文件计数器',
    description: '加载单文件 quickjs_ui Page(.mjs)，并使用原生 Flutter Widget 渲染。',
    tags: const ['single-file', 'page'],
    builder: (_) => const JsUiCounterPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: '共享运行时计数器',
    description: '使用应用级预热运行时加载同一个计数器页面。',
    tags: const ['runtime', 'preheat'],
    builder: (_) => const JsUiSharedRuntimeCounterPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: '多文件模块计数器',
    description: '从入口 .mjs 加载多文件 quickjs_ui 页面，自动解析相对 import 后渲染。',
    tags: const ['bundle', 'module'],
    builder: (_) => const JsUiBundleCounterPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: 'JSON Schema 页面',
    description: '从纯 JSON UI schema asset 解析 JsUiNode，并不经过 JS 直接渲染。',
    tags: const ['schema', 'json'],
    builder: (_) => const JsUiSchemaPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: '页面发布包',
    description: '演示固定包根 main.mjs + manifest.json 的 asset 发布包加载和校验。',
    tags: const ['package', 'manifest'],
    builder: (_) => const JsUiPackageDemoPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: '视频播放器插件',
    description:
        '演示第三方 quickjs_ui 插件，通过 quickjs_ui/video_player 暴露 VideoPlayer 组件。',
    tags: const ['plugin', 'video'],
    builder: (_) => const JsUiVideoPlayerPluginPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.gettingStarted,
    title: 'WebView 插件',
    description: '演示网页方法调用和 A / B / C 级联 DOM 查询隔离。',
    tags: const ['plugin', 'webview', 'bridge'],
    builder: (_) => const JsUiWebViewPluginPage(),
  ),
];
