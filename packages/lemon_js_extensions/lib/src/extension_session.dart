import 'dart:async';

import 'package:lemon_js/lemon_js_internal.dart';

import 'extension.dart';
import 'extension_capabilities.dart';

/// 扩展 Session 的生命周期状态。
enum JsExtensionSessionState {
  /// 尚未启动 Core service，或已重启并等待下一次调用。
  inactive,

  /// Core service Runtime 已启动并可接受调用。
  active,

  /// Runtime 遇到终止性故障，等待下一次调用重建。
  failed,

  /// Session 已禁用，调用会被拒绝。
  disabled,

  /// Session 已永久释放，不能再次启用。
  disposed,
}

/// 可由宿主替换的 Core 服务运行时接口。
abstract interface class JsExtensionServiceRuntime implements JsPluginHost {
  /// 关闭 Runtime 并释放其持有的资源。
  Future<void> close();
}

/// 可向 Session 报告底层执行状态的 Runtime 可选能力。
abstract interface class JsExtensionStatefulRuntime {
  /// 底层 Runtime 的当前生命周期状态。
  JsRuntimeState get runtimeState;
}

/// 创建扩展 Core 服务运行时的工厂。
typedef JsExtensionRuntimeFactory =
    Future<JsExtensionServiceRuntime> Function({
      required JsOptions options,
      required List<JsFeatures> features,
    });

/// 在 Core 与 JSUI 组件之间共享的扩展生命周期和能力边界。
final class JsExtensionSession {
  /// 创建扩展 Session。
  ///
  /// [maxPendingTasks] 限制 Core service 执行队列中等待的任务数；当前正在
  /// 执行的任务不计入。队列已满时新调用立即抛出 [JsQueueFullException]。
  /// [callTimeout] 是未给单次调用传入 `timeout` 时使用的默认超时时间。
  JsExtensionSession({
    required this.extension,
    JsKvStore? storage,
    Iterable<String> grantedPermissions = const <String>[],
    List<JsFeatures> sharedFeatures = const <JsFeatures>[],
    List<JsFeatures> serviceFeatures = const <JsFeatures>[],
    List<JsFeatures> uiFeatures = const <JsFeatures>[],
    JsExtensionFeatures? features,
    this.maxPendingTasks = 64,
    this.callTimeout = const Duration(seconds: 30),
    JsExtensionRuntimeFactory? runtimeFactory,
  }) : storage = storage ?? JsSharedPreferencesKvStore(),
       grantedPermissions = Set<String>.unmodifiable(grantedPermissions),
       _runtimeFactory = runtimeFactory ?? _defaultRuntimeFactory {
    if (maxPendingTasks < 1) {
      throw ArgumentError.value(
        maxPendingTasks,
        'maxPendingTasks',
        'must be positive',
      );
    }
    if (callTimeout <= Duration.zero) {
      throw ArgumentError.value(callTimeout, 'callTimeout', 'must be positive');
    }
    final undeclared = this.grantedPermissions.difference(
      extension.manifest.permissions.toSet(),
    );
    if (undeclared.isNotEmpty) {
      throw ArgumentError(
        'Granted permissions are not declared by extension: '
        '${undeclared.join(', ')}',
      );
    }
    final hostFeatures = features ?? JsExtensionFeatures.defaults();
    final injectedFeatures = <JsFeatures>[];
    final storageFactory = hostFeatures.storageFactory;
    if (storageFactory != null) {
      injectedFeatures.add(storageFactory(id, this.storage));
    }
    final httpFactory = hostFeatures.httpFactory;
    if (httpFactory != null) {
      _ownedHttpSession = httpFactory();
      injectedFeatures.add(AxiosFeatures.session(session: _ownedHttpSession!));
    }
    final cryptoFactory = hostFeatures.cryptoFactory;
    if (cryptoFactory != null) injectedFeatures.add(cryptoFactory());
    this.sharedFeatures = List<JsFeatures>.unmodifiable(<JsFeatures>[
      ...sharedFeatures,
      ...injectedFeatures,
    ]);
    this.serviceFeatures = List<JsFeatures>.unmodifiable(serviceFeatures);
    this.uiFeatures = List<JsFeatures>.unmodifiable(uiFeatures);
  }

  /// 此 Session 执行的已解析扩展。
  final JsExtension extension;

  /// 扩展使用的持久化 KV Store。
  final JsKvStore storage;

  /// 宿主实际授予扩展的权限集合。
  final Set<String> grantedPermissions;

  /// 同时注入 Core service 与所有 UI route 的宿主能力。
  late final List<JsFeatures> sharedFeatures;

  /// 仅注入 Core service Runtime 的宿主能力。
  late final List<JsFeatures> serviceFeatures;

  /// 仅注入 UI route Runtime 的宿主能力。
  late final List<JsFeatures> uiFeatures;

  /// Core service 执行队列允许等待的最大任务数。
  final int maxPendingTasks;

  /// Core service 单次调用的默认超时时间。
  final Duration callTimeout;
  final JsExtensionRuntimeFactory _runtimeFactory;

  JsExtensionSessionState _state = JsExtensionSessionState.inactive;
  JsExtensionServiceRuntime? _serviceRuntime;
  Future<JsExtensionServiceRuntime>? _startingRuntime;
  Future<void>? _runtimeCleanup;
  JsHttpSession? _ownedHttpSession;

  /// 扩展清单中的稳定标识符。
  String get id => extension.id;

  /// Session 的当前生命周期状态。
  JsExtensionSessionState get state => _state;

  /// Core service Runtime 当前是否已经启动。
  bool get hasStartedService => _serviceRuntime != null;

  /// 释放当前 Core Runtime；其内存状态会丢失，下次调用将重新创建并执行插件初始化。
  Future<void> restart() async {
    _ensureUsable();
    await _closeRuntime();
    _state = JsExtensionSessionState.inactive;
  }

  /// 调用清单中对宿主公开的 service 方法。
  Future<Object?> callPublic(
    String method, {
    List<Object?> arguments = const <Object?>[],
    Duration? timeout,
  }) {
    final service = _requireService();
    if (!service.publicExports.contains(method)) {
      throw StateError(
        'Extension "$id" does not expose public service method "$method"',
      );
    }
    return _call(service, method, arguments, timeout: timeout);
  }

  /// 调用清单中仅向扩展 UI 公开的 service 方法。
  Future<Object?> callUi(
    String method, {
    List<Object?> arguments = const <Object?>[],
    Duration? timeout,
  }) {
    final service = _requireService();
    if (!service.uiExports.contains(method)) {
      throw StateError(
        'Extension "$id" does not expose UI service method "$method"',
      );
    }
    return _call(service, method, arguments, timeout: timeout);
  }

  /// 调用插件声明的内部 KV 迁移函数。
  Future<Object?> migrateStorage(int fromVersion, int toVersion) {
    final service = _requireService();
    final method = service.storageMigrationExport;
    if (method == null) {
      throw StateError(
        'Extension "$id" does not declare service.storageMigrationExport',
      );
    }
    return _call(service, method, <Object?>[fromVersion, toVersion]);
  }

  /// 为 [route] 组装经过权限校验的 JSUI Runtime 能力。
  List<JsFeatures> featuresForRoute(
    String route, {
    List<JsFeatures> routeFeatures = const <JsFeatures>[],
  }) {
    _ensureUsable();
    final routeManifest = extension.ui?.routes[route];
    if (routeManifest == null) {
      throw StateError('Extension "$id" has no UI route "$route"');
    }
    final missing = routeManifest.permissions.toSet().difference(
      grantedPermissions,
    );
    if (missing.isNotEmpty) {
      throw StateError(
        'Extension route "$route" lacks granted permissions: '
        '${missing.join(', ')}',
      );
    }
    return List<JsFeatures>.unmodifiable(<JsFeatures>[
      ...sharedFeatures,
      ...uiFeatures,
      if (extension.service != null) JsExtensionServiceFeatures(this),
      ...routeFeatures,
    ]);
  }

  /// 禁用 Session 并关闭当前 Core service Runtime。
  Future<void> disable() async {
    if (_state == JsExtensionSessionState.disposed) return;
    _state = JsExtensionSessionState.disabled;
    await _closeRuntime();
  }

  /// 重新启用已禁用或故障的 Session。
  void enable() {
    if (_state == JsExtensionSessionState.disposed) {
      throw StateError('Extension session "$id" is disposed');
    }
    _state = JsExtensionSessionState.inactive;
  }

  /// 永久释放 Session；[clearStorage] 为真时同时清空扩展命名空间。
  Future<void> dispose({bool clearStorage = false}) async {
    if (_state == JsExtensionSessionState.disposed) return;
    _state = JsExtensionSessionState.disposed;
    try {
      await _closeRuntime();
      if (clearStorage) await storage.clear(namespace: id);
    } finally {
      _ownedHttpSession?.close();
      _ownedHttpSession = null;
    }
  }

  JsExtensionServiceComponent _requireService() {
    _ensureUsable();
    final service = extension.service;
    if (service == null) {
      throw StateError('Extension "$id" has no service component');
    }
    return service;
  }

  void _ensureUsable() {
    if (_state == JsExtensionSessionState.disabled) {
      throw StateError('Extension session "$id" is disabled');
    }
    if (_state == JsExtensionSessionState.disposed) {
      throw StateError('Extension session "$id" is disposed');
    }
  }

  Future<Object?> _call(
    JsExtensionServiceComponent service,
    String method,
    List<Object?> arguments, {
    Duration? timeout,
  }) async {
    final runtime = await _ensureRuntime(service);
    try {
      return await runtime.callPluginExport(
        service.plugin,
        method,
        arguments,
        timeout: timeout ?? callTimeout,
      );
    } catch (error) {
      if (_isTerminalRuntimeFailure(error, runtime)) {
        await _discardFailedRuntime(runtime);
      }
      rethrow;
    }
  }

  Future<JsExtensionServiceRuntime> _ensureRuntime(
    JsExtensionServiceComponent service,
  ) async {
    await _runtimeCleanup;
    _ensureUsable();
    final current = _serviceRuntime;
    if (current != null) return current;
    final starting = _startingRuntime;
    if (starting != null) return starting;
    final future = _createRuntime(service);
    _startingRuntime = future;
    try {
      final runtime = await future;
      if (_state == JsExtensionSessionState.disabled ||
          _state == JsExtensionSessionState.disposed) {
        await runtime.close();
        throw StateError('Extension session "$id" stopped during startup');
      }
      _serviceRuntime = runtime;
      _state = JsExtensionSessionState.active;
      return runtime;
    } finally {
      _startingRuntime = null;
    }
  }

  Future<JsExtensionServiceRuntime> _createRuntime(
    JsExtensionServiceComponent service,
  ) async {
    final runtime = await _runtimeFactory(
      options: JsOptions(maxPendingTasks: maxPendingTasks),
      features: <JsFeatures>[
        ...sharedFeatures,
        ...serviceFeatures,
        service.plugin.asFeatures(),
      ],
    );
    try {
      await runtime.validatePlugin(service.plugin);
      await runtime.initPlugin(
        service.plugin,
        context: <String, Object?>{
          'extensionId': id,
          'permissions': grantedPermissions.toList(growable: false),
        },
      );
      return runtime;
    } catch (_) {
      await runtime.close();
      rethrow;
    }
  }

  Future<void> _closeRuntime() async {
    await _runtimeCleanup;
    final starting = _startingRuntime;
    if (starting != null) {
      try {
        await starting;
      } catch (_) {
        // Startup already performs cleanup.
      }
    }
    final runtime = _serviceRuntime;
    _serviceRuntime = null;
    if (runtime == null) return;
    final stateful = runtime is JsExtensionStatefulRuntime
        ? runtime as JsExtensionStatefulRuntime
        : null;
    final plugin = extension.service?.plugin;
    if (plugin != null &&
        (stateful == null || stateful.runtimeState == JsRuntimeState.ready)) {
      try {
        await runtime.disposePlugin(plugin);
      } catch (_) {
        // Runtime disposal remains mandatory after plugin cleanup fails.
      }
    }
    await runtime.close();
  }

  Future<void> _discardFailedRuntime(JsExtensionServiceRuntime runtime) async {
    if (!identical(_serviceRuntime, runtime)) return;
    _serviceRuntime = null;
    _state = JsExtensionSessionState.failed;
    final cleanup = () async {
      try {
        await runtime.close();
      } catch (_) {
        // 故障 Runtime 的资源清理是 best effort，原始调用错误必须保留。
      }
    }();
    _runtimeCleanup = cleanup;
    try {
      await cleanup;
    } finally {
      if (identical(_runtimeCleanup, cleanup)) _runtimeCleanup = null;
    }
  }
}

bool _isTerminalRuntimeFailure(
  Object error,
  JsExtensionServiceRuntime runtime,
) {
  if (error is JsRuntimeCrashException ||
      error is JsRuntimeClosedException ||
      error is JsOutOfMemoryException) {
    return true;
  }
  if (runtime is! JsExtensionStatefulRuntime) return false;
  final stateful = runtime as JsExtensionStatefulRuntime;
  return stateful.runtimeState == JsRuntimeState.failed ||
      stateful.runtimeState == JsRuntimeState.closed;
}

/// 将同一 Session 的受限 Core 方法暴露给 JSUI。
final class JsExtensionServiceFeatures extends JsFeatures {
  /// 创建将 [session] 的 UI service 导出注入 JSUI 的能力集合。
  JsExtensionServiceFeatures(JsExtensionSession session)
    : super(
        name: 'lemon_js_extensions.service.${session.id}',
        methods: <JsHostMethod>[
          JsHostMethod(
            name: 'lemon_js_extensions.service.${session.id}.call',
            debugName: 'extension-service:${session.id}',
            callback: (arguments, context) async {
              if (arguments.length != 2 || arguments.first is! String) {
                throw ArgumentError(
                  'pluginService.call expects a method and argument list',
                );
              }
              final method = arguments.first! as String;
              final rawArguments = arguments[1];
              if (rawArguments is! List) {
                throw ArgumentError(
                  'pluginService.call arguments must be a list',
                );
              }
              final result = await session.callUi(
                method,
                arguments: rawArguments.cast<Object?>(),
              );
              context.throwIfCancelled();
              return result;
            },
          ),
        ],
        modules: <JsModule>[
          JsModule(
            name: 'lemon_js_extensions/plugin_service',
            source: _serviceModuleSource(session.id),
          ),
        ],
      );
}

String _serviceModuleSource(String extensionId) =>
    '''
const methodBridge = globalThis.__jsHostMethods[
  'lemon_js_extensions.service.$extensionId.call'
];

export const pluginService = Object.freeze({
  call(method, ...args) {
    return methodBridge(String(method), args);
  },
});

export default pluginService;
''';

Future<JsExtensionServiceRuntime> _defaultRuntimeFactory({
  required JsOptions options,
  required List<JsFeatures> features,
}) async => _RuntimeAdapter(
  await JsEngine.create(options: options, features: features),
);

final class _RuntimeAdapter
    implements JsExtensionServiceRuntime, JsExtensionStatefulRuntime {
  _RuntimeAdapter(this.engine);

  final JsEngine engine;

  @override
  JsRuntimeState get runtimeState => engine.state;

  @override
  Future<void> close() => engine.dispose();

  @override
  Future<Object?> callPluginExport(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) => engine.callPluginExport(plugin, method, args, timeout: timeout);

  @override
  Future<Object?> disposePlugin(JsPlugin plugin, {Duration? timeout}) =>
      engine.disposePlugin(plugin, timeout: timeout);

  @override
  Future<Object?> initPlugin(
    JsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) => engine.initPlugin(plugin, context: context, timeout: timeout);

  @override
  Future<void> validatePlugin(JsPlugin plugin, {Duration? timeout}) =>
      engine.validatePlugin(plugin, timeout: timeout);
}
