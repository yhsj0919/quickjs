import '../example_page_spec.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_anchored_overlay_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_canvas_clock_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_control_state_transitions_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_control_states_slots_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_controls_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_decoration_effects_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_feedback_overlays_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_form_controls_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_implicit_animations_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_keyed_list_transitions_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_pointer_keyboard_events_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_scroll_transition_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_temperature_chart_page.dart';
import '../pages/quickjs_ui/foundation/quickjs_ui_widgets_demo_page.dart';
import 'catalog_helpers.dart';

// Repository rule: append newly created demos to the end of this list.
final List<ExamplePageSpec> jsUiFoundationExamplePages = [
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '页面结构 · Scaffold 与导航',
    description: '集中演示 Scaffold、AppBar、Drawer、底部导航、FAB、GridView 和 Stack。',
    tags: const ['scaffold', 'navigation', 'layout'],
    builder: (_) => const JsUiWidgetsDemoPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '布局与媒体 · 图片、约束与分层',
    description:
        '集中演示 Image、Placeholder、Divider、Stack、Positioned、Center 和 Tooltip。',
    tags: const ['layout', 'image', 'media'],
    builder: (_) => const JsUiControlsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '装饰效果 · 渐变、边框与阴影',
    description: '独立演示线性与径向渐变、渐变 stops、分边边框、阴影偏移和多层阴影。',
    tags: const ['decoration', 'gradient', 'shadow'],
    builder: (_) => const JsUiDecorationEffectsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '输入事件 · 鼠标、指针与键盘',
    description: '独立演示鼠标移入移出、悬停、滚轮、原始指针、焦点和键盘事件。',
    tags: const ['mouse', 'pointer', 'keyboard'],
    builder: (_) => const JsUiPointerKeyboardEventsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '表单控件 · 状态与实时预览',
    description: '独立演示 Checkbox、Switch、Slider、DropdownButton 和表单状态。',
    tags: const ['form', 'control', 'state'],
    builder: (_) => const JsUiFormControlsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '反馈效果 · 进度、动画与系统浮层',
    description:
        '独立演示进度、AnimatedAlign、AnimatedSwitcher、SnackBar、Dialog 和 BottomSheet。',
    tags: const ['feedback', 'animation', 'overlay'],
    builder: (_) => const JsUiFeedbackOverlaysPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '滚动控制 · 定位与嵌套区域',
    description: '集中演示滚动位置事件、按 stable key 定位和 SingleChildScrollView 嵌套滚动。',
    tags: const ['scroll', 'positioning', 'nested'],
    builder: (_) => const JsUiScrollTransitionPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '列表动画 · Stable Key 进出与重排',
    description: '独立演示 keyed 列表项的新增、删除和顺序反转过渡。',
    tags: const ['list', 'key', 'transition'],
    builder: (_) => const JsUiKeyedListTransitionsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '基础动画 · 独立隐式过渡',
    description: '独立演示 AnimatedContainer、AnimatedOpacity 和 AnimatedPadding。',
    tags: const ['animation', 'implicit', 'transition'],
    builder: (_) => const JsUiImplicitAnimationsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '控件系统 · 状态与结构插槽',
    description: '统一控件状态模型，并演示 Button、Switch、Slider 和输入框的内部结构插槽。',
    tags: const ['control', 'state', 'slot'],
    builder: (_) => const JsUiControlStatesSlotsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '控件动画 · 状态过渡',
    description: '控件共享 Flutter VSync 本地状态插值，支持颜色、边框、尺寸、透明度与缩放。',
    tags: const ['control', 'animation'],
    builder: (_) => const JsUiControlStateTransitionsPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: '锚点浮层 · 定位与滚动跟随',
    description: '集中演示浮层方向、偏移、锚点宽度匹配、悬停提示与滚动跟随。',
    tags: const ['overlay', 'anchor', 'positioning'],
    builder: (_) => const JsUiAnchoredOverlayPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: 'Canvas 模拟时钟',
    description: '由 JS Canvas 2D 风格生成绘图场景，并由 Flutter VSync 本地驱动。',
    tags: const ['canvas', 'vsync'],
    builder: (_) => const JsUiCanvasClockPage(),
  ),
  jsUiPageSpec(
    category: ExampleCategory.uiFoundation,
    title: 'Canvas 温度折线图',
    description: '演示折线渐显、渐变画笔、虚线网格、本地坐标命中和悬停提示。',
    tags: const ['canvas', 'chart', 'animation', 'pointer'],
    builder: (_) => const JsUiTemperatureChartPage(),
  ),
];
