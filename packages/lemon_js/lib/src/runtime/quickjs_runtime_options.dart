import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';

part '../module/quickjs_essential_host_mount.dart';
part '../module/quickjs_node_host_mount.dart';
part '../module/quickjs_web_host_mount.dart';

/// Loads an ES module source by its normalized module name.
///
/// Relative specifiers are normalized by [Quickjs] before the loader is called,
/// so a loader can use the incoming [moduleName] as its cache key. Returning
/// `null` means the module cannot be resolved.
typedef JsModuleLoader = FutureOr<String?> Function(String moduleName);

/// Callback used by a Dart host provider.
///
/// JavaScript wrappers call providers through a Promise-returning bridge. The
/// callback receives already-converted JavaScript arguments and may return any
/// value supported by the structured value codec.
typedef JsProviderCallback =
    FutureOr<Object?> Function(List<Object?> args, JsProviderContext context);

/// Lifecycle context for one async host-provider invocation.
///
/// [cancelled] completes when the owning runtime is stopped, disposed, or
/// rebuilt. Provider implementations that own cancellable work should stop it
/// promptly, then call [throwIfCancelled] before returning a value.
final class JsProviderContext {
  /// Creates an invocation context.
  ///
  /// Provider users normally receive this from the runtime rather than
  /// constructing one directly.
  JsProviderContext();

  final Completer<void> _cancelled = Completer<void>();
  Object? _cancellationReason;

  /// Completes when this invocation no longer belongs to a live runtime.
  Future<void> get cancelled => _cancelled.future;

  /// Whether the owning runtime has cancelled this invocation.
  bool get isCancelled => _cancelled.isCompleted;

  /// The runtime lifecycle error that caused cancellation, when available.
  Object? get cancellationReason => _cancellationReason;

  /// Throws [cancellationReason] if this invocation has been cancelled.
  void throwIfCancelled() {
    final reason = _cancellationReason;
    if (reason != null) {
      throw reason;
    }
  }

  /// Cancels this invocation with [reason]. Repeated calls are ignored.
  void cancel(Object reason) {
    if (_cancelled.isCompleted) {
      return;
    }
    _cancellationReason = reason;
    _cancelled.complete();
  }
}

/// Browser-like global aliases that can be explicitly installed into a runtime.
final class JsGlobals {
  const JsGlobals({this.window = false, this.self = false});

  /// Installs `globalThis.window = globalThis` when true.
  final bool window;

  /// Installs `globalThis.self = globalThis` when true.
  final bool self;

  bool get isEmpty => !window && !self;
}

/// 安装到每个新建 runtime 的启动/引导 JavaScript 脚本描述。
///
/// 宿主脚本在内置 console 与显式宿主能力安装之后执行；runtime 在 `restart()`
/// 后重建时也会重新执行。适用于注入可选全局对象或 polyfill，例如 `crypto`、
/// `Buffer`、`location` 或应用自定义对象。
final class JsScript {
  /// 使用内联 JavaScript 源码创建宿主脚本。
  ///
  /// - [name]：QuickJS 堆栈中显示的脚本名称。
  /// - [source]：要执行的 JavaScript 源码。
  /// - [globals]：本脚本声明会安装到 `globalThis` 的全局变量名列表。
  const JsScript.js({
    required this.name,
    required this.source,
    this.globals = const <String>[],
  }) : assetKey = null,
       bundle = null;

  /// 使用 Flutter asset 创建宿主脚本描述（同步构造）。
  ///
  /// 可在 features 列表中直接书写，无需 `await`。asset 内容在 runtime 安装宿主
  /// 脚本时通过 [loadSource] 延迟加载。
  ///
  /// - [name]：QuickJS 堆栈中显示的脚本名称。
  /// - [assetKey]：脚本所在的 Flutter asset 路径。
  /// - [bundle]：读取 asset 时使用的 bundle；为 `null` 时使用 [rootBundle]。
  /// - [globals]：本脚本声明会安装到 `globalThis` 的全局变量名列表。
  const JsScript.asset({
    required this.name,
    required this.assetKey,
    this.bundle,
    this.globals = const <String>[],
  }) : source = null;

  factory JsScript.providerGlobals({
    required String name,
    required Map<String, String> globals,
  }) {
    final entries = globals.entries.map((entry) {
      final globalName = _validateHostScriptGlobalName(entry.key);
      final providerName = _validateHostScriptProviderName(entry.value);
      return '''
globalThis[${jsonEncode(globalName)}] = (...args) =>
  globalThis.__quickjsHostProviders[${jsonEncode(providerName)}](...args);
''';
    }).join();
    return JsScript.js(
      name: name,
      source: entries,
      globals: List<String>.unmodifiable(globals.keys),
    );
  }

  /// QuickJS 堆栈中使用的脚本 source 名称。
  final String name;

  /// 内联 JavaScript 源码；与 [assetKey] 二选一。
  final String? source;

  /// 包含 JavaScript 源码的 Flutter asset 路径。
  final String? assetKey;

  /// 解析 [assetKey] 时使用的 asset bundle。
  final AssetBundle? bundle;

  /// 本脚本安装到 `globalThis` 的全局变量名列表。
  ///
  /// features 校验会在重建 runtime 前拒绝重复声明的全局名。不安装全局对象的脚本
  /// 可留空。
  final List<String> globals;

  /// 加载脚本源码：优先返回内联 [source]，否则从 [assetKey] 读取 asset。
  Future<String> loadSource() async {
    final inlineSource = source;
    if (inlineSource != null) {
      return inlineSource;
    }
    final key = assetKey;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS host script "$name" has no source or assetKey',
      );
    }
    return (bundle ?? rootBundle).loadString(key);
  }
}

String _validateHostScriptGlobalName(String name) {
  final isIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);
  if (!isIdentifier) {
    throw JsValueConversionException(
      'QuickJS host script global name must be a JavaScript identifier: $name',
    );
  }
  return name;
}

String _validateHostScriptProviderName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host script provider name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host script provider name must not contain NUL',
    );
  }
  return name;
}

/// 显式注册到 runtime 的 JavaScript 模块描述。
///
/// ES 模块在 JS `import` [specifier] 时加载；CommonJS 模块在通过
/// [Quickjs.evalCommonJs] 执行 `require(specifier)` 时加载。
final class JsModule {
  /// 使用内联源码创建宿主模块。
  ///
  /// - [specifier]：JS `import` / `require` 使用的模块标识符。
  /// - [source]：模块 JavaScript 源码。
  /// - [format]：模块格式（ES module 或 CommonJS）。
  const JsModule({
    required this.specifier,
    required this.source,
    this.format = JsModuleFormat.esModule,
  }) : assetKey = null,
       bundle = null;

  /// 使用 Flutter asset 创建宿主模块描述（同步构造）。
  ///
  /// asset 源码在 runtime 构建模块图时通过 [loadSource] 延迟加载。
  ///
  /// - [specifier]：JS `import` / `require` 使用的模块标识符。
  /// - [assetKey]：模块源码所在的 Flutter asset 路径。
  /// - [bundle]：读取 asset 时使用的 bundle。
  /// - [format]：模块格式（ES module 或 CommonJS）。
  const JsModule.asset({
    required this.specifier,
    required this.assetKey,
    this.bundle,
    this.format = JsModuleFormat.esModule,
  }) : source = null;

  /// 创建 ES 格式宿主模块（内联源码）。
  const JsModule.esModule({required String specifier, required String source})
    : this(
        specifier: specifier,
        source: source,
        format: JsModuleFormat.esModule,
      );

  /// 创建 ES 格式宿主模块（Flutter asset，同步构造）。
  const JsModule.esModuleAsset({
    required String specifier,
    required String assetKey,
    AssetBundle? bundle,
  }) : this.asset(
         specifier: specifier,
         assetKey: assetKey,
         bundle: bundle,
         format: JsModuleFormat.esModule,
       );

  /// 创建 CommonJS 格式宿主模块（内联源码）。
  const JsModule.commonJs({required String specifier, required String source})
    : this(
        specifier: specifier,
        source: source,
        format: JsModuleFormat.commonJs,
      );

  /// 创建 CommonJS 格式宿主模块（Flutter asset，同步构造）。
  const JsModule.commonJsAsset({
    required String specifier,
    required String assetKey,
    AssetBundle? bundle,
  }) : this.asset(
         specifier: specifier,
         assetKey: assetKey,
         bundle: bundle,
         format: JsModuleFormat.commonJs,
       );

  /// JS `import` 或 `require` 使用的模块标识符。
  final String specifier;

  /// 内联模块 JavaScript 源码；与 [assetKey] 二选一。
  final String? source;

  /// 包含模块源码的 Flutter asset 路径。
  final String? assetKey;

  /// 解析 [assetKey] 时使用的 asset bundle。
  final AssetBundle? bundle;

  /// 模块格式（ES module 或 CommonJS）。
  final JsModuleFormat format;

  /// 加载模块源码：优先返回内联 [source]，否则从 [assetKey] 读取 asset。
  Future<String> loadSource() async {
    final inlineSource = source;
    if (inlineSource != null) {
      return inlineSource;
    }
    final key = assetKey;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS host module "$specifier" has no source or assetKey',
      );
    }
    return (bundle ?? rootBundle).loadString(key);
  }
}

/// Supported host module source formats.
enum JsModuleFormat {
  /// ES module source for `import` / dynamic `import()`.
  esModule,

  /// CommonJS source for `require()`.
  commonJs,
}

/// Host function implementation available to startup scripts or host modules.
///
/// Providers are intentionally not exposed as user-facing globals by
/// themselves. A startup script or host module should wrap a provider into the
/// desired JavaScript API shape, such as `fetch()` or `crypto.subtle.digest()`.
final class JsProvider {
  const JsProvider.dart({
    required this.name,
    required this.callback,
    this.debugName,
    this.globalName,
    this.implementation = JsProviderImplementation.dart,
  });

  factory JsProvider.global({
    required String name,
    required JsProviderCallback callback,
    String? debugName,
    JsProviderImplementation implementation = JsProviderImplementation.dart,
  }) {
    final globalName = _validateHostScriptGlobalName(name);
    return JsProvider.dart(
      name: 'global.$globalName',
      globalName: globalName,
      debugName: debugName,
      implementation: implementation,
      callback: callback,
    );
  }

  /// Runtime-scoped provider name used by JavaScript wrappers.
  final String name;

  /// Optional readable name for debug snapshots.
  final String? debugName;

  /// Optional global function name installed as a direct wrapper for [name].
  ///
  /// Use this for simple `globalThis.foo(...)` APIs. Leave it null when a
  /// startup script or module needs to expose a richer API shape, such as
  /// `fetch()` or `crypto.subtle.digest()`.
  final String? globalName;

  /// Declared source of the provider implementation.
  ///
  /// This is inspector metadata and does not change callback behavior. All
  /// current providers use the asynchronous callback bridge.
  final JsProviderImplementation implementation;

  /// Dart/Flutter implementation. JS receives a Promise for each call.
  ///
  /// The per-call context is cancelled when the runtime restarts, is disposed,
  /// or is rebuilt. Await [JsProviderContext.cancelled] when the
  /// underlying operation supports cooperative cancellation.
  final JsProviderCallback callback;
}

/// Source of a host-provider implementation.
enum JsProviderImplementation {
  /// Pure Dart or Flutter code running in the host isolate.
  dart,

  /// A Dart callback backed by a platform API or platform channel.
  platform,

  /// A Dart callback backed by a browser/Web API.
  web,
}

/// Named bundle of environment patches, modules, and host providers.
///
/// A features installs one composable capability bundle into a runtime.
base class JsFeatures {
  const JsFeatures({
    required this.name,
    this.browserGlobals = const JsGlobals(),
    this.scripts = const <JsScript>[],
    this.modules = const <JsModule>[],
    this.providers = const <JsProvider>[],
  });

  /// Creates a minimal browser-like global environment.
  ///
  /// This installs `window` / `self` aliases by default plus small
  /// startup-script implementations for `location`, `navigator`, `URL`,
  /// `localStorage`, and `sessionStorage`. It does not install `fetch`, Web
  /// Crypto, DOM APIs, networking, or platform storage.
  factory JsFeatures.web({
    String locationHref = 'about:blank',
    String userAgent = 'QuickJS',
    bool window = true,
    bool self = true,
    bool storage = true,
  }) => _quickjsWebHostMount(
    locationHref: locationHref,
    userAgent: userAgent,
    window: window,
    self: self,
    storage: storage,
  );

  /// Creates a small low-risk host environment for common utility APIs.
  ///
  /// The current essential preset installs `buffer` / `node:buffer` as both an
  /// ES module and a CommonJS module. Set [globalBuffer] to true to also install
  /// `globalThis.Buffer` as a startup global.
  factory JsFeatures.essential({bool globalBuffer = false}) =>
      _quickjsEssentialHostMount(globalBuffer: globalBuffer);

  /// Creates a minimal Node-like module environment.
  ///
  /// This preset installs pure-JS host modules for `buffer`, `crypto`, `path`,
  /// `process`, and `timers`, all available through both bare and `node:`
  /// specifiers.
  /// `Buffer` and `process` are not installed as globals unless explicitly
  /// requested. It does not install Node `fs`, networking, or a full npm
  /// resolver. The `crypto` module is a minimal compatibility subset.
  factory JsFeatures.node({
    bool globalBuffer = false,
    bool globalProcess = false,
    Map<String, String> env = const <String, String>{},
    String platform = 'quickjs',
    String cwd = '/',
  }) => _quickjsNodeHostMount(
    globalBuffer: globalBuffer,
    globalProcess: globalProcess,
    env: env,
    platform: platform,
    cwd: cwd,
  );

  /// Stable name used for conflict detection and debug inspection.
  final String name;

  /// Browser-like global aliases installed before scripts.
  final JsGlobals browserGlobals;

  /// Ordered scripts that complete the runtime global environment.
  final List<JsScript> scripts;

  /// ES module and CommonJS definitions included in this features.
  final List<JsModule> modules;

  /// Dart/Flutter providers included in this features.
  final List<JsProvider> providers;
}

/// Resource and execution-queue limits used when creating a QuickJS runtime.
final class JsOptions {
  const JsOptions({
    this.memoryLimitBytes,
    this.stackLimitBytes,
    this.maxPendingTasks = 256,
  });

  /// Maximum memory for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Exceeding the limit is reported as
  /// `JsOutOfMemoryException` by the public API.
  final int? memoryLimitBytes;

  /// Maximum native call stack for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Native uses `JS_SetMaxStackSize`; the
  /// current web backend does not expose an equivalent WASM option yet.
  final int? stackLimitBytes;

  /// Maximum number of tasks allowed to wait in this runtime's execution queue.
  ///
  /// The task currently executing is not counted. For example, a value of `1`
  /// allows one running task and one waiting task. While the queue is at this
  /// limit, a new eval, module call, or plugin call fails immediately with
  /// [JsQueueFullException]. This bounds memory growth and latency when a long
  /// JavaScript task causes callers to submit work faster than it can run.
  /// Must be greater than zero. Defaults to `256`.
  final int maxPendingTasks;
}
