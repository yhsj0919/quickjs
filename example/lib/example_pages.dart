import 'example_page_spec.dart';
import 'pages/async_api_page.dart';
import 'pages/basic_eval_page.dart';
import 'pages/exception_model_page.dart';
import 'pages/memory_limit_page.dart';
import 'pages/native_worker_page.dart';
import 'pages/queue_reentry_page.dart';
import 'pages/runtime_isolation_page.dart';
import 'pages/structured_values_page.dart';

// 规则：每个新功能都必须在这里同步注册一个 example 测试页面。
// 每个页面必须能独立运行，进入页面时创建自己的 Quickjs 实例，退出页面时销毁。
// 页面注册表：每个新功能都应该在这里新增一个独立 example 页面。
// 页面之间不能共享 Quickjs runtime，避免状态污染手动验收结果。
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
    title: '执行队列与重入策略',
    description: '验证 100 次 eval 的 FIFO 顺序，以及 dispose / timeout 对排队任务的取消语义。',
    builder: (_) => const QueueReentryPage(),
  ),
  ExamplePageSpec(
    title: '运行时 Worker',
    description: '执行长耗时 JS 忙循环，验证 UI 不阻塞、timeout 和 stop。',
    builder: (_) => const NativeWorkerPage(),
  ),
  ExamplePageSpec(
    title: 'Runtime 隔离',
    description: '验证多个 Quickjs 实例的 globals 隔离，以及 dispose 一个不影响另一个。',
    builder: (_) => const RuntimeIsolationPage(),
  ),
  ExamplePageSpec(
    title: '基础错误模型',
    description: '触发 JS throw、timeout、stop 和 closed runtime，验证公开异常类型。',
    builder: (_) => const ExceptionModelPage(),
  ),
  ExamplePageSpec(
    title: '资源限制',
    description:
        '使用 memoryLimitBytes / stackLimitBytes 创建受限 runtime，验证资源错误和恢复后的 eval。',
    builder: (_) => const MemoryLimitPage(),
  ),
  ExamplePageSpec(
    title: '结构化返回',
    description:
        '使用 evaluateValue 获取 number、boolean、string、null 和 undefined 的 Dart 值。',
    builder: (_) => const StructuredValuesPage(),
  ),
];
