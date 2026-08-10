import '../example_page_spec.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_profile_form_page.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_todo_page.dart';
import '../pages/quickjs_ui/scenario/quickjs_ui_weather_background_page.dart';
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
    title: '动态天气背景',
    description: '使用内置静态天气数据驱动动态 Canvas 背景，不依赖远程天气接口。',
    tags: const ['weather', 'static', 'canvas', 'animation'],
    builder: (_) => const QuickjsUiWeatherBackgroundPage(),
  ),
];
