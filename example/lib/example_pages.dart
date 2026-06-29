import 'example_page_spec.dart';
import 'pages/async_api_page.dart';
import 'pages/basic_eval_page.dart';
import 'pages/callback_bridge_page.dart';
import 'pages/class_binding_page.dart';
import 'pages/console_page.dart';
import 'pages/crypto_random_uuid_page.dart';
import 'pages/exception_model_page.dart';
import 'pages/function_handle_page.dart';
import 'pages/fetch_page.dart';
import 'pages/host_modules_page.dart';
import 'pages/host_mounts_page.dart';
import 'pages/js_call_dart_plugin_page.dart';
import 'pages/memory_limit_page.dart';
import 'pages/module_eval_page.dart';
import 'pages/native_worker_page.dart';
import 'pages/npm_bundle_page.dart';
import 'pages/object_proxy_page.dart';
import 'pages/plugin_page.dart';
import 'pages/queue_reentry_page.dart';
import 'pages/runtime_isolation_page.dart';
import 'pages/stream_callback_page.dart';
import 'pages/structured_values_page.dart';
import 'pages/timer_event_loop_page.dart';
import 'pages/web_host_environment_page.dart';
import 'pages/zip_plugin_page.dart';

// 规则：每个新功能都必须在这里同步注册一个 example 测试页面。
// 每个页面必须能独立运行，进入页面时创建自己的 Quickjs 实例，退出页面时销毁。
// 页面注册表：每个新功能都应该在这里新增一个独立 example 页面。
// 页面之间不能共享 Quickjs runtime，避免状态污染手动验收结果。
// 新页面必须追加到列表末尾，已有页面顺序和首页序号保持稳定。
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
  ExamplePageSpec(
    title: 'Callback Bridge',
    description: '绑定 Dart 函数，JS 通过 Promise await 调用并接收返回值或错误。',
    builder: (_) => const CallbackBridgePage(),
  ),
  ExamplePageSpec(
    title: 'Timer 与事件循环',
    description: '使用 setTimeout / clearTimeout / setInterval 驱动 Promise 与事件循环。',
    builder: (_) => const TimerEventLoopPage(),
  ),
  ExamplePageSpec(
    title: '流式 Callback',
    description:
        'Dart Stream 映射为 JS async iterable（for-await），JS sink 分片推送到 Dart Stream。',
    builder: (_) => const StreamCallbackPage(),
  ),
  ExamplePageSpec(
    title: 'Module',
    description: '执行 ES module、CommonJS、相对路径解析与 runtime module cache。',
    builder: (_) => const ModuleEvalPage(),
  ),
  ExamplePageSpec(
    title: '宿主模块',
    description:
        '使用 QuickjsRuntimeOptions.modules 注入 ES module 和 CommonJS 宿主模块，验证 cache、debugInspect、essential Buffer 与 node preset。',
    builder: (_) => const HostModulesPage(),
  ),
  ExamplePageSpec(
    title: 'Web 宿主环境',
    description:
        '使用 QuickjsHostMount.web() 注入 window、location、navigator、URL 和内存版 storage。',
    builder: (_) => const WebHostEnvironmentPage(),
  ),
  ExamplePageSpec(
    title: 'Function Handle',
    description:
        '使用 evaluateHandle 获取 JS function，并通过 handle.call / callAsync / dispose 管理。',
    builder: (_) => const FunctionHandlePage(),
  ),
  ExamplePageSpec(
    title: '对象代理',
    description: '使用 bindObject 注册 Dart proxy，暴露只读属性、Promise 方法和显式释放。',
    builder: (_) => const ObjectProxyPage(),
  ),
  ExamplePageSpec(
    title: 'Class Binding',
    description:
        '使用 bindClass 注册 Dart class，展示 new User、await getter/method 和显式释放。',
    builder: (_) => const ClassBindingPage(),
  ),
  ExamplePageSpec(
    title: 'Console',
    description:
        '使用 Quickjs.create(onConsole:) 接收 console.log / warn / error 事件。',
    builder: (_) => const ConsolePage(),
  ),
  ExamplePageSpec(
    title: 'Web Crypto',
    description:
        '通过 QuickjsWebCryptoMount() 安装 randomUUID、getRandomValues、Flutter 原生 subtle.digest 和 HMAC-SHA-256 crypto.subtle.sign/verify。',
    builder: (_) => const CryptoRandomUuidPage(),
  ),
  ExamplePageSpec(
    title: '能力批量挂载',
    description:
        '使用 QuickjsRuntimeOptions.mounts 和 Quickjs.mount() 批量安装环境补全、模块与 provider。',
    builder: (_) => const HostMountsPage(),
  ),
  ExamplePageSpec(
    title: 'NPM Bundle',
    description:
        '加载 esbuild 生成的单文件 asset，注册为 ES module，并只调用 compareValues() 导出方法。',
    builder: (_) => const NpmBundlePage(),
  ),
  ExamplePageSpec(
    title: 'Fetch',
    description:
        '验证 QuickjsFetchMount 的 Fetch、Request、Response、重定向、自定义配置与 Axios/XHR 兼容协议。',
    builder: (_) => const FetchPage(),
  ),
  ExamplePageSpec(
    title: 'JS 插件',
    description:
        '使用 QuickjsPlugin 注册单文件插件和多模块插件包，验证 validatePlugin、invokePlugin、structured codec 和错误返回。',
    builder: (_) => const PluginPage(),
  ),
  ExamplePageSpec(
    title: 'Zip Plugin',
    description:
        'Load a zipped plugin asset with QuickjsZipPlugin.asset(), validate it, run init(), and call exported methods.',
    builder: (_) => const ZipPluginPage(),
  ),
  ExamplePageSpec(
    title: 'JsCallDart 插件',
    description: '按 flutter_js main2.dart 的方式加载 asset 插件、注册 Dart 方法并运行 test2。',
    builder: (_) => const JsCallDartPluginPage(),
  ),
];
