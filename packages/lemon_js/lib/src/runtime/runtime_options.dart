import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/exception.dart';

part '../module/essential_features.dart';
part '../module/node_features.dart';
part '../module/web_features.dart';

/// 按需懒加载未预先注册的 ES 模块源码。
///
/// 当 JavaScript `import` 的模块未包含在预注册的 `modules` 中时调用。
/// 相对模块标识符会先由 [JsEngine] 规范化，因此可以直接使用
/// [name] 作为缓存键。返回 `null` 表示模块不存在或无法加载。
typedef JsModuleLoader = FutureOr<String?> Function(String name);

/// 创建时注入的 Dart 宿主方法回调。
///
/// JavaScript 通过返回 Promise 的桥接层调用该方法。回调接收已转换的参数和
/// 本次调用的生命周期上下文，可以返回结构化值编解码器支持的任意值。
typedef JsHostMethodCallback =
    FutureOr<Object?> Function(List<Object?> args, JsHostMethodContext context);

/// 一次异步宿主方法调用的生命周期上下文。
///
/// [cancelled] completes when the owning runtime is stopped, disposed, or
/// rebuilt. Method implementations that own cancellable work should stop it
/// promptly, then call [throwIfCancelled] before returning a value.
abstract interface class JsHostMethodContext {
  /// Completes when this invocation no longer belongs to a live runtime.
  Future<void> get cancelled;

  /// Whether the owning runtime has cancelled this invocation.
  bool get isCancelled;

  /// The runtime lifecycle error that caused cancellation, when available.
  Object? get cancellationReason;

  /// Throws [cancellationReason] if this invocation has been cancelled.
  void throwIfCancelled();
}

/// Browser-like global aliases that can be explicitly installed into a runtime.
final class JsGlobals {
  /// Creates an explicit set of browser-compatible global aliases.
  const JsGlobals({this.window = false, this.self = false});

  /// Installs `globalThis.window = globalThis` when true.
  final bool window;

  /// Installs `globalThis.self = globalThis` when true.
  final bool self;

  /// Whether no browser-compatible aliases are requested.
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
  const JsScript({
    required this.name,
    required this.source,
    this.globals = const <String>[],
  }) : path = null,
       bundle = null;

  /// 使用 Flutter asset 创建宿主脚本描述（同步构造）。
  ///
  /// 可在 features 列表中直接书写，无需 `await`。asset 内容在 runtime 安装宿主
  /// 脚本时通过 [loadSource] 延迟加载。
  ///
  /// - [name]：QuickJS 堆栈中显示的脚本名称。
  /// - [path]：脚本所在的 Flutter asset 路径。
  /// - [bundle]：读取 asset 时使用的 bundle；为 `null` 时使用 [rootBundle]。
  /// - [globals]：本脚本声明会安装到 `globalThis` 的全局变量名列表。
  const JsScript.asset({
    required this.name,
    required this.path,
    this.bundle,
    this.globals = const <String>[],
  }) : source = null;

  /// Creates a startup script that exposes persistent host methods as globals.
  factory JsScript.methodGlobals({
    required String name,
    required Map<String, String> globals,
  }) {
    final entries = globals.entries.map((entry) {
      final globalName = _validateHostScriptGlobalName(entry.key);
      final methodName = _validateHostScriptMethodName(entry.value);
      return '''
globalThis[${jsonEncode(globalName)}] = (...args) =>
  globalThis.__jsHostMethods[${jsonEncode(methodName)}](...args);
''';
    }).join();
    return JsScript(
      name: name,
      source: entries,
      globals: List<String>.unmodifiable(globals.keys),
    );
  }

  /// QuickJS 堆栈中使用的脚本 source 名称。
  final String name;

  /// 内联 JavaScript 源码；与 [path] 二选一。
  final String? source;

  /// 包含 JavaScript 源码的 Flutter asset 路径。
  final String? path;

  /// 解析 [path] 时使用的 asset bundle。
  final AssetBundle? bundle;

  /// 本脚本安装到 `globalThis` 的全局变量名列表。
  ///
  /// features 校验会在重建 runtime 前拒绝重复声明的全局名。不安装全局对象的脚本
  /// 可留空。
  final List<String> globals;

  /// 加载脚本源码：优先返回内联 [source]，否则从 [path] 读取 asset。
  Future<String> loadSource() async {
    final inlineSource = source;
    if (inlineSource != null) {
      return inlineSource;
    }
    final key = path;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS host script "$name" has no source or path',
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

String _validateHostScriptMethodName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host script method name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host script method name must not contain NUL',
    );
  }
  return name;
}

/// 显式注册到 runtime 的 JavaScript 模块描述。
///
/// ES 模块在 JS `import` [name] 时加载；CommonJS 模块在通过
/// [JsEngine.runCommonJs] 执行 `require(name)` 时加载。
final class JsModule {
  /// 使用内联源码创建宿主模块。
  ///
  /// - [name]：JS `import` / `require` 使用的模块名。
  /// - [source]：模块 JavaScript 源码。
  /// - [format]：模块格式（ES module 或 CommonJS）。
  const JsModule({
    required this.name,
    required this.source,
    this.format = JsModuleFormat.esModule,
  }) : path = null,
       bundle = null;

  /// 使用 Flutter asset 创建宿主模块描述（同步构造）。
  ///
  /// asset 源码在 runtime 构建模块图时通过 [loadSource] 延迟加载。
  ///
  /// - [name]：JS `import` / `require` 使用的模块名。
  /// - [path]：模块源码所在的 Flutter asset 路径。
  /// - [bundle]：读取 asset 时使用的 bundle。
  /// - [format]：模块格式（ES module 或 CommonJS）。
  const JsModule.asset({
    required this.name,
    required this.path,
    this.bundle,
    this.format = JsModuleFormat.esModule,
  }) : source = null;

  /// 创建 ES 格式宿主模块（内联源码）。
  /// 创建 CommonJS 格式宿主模块（内联源码）。
  const JsModule.commonJs({required String name, required String source})
    : this(name: name, source: source, format: JsModuleFormat.commonJs);

  /// 创建 CommonJS 格式宿主模块（Flutter asset，同步构造）。
  const JsModule.commonJsAsset({
    required String name,
    required String path,
    AssetBundle? bundle,
  }) : this.asset(
         name: name,
         path: path,
         bundle: bundle,
         format: JsModuleFormat.commonJs,
       );

  /// JS `import` 或 `require` 使用的模块名。
  final String name;

  /// 内联模块 JavaScript 源码；与 [path] 二选一。
  final String? source;

  /// 包含模块源码的 Flutter asset 路径。
  final String? path;

  /// 解析 [path] 时使用的 asset bundle。
  final AssetBundle? bundle;

  /// 模块格式（ES module 或 CommonJS）。
  final JsModuleFormat format;

  /// 加载模块源码：优先返回内联 [source]，否则从 [path] 读取 asset。
  Future<String> loadSource() async {
    final inlineSource = source;
    if (inlineSource != null) {
      return inlineSource;
    }
    final key = path;
    if (key == null) {
      throw JsValueConversionException(
        'QuickJS host module "$name" has no source or path',
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

/// 创建时注入并在引擎重建后恢复的 Dart 宿主方法。
///
/// [JsHostMethod.global] 直接安装全局方法；默认构造提供内部方法名，
/// 由启动脚本或宿主模块包装成 `fetch()`、`crypto.subtle.digest()` 等 API。
final class JsHostMethod {
  /// Creates a persistent named host method descriptor.
  const JsHostMethod({
    required this.name,
    required this.callback,
    this.debugName,
    this.globalName,
    this.implementation = JsHostMethodImplementation.dart,
  });

  /// Creates a persistent host method installed directly on globalThis.
  factory JsHostMethod.global({
    required String name,
    required JsHostMethodCallback callback,
    String? debugName,
    JsHostMethodImplementation implementation = JsHostMethodImplementation.dart,
  }) {
    final globalName = _validateHostScriptGlobalName(name);
    return JsHostMethod(
      name: 'global.$globalName',
      globalName: globalName,
      debugName: debugName,
      implementation: implementation,
      callback: callback,
    );
  }

  /// JavaScript 包装器使用的 runtime 级宿主方法名。
  final String name;

  /// Optional readable name for debug snapshots.
  final String? debugName;

  /// Optional global function name installed as a direct wrapper for [name].
  ///
  /// Use this for simple `globalThis.foo(...)` APIs. Leave it null when a
  /// startup script or module needs to expose a richer API shape, such as
  /// `fetch()` or `crypto.subtle.digest()`.
  final String? globalName;

  /// Declared source of the method implementation.
  ///
  /// This is inspector metadata and does not change callback behavior. All
  /// current methods use the asynchronous callback bridge.
  final JsHostMethodImplementation implementation;

  /// Dart/Flutter implementation. JS receives a Promise for each call.
  ///
  /// The per-call context is cancelled when the runtime restarts, is disposed,
  /// or is rebuilt. Await [JsHostMethodContext.cancelled] when the
  /// underlying operation supports cooperative cancellation.
  final JsHostMethodCallback callback;
}

/// 宿主方法的实现来源。
enum JsHostMethodImplementation {
  /// Pure Dart or Flutter code running in the host isolate.
  dart,

  /// A Dart callback backed by a platform API or platform channel.
  platform,

  /// A Dart callback backed by a browser/Web API.
  web,
}

/// Named bundle of environment patches, modules, and host methods.
///
/// A features installs one composable capability bundle into a runtime.
base class JsFeatures {
  /// Creates one named, composable runtime feature bundle.
  const JsFeatures({
    required this.name,
    this.browserGlobals = const JsGlobals(),
    this.scripts = const <JsScript>[],
    this.modules = const <JsModule>[],
    this.methods = const <JsHostMethod>[],
  });

  /// Stable name used for conflict detection and debug inspection.
  final String name;

  /// Browser-like global aliases installed before scripts.
  final JsGlobals browserGlobals;

  /// Ordered scripts that complete the runtime global environment.
  final List<JsScript> scripts;

  /// ES module and CommonJS definitions included in this features.
  final List<JsModule> modules;

  /// 注入 JavaScript 的 Dart/Flutter 宿主方法。
  final List<JsHostMethod> methods;
}

/// Resource and execution-queue limits used when creating a QuickJS runtime.
final class JsOptions {
  /// Creates runtime resource and waiting-task limits.
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
