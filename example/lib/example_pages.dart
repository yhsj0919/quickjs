import 'example_page_spec.dart';
import 'pages/basic_eval_page.dart';

// 规则：每个新功能都必须在这里同步注册一个 example 测试页面。
// 每个页面必须能独立运行，进入页面时创建自己的 Quickjs 实例，退出页面时销毁。
final List<ExamplePageSpec> examplePages = [
  ExamplePageSpec(
    title: '基础执行',
    description: '创建 Quickjs，执行一段 JavaScript，退出页面时销毁。',
    builder: (_) => const BasicEvalPage(),
  ),
];
