import '../example_page_spec.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_profile_form_page.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_todo_page.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_weather_background_page.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_weather_demo_page.dart';
import 'catalog_helpers.dart';

// Repository rule: append newly created demos to the end of this list.
final List<ExamplePageSpec> quickjsUiScenarioExamplePages = [
  quickjsUiPageSpec(
    category: ExampleCategory.scenario,
    kind: ExampleKind.scenario,
    title: '待办列表',
    description: '实际列表场景：ListView、TextField、事件、受控输入和 ThemeData token。',
    tags: const ['list', 'input'],
    builder: (_) => const QuickjsUiTodoPage(),
  ),
  quickjsUiPageSpec(
    category: ExampleCategory.scenario,
    kind: ExampleKind.scenario,
    title: '个人资料表单',
    description: '实际表单场景：受控输入、focus/blur、submit 和预览。',
    tags: const ['form', 'input'],
    builder: (_) => const QuickjsUiProfileFormPage(),
  ),
  quickjsUiPageSpec(
    category: ExampleCategory.scenario,
    kind: ExampleKind.scenario,
    title: '天气综合页面',
    description: '实际天气卡片场景：IP 定位、刷新、当前天气、小时预报和生活提示。',
    tags: const ['weather', 'network'],
    builder: (_) => const QuickjsUiWeatherDemoPage(),
  ),
  quickjsUiPageSpec(
    category: ExampleCategory.scenario,
    kind: ExampleKind.scenario,
    title: '天气背景库',
    description: '可迁移的图片分层天气背景库，使用原生 VSync 和 Canvas 雨雪效果。',
    tags: const ['weather', 'module', 'animation'],
    builder: (_) => const QuickjsUiWeatherBackgroundPage(),
  ),
];
