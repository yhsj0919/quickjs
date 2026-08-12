import 'dart:async';

import 'package:lemon_js/lemon_js.dart';

import 'quickjs_extension.dart';
import 'quickjs_extension_storage.dart';

/// 扩展 Session 的生命周期状态。
enum QuickjsExtensionSessionState { inactive, active, disabled, disposed }

/// 可由宿主替换的 Core 服务运行时接口。
abstract interface class QuickjsExtensionServiceRuntime
    implements QuickjsPluginHost {
  Future<void> close();
}

/// 创建扩展 Core 服务运行时的工厂。
typedef QuickjsExtensionRuntimeFactory =
    Future<QuickjsExtensionServiceRuntime> Function(
      QuickjsRuntimeOptions options,
    );

/// 在 Core 与 JSUI 组件之间共享的扩展生命周期和能力边界。
final class QuickjsExtensionSession {
  QuickjsExtensionSession({
    required this.extension,
    QuickjsExtensionStorage? storage,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsHostMount> sharedMounts = const <QuickjsHostMount>[],
    List<QuickjsHostMount> serviceMounts = const <QuickjsHostMount>[],
    List<QuickjsHostMount> uiMounts = const <QuickjsHostMount>[],
    QuickjsExtensionRuntimeFactory? runtimeFactory,
  }) : storage = storage ?? InMemoryQuickjsExtensionStorage(),
       grantedPermissions = Set<String>.unmodifiable(grantedPermissions),
       sharedMounts = List<QuickjsHostMount>.unmodifiable(sharedMounts),
       serviceMounts = List<QuickjsHostMount>.unmodifiable(serviceMounts),
       uiMounts = List<QuickjsHostMount>.unmodifiable(uiMounts),
       _runtimeFactory = runtimeFactory ?? _defaultRuntimeFactory {
    final undeclared = this.grantedPermissions.difference(
      extension.manifest.permissions.toSet(),
    );
    if (undeclared.isNotEmpty) {
      throw ArgumentError(
        'Granted permissions are not declared by extension: '
        '${undeclared.join(', ')}',
      );
    }
  }

  final QuickjsExtension extension;
  final QuickjsExtensionStorage storage;
  final Set<String> grantedPermissions;
  final List<QuickjsHostMount> sharedMounts;
  final List<QuickjsHostMount> serviceMounts;
  final List<QuickjsHostMount> uiMounts;
  final QuickjsExtensionRuntimeFactory _runtimeFactory;

  QuickjsExtensionSessionState _state = QuickjsExtensionSessionState.inactive;
  QuickjsExtensionServiceRuntime? _serviceRuntime;
  Future<QuickjsExtensionServiceRuntime>? _startingRuntime;

  String get id => extension.id;
  QuickjsExtensionSessionState get state => _state;
  bool get hasStartedService => _serviceRuntime != null;

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

  List<QuickjsHostMount> mountsForRoute(
    String route, {
    List<QuickjsHostMount> routeMounts = const <QuickjsHostMount>[],
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
    return List<QuickjsHostMount>.unmodifiable(<QuickjsHostMount>[
      ...sharedMounts,
      ...uiMounts,
      if (grantedPermissions.contains('storage'))
        QuickjsExtensionStorageMount(extensionId: id, storage: storage),
      if (extension.service != null) QuickjsExtensionServiceBridgeMount(this),
      ...routeMounts,
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
    await _closeRuntime();
    if (clearStorage) await storage.clear(id);
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
    return runtime.callPlugin(
      service.plugin,
      method,
      arguments,
      timeout: timeout,
    );
  }

  Future<QuickjsExtensionServiceRuntime> _ensureRuntime(
    QuickjsServiceComponent service,
  ) async {
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
      QuickjsRuntimeOptions(
        mounts: <QuickjsHostMount>[
          ...sharedMounts,
          ...serviceMounts,
          service.plugin.asMount(),
          if (grantedPermissions.contains('storage'))
            QuickjsExtensionStorageMount(extensionId: id, storage: storage),
        ],
      ),
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
    final plugin = extension.service?.plugin;
    if (plugin != null) {
      try {
        await runtime.disposePlugin(plugin);
      } catch (_) {
        // Runtime disposal remains mandatory after plugin cleanup fails.
      }
    }
    await runtime.close();
  }
}

/// 将同一 Session 的受限 Core 方法暴露给 JSUI。
final class QuickjsExtensionServiceBridgeMount extends QuickjsHostMount {
  QuickjsExtensionServiceBridgeMount(QuickjsExtensionSession session)
    : super(
        name: 'quickjs_extensions.service.${session.id}',
        providers: <QuickjsHostProvider>[
          QuickjsHostProvider.dart(
            name: 'quickjs_extensions.service.${session.id}.call',
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
        modules: <QuickjsHostModule>[
          QuickjsHostModule.esModule(
            specifier: 'quickjs_extensions/plugin_service',
            source: _serviceModuleSource(session.id),
          ),
        ],
      );
}

String _serviceModuleSource(String extensionId) =>
    '''
const provider = globalThis.__quickjsHostProviders[
  'quickjs_extensions.service.$extensionId.call'
];

export const pluginService = Object.freeze({
  call(method, ...args) {
    return provider(String(method), args);
  },
});

export default pluginService;
''';

Future<QuickjsExtensionServiceRuntime> _defaultRuntimeFactory(
  QuickjsRuntimeOptions options,
) async => _QuickjsRuntimeAdapter(await Quickjs.create(options: options));

final class _QuickjsRuntimeAdapter implements QuickjsExtensionServiceRuntime {
  _QuickjsRuntimeAdapter(this.engine);

  final Quickjs engine;

  @override
  Future<void> close() => engine.dispose();

  @override
  Future<Object?> callPlugin(
    QuickjsPlugin plugin,
    String method,
    List<Object?> args, {
    Duration? timeout,
  }) => engine.callPlugin(plugin, method, args, timeout: timeout);

  @override
  Future<Object?> disposePlugin(QuickjsPlugin plugin, {Duration? timeout}) =>
      engine.disposePlugin(plugin, timeout: timeout);

  @override
  Future<Object?> initPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> context = const <String, Object?>{},
    Duration? timeout,
  }) => engine.initPlugin(plugin, context: context, timeout: timeout);

  @override
  Future<void> validatePlugin(QuickjsPlugin plugin, {Duration? timeout}) =>
      engine.validatePlugin(plugin, timeout: timeout);
}
