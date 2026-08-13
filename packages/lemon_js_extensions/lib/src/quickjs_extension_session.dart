import 'dart:async';

import 'package:lemon_js/lemon_js.dart';

import 'quickjs_extension.dart';
import 'quickjs_extension_capabilities.dart';
import 'quickjs_extension_storage.dart';

/// 扩展 Session 的生命周期状态。
enum QuickjsExtensionSessionState {
  inactive,
  active,
  failed,
  disabled,
  disposed,
}

/// 可由宿主替换的 Core 服务运行时接口。
abstract interface class QuickjsExtensionServiceRuntime
    implements JsPluginHost {
  Future<void> close();
}

/// 可向 Session 报告底层执行状态的 Runtime 可选能力。
abstract interface class QuickjsExtensionStatefulRuntime {
  JsRuntimeState get runtimeState;
}

/// 创建扩展 Core 服务运行时的工厂。
typedef QuickjsExtensionRuntimeFactory =
    Future<QuickjsExtensionServiceRuntime> Function({
      required JsOptions options,
      required List<JsFeatures> features,
    });

/// 在 Core 与 JSUI 组件之间共享的扩展生命周期和能力边界。
final class QuickjsExtensionSession {
  QuickjsExtensionSession({
    required this.extension,
    QuickjsExtensionStorage? storage,
    Iterable<String> grantedPermissions = const <String>[],
    List<JsFeatures> sharedFeatures = const <JsFeatures>[],
    List<JsFeatures> serviceFeatures = const <JsFeatures>[],
    List<JsFeatures> uiFeatures = const <JsFeatures>[],
    QuickjsExtensionOptionalCapabilities? optionalCapabilities,
    this.maxPendingCoreCalls = 64,
    this.defaultCallTimeout = const Duration(seconds: 30),
    QuickjsExtensionRuntimeFactory? runtimeFactory,
  }) : storage = storage ?? SharedPreferencesJsKvStore(),
       grantedPermissions = Set<String>.unmodifiable(grantedPermissions),
       _runtimeFactory = runtimeFactory ?? _defaultRuntimeFactory {
    if (maxPendingCoreCalls < 1) {
      throw ArgumentError.value(
        maxPendingCoreCalls,
        'maxPendingCoreCalls',
        'must be positive',
      );
    }
    if (defaultCallTimeout <= Duration.zero) {
      throw ArgumentError.value(
        defaultCallTimeout,
        'defaultCallTimeout',
        'must be positive',
      );
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
    final capabilities =
        optionalCapabilities ?? QuickjsExtensionOptionalCapabilities.defaults();
    final capabilityMounts = <JsFeatures>[];
    final storageFactory = capabilities.storageFeaturesFactory;
    if (storageFactory != null) {
      capabilityMounts.add(storageFactory(id, this.storage));
    }
    final httpFactory = capabilities.httpSessionFactory;
    if (httpFactory != null) {
      _ownedHttpSession = httpFactory();
      capabilityMounts.add(
        AxiosFeatures.session(
          assetKey: quickjsExtensionAxiosAsset,
          session: _ownedHttpSession!,
        ),
      );
    }
    final cryptoFactory = capabilities.cryptoMountFactory;
    if (cryptoFactory != null) capabilityMounts.add(cryptoFactory());
    this.sharedFeatures = List<JsFeatures>.unmodifiable(<JsFeatures>[
      ...sharedFeatures,
      ...capabilityMounts,
    ]);
    this.serviceFeatures = List<JsFeatures>.unmodifiable(serviceFeatures);
    this.uiFeatures = List<JsFeatures>.unmodifiable(uiFeatures);
  }

  final QuickjsExtension extension;
  final QuickjsExtensionStorage storage;
  final Set<String> grantedPermissions;
  late final List<JsFeatures> sharedFeatures;
  late final List<JsFeatures> serviceFeatures;
  late final List<JsFeatures> uiFeatures;
  final int maxPendingCoreCalls;
  final Duration defaultCallTimeout;
  final QuickjsExtensionRuntimeFactory _runtimeFactory;

  QuickjsExtensionSessionState _state = QuickjsExtensionSessionState.inactive;
  QuickjsExtensionServiceRuntime? _serviceRuntime;
  Future<QuickjsExtensionServiceRuntime>? _startingRuntime;
  Future<void>? _runtimeCleanup;
  JsHttpSession? _ownedHttpSession;

  String get id => extension.id;
  QuickjsExtensionSessionState get state => _state;
  bool get hasStartedService => _serviceRuntime != null;

  /// 释放当前 Core Runtime；其内存状态会丢失，下次调用将重新创建并执行插件初始化。
  Future<void> restart() async {
    _ensureUsable();
    await _closeRuntime();
    _state = QuickjsExtensionSessionState.inactive;
  }

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
      if (extension.service != null) QuickjsExtensionServiceFeatures(this),
      ...routeFeatures,
    ]);
  }

  Future<void> disable() async {
    if (_state == QuickjsExtensionSessionState.disposed) return;
    _state = QuickjsExtensionSessionState.disabled;
    await _closeRuntime();
  }

  void enable() {
    if (_state == QuickjsExtensionSessionState.disposed) {
      throw StateError('Extension session "$id" is disposed');
    }
    _state = QuickjsExtensionSessionState.inactive;
  }

  Future<void> dispose({bool clearStorage = false}) async {
    if (_state == QuickjsExtensionSessionState.disposed) return;
    _state = QuickjsExtensionSessionState.disposed;
    try {
      await _closeRuntime();
      if (clearStorage) await storage.clear(namespace: id);
    } finally {
      _ownedHttpSession?.close();
      _ownedHttpSession = null;
    }
  }

  QuickjsServiceComponent _requireService() {
    _ensureUsable();
    final service = extension.service;
    if (service == null) {
      throw StateError('Extension "$id" has no service component');
    }
    return service;
  }

  void _ensureUsable() {
    if (_state == QuickjsExtensionSessionState.disabled) {
      throw StateError('Extension session "$id" is disabled');
    }
    if (_state == QuickjsExtensionSessionState.disposed) {
      throw StateError('Extension session "$id" is disposed');
    }
  }

  Future<Object?> _call(
    QuickjsServiceComponent service,
    String method,
    List<Object?> arguments, {
    Duration? timeout,
  }) async {
    final runtime = await _ensureRuntime(service);
    try {
      return await runtime.callPlugin(
        service.plugin,
        method,
        arguments,
        timeout: timeout ?? defaultCallTimeout,
      );
    } catch (error) {
      if (_isTerminalRuntimeFailure(error, runtime)) {
        await _discardFailedRuntime(runtime);
      }
      rethrow;
    }
  }

  Future<QuickjsExtensionServiceRuntime> _ensureRuntime(
    QuickjsServiceComponent service,
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
      if (_state == QuickjsExtensionSessionState.disabled ||
          _state == QuickjsExtensionSessionState.disposed) {
        await runtime.close();
        throw StateError('Extension session "$id" stopped during startup');
      }
      _serviceRuntime = runtime;
      _state = QuickjsExtensionSessionState.active;
      return runtime;
    } finally {
      _startingRuntime = null;
    }
  }

  Future<QuickjsExtensionServiceRuntime> _createRuntime(
    QuickjsServiceComponent service,
  ) async {
    final runtime = await _runtimeFactory(
      options: JsOptions(maxPendingTasks: maxPendingCoreCalls),
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
    final stateful = runtime is QuickjsExtensionStatefulRuntime
        ? runtime as QuickjsExtensionStatefulRuntime
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

  Future<void> _discardFailedRuntime(
    QuickjsExtensionServiceRuntime runtime,
  ) async {
    if (!identical(_serviceRuntime, runtime)) return;
    _serviceRuntime = null;
    _state = QuickjsExtensionSessionState.failed;
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
  QuickjsExtensionServiceRuntime runtime,
) {
  if (error is JsRuntimeCrashException ||
      error is JsRuntimeClosedException ||
      error is JsOutOfMemoryException) {
    return true;
  }
  if (runtime is! QuickjsExtensionStatefulRuntime) return false;
  final stateful = runtime as QuickjsExtensionStatefulRuntime;
  return stateful.runtimeState == JsRuntimeState.failed ||
      stateful.runtimeState == JsRuntimeState.closed;
}

/// 将同一 Session 的受限 Core 方法暴露给 JSUI。
final class QuickjsExtensionServiceFeatures extends JsFeatures {
  QuickjsExtensionServiceFeatures(QuickjsExtensionSession session)
    : super(
        name: 'lemon_js_extensions.service.${session.id}',
        providers: <JsProvider>[
          JsProvider.dart(
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
          JsModule.esModule(
            specifier: 'lemon_js_extensions/plugin_service',
            source: _serviceModuleSource(session.id),
          ),
        ],
      );
}

String _serviceModuleSource(String extensionId) =>
    '''
const provider = globalThis.__quickjsHostProviders[
  'lemon_js_extensions.service.$extensionId.call'
];

export const pluginService = Object.freeze({
  call(method, ...args) {
    return provider(String(method), args);
  },
});

export default pluginService;
''';

Future<QuickjsExtensionServiceRuntime> _defaultRuntimeFactory({
  required JsOptions options,
  required List<JsFeatures> features,
}) async => _QuickjsRuntimeAdapter(
  await Quickjs.create(options: options, features: features),
);

final class _QuickjsRuntimeAdapter
    implements QuickjsExtensionServiceRuntime, QuickjsExtensionStatefulRuntime {
  _QuickjsRuntimeAdapter(this.engine);

  final Quickjs engine;

  @override
  JsRuntimeState get runtimeState => engine.state;

  @override
  Future<void> close() => engine.dispose();

  @override
  Future<Object?> callPlugin(
    JsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) => engine.callPlugin(plugin, method, args, timeout: timeout);

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
