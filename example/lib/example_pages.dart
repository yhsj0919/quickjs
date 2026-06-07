import 'example_page_spec.dart';
import 'pages/async_api_page.dart';
import 'pages/basic_eval_page.dart';
import 'pages/native_worker_page.dart';

// 规则：每个新功能都必须在这里同步注册一个 example 测试页面。
// 每个页面必须能独立运行，进入页面时创建自己的 Quickjs 实例，退出页面时销毁。
final List<ExamplePageSpec> examplePages = [
  ExamplePageSpec(
    title: '基础执行',
    description: '创建 Quickjs，执行一段 JavaScript，退出页面时销毁。',
    builder: (_) => const BasicEvalPage(),
  ),
  ExamplePageSpec(
    title: '异步 API',
    description: '提交排队 eval 请求，并验证 runtime 销毁后的错误行为。',
    builder: (_) => const AsyncApiPage(),
  ),
  ExamplePageSpec(
    title: '运行时 Worker',
    description: '执行长耗时 JS 忙循环，同时观察 Dart UI 计数器是否继续变化。',
    builder: (_) => const NativeWorkerPage(),
  ),
];
