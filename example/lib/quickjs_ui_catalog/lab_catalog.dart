import '../example_page_spec.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_adaptive_performance_lab_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_arc_gauge_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_control_motion_stress_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_energy_burst_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_fireflies_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_huge_list_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_infinite_list_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_large_list_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_neon_galaxy_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_overlay_system_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_snappable_dust_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_starfield_page.dart';
import '../pages/quickjs_ui/lab/quickjs_ui_universal_effects_page.dart';
import 'catalog_helpers.dart';

// Repository rule: append newly created demos to the end of this list.
final List<ExamplePageSpec> quickjsUiLabExamplePages = [
  quickjsUiLabSpec(
    title: '列表性能 · 2,000 项',
    description: '独立测试 2,000 个列表项的按需构建和滚动性能。',
    builder: (_) => const QuickjsUiLargeListPage(),
  ),
  quickjsUiLabSpec(
    title: '列表性能 · 100,000 项',
    description: '使用 ListView.builder 分批渲染并连续滚动 100,000 个列表项。',
    builder: (_) => const QuickjsUiHugeListPage(),
  ),
  quickjsUiLabSpec(
    title: '列表性能 · 无限加载',
    description: '测试列表分页追加、加载提示、防重复请求和系统下拉刷新。',
    builder: (_) => const QuickjsUiInfiniteListPage(),
  ),
  quickjsUiLabSpec(
    title: 'Canvas 控件 · 弧形功率仪表盘',
    description: '可拖动调节的分段渐变进度弧，包含刻度、指针、数值和语义信息。',
    builder: (_) => const QuickjsUiArcGaugePage(),
  ),
  quickjsUiLabSpec(
    title: 'Canvas 特效 · 卡片灰飞烟灭',
    description: '参考 Snappable 的错峰消散算法，点击卡片触发粒子化并可恢复。',
    builder: (_) => const QuickjsUiSnappableDustPage(),
  ),
  quickjsUiLabSpec(
    title: '粒子特效 · 星际穿梭',
    description: '520 条带景深和加色混合的高速星轨，本地 VSync 动画。',
    builder: (_) => const QuickjsUiStarfieldPage(),
  ),
  quickjsUiLabSpec(
    title: '粒子特效 · 霓虹星系',
    description: '300 个粒子组成多旋臂星系，静态轨道缓存并在宿主本地旋转。',
    builder: (_) => const QuickjsUiNeonGalaxyPage(),
  ),
  quickjsUiLabSpec(
    title: '粒子特效 · 萤火虫花园',
    description: '260 个独立缓动粒子，以不同周期漂移、呼吸和发光。',
    builder: (_) => const QuickjsUiFirefliesPage(),
  ),
  quickjsUiLabSpec(
    title: '粒子特效 · 能量爆发',
    description: '360 个径向粒子和脉冲核心组成循环能量爆发。',
    builder: (_) => const QuickjsUiEnergyBurstPage(),
  ),
  quickjsUiLabSpec(
    title: '通用特效 · 任意控件本地动画',
    description: '任意节点统一使用 opacity、transform、clip、blur 和 colorFilter。',
    builder: (_) => const QuickjsUiUniversalEffectsPage(),
  ),
  quickjsUiLabSpec(
    title: '浮层系统 · 任意内容',
    description: '测试任意 JSUI 内容、遮罩、定位、进出动画和关闭生命周期。',
    builder: (_) => const QuickjsUiOverlaySystemPage(),
  ),
  quickjsUiLabSpec(
    title: '控件动画 · 性能压力测试',
    description: '同时驱动 1、10 或 40 个控件状态动画，测试 120Hz 与 60Hz 流畅度。',
    builder: (_) => const QuickjsUiControlMotionStressPage(),
  ),
  quickjsUiLabSpec(
    title: '综合性能 · 自适应效果质量',
    description: '综合测试 Canvas、Snapshot、滤镜与组件动画，并展示自动降级指标。',
    builder: (_) => const QuickjsUiAdaptivePerformanceLabPage(),
  ),
];
