import 'package:lemon_js/lemon_js.dart';

import 'quickjs_extension.dart';
import 'quickjs_extension_capabilities.dart';
import 'quickjs_extension_session.dart';
import 'quickjs_extension_storage.dart';

/// 已安装扩展及其共享 Session。
final class InstalledQuickjsExtension {
  const InstalledQuickjsExtension({
    required this.extension,
    required this.session,
  });

  final QuickjsExtension extension;
  final QuickjsExtensionSession session;

  String get id => extension.id;
  bool get enabled =>
      session.state != QuickjsExtensionSessionState.disabled &&
      session.state != QuickjsExtensionSessionState.disposed;
}

/// 可直接打开的扩展交互流程引用。
final class QuickjsExtensionFlowReference {
  const QuickjsExtensionFlowReference({
    required this.installed,
    required this.flowId,
    required this.route,
  });

  final InstalledQuickjsExtension installed;
  final String flowId;
  final String route;
}

/// 保存并查询当前宿主已安装扩展的内存注册表。
final class QuickjsExtensionRegistry {
  final Map<String, InstalledQuickjsExtension> _installed =
      <String, InstalledQuickjsExtension>{};

  Iterable<InstalledQuickjsExtension> get installed =>
      _installed.values.where((item) => item.enabled);

  InstalledQuickjsExtension? find(String id) => _installed[id];

  Iterable<InstalledQuickjsExtension> servicesForContract(String contract) =>
      installed.where((item) => item.extension.service?.contract == contract);

  QuickjsExtensionFlowReference? findFlow(String extensionId, String flowId) {
    final item = _installed[extensionId];
    if (item == null || !item.enabled) return null;
    final flow = item.extension.manifest.flows[flowId];
    if (flow == null) return null;
    return QuickjsExtensionFlowReference(
      installed: item,
      flowId: flowId,
      route: flow.route,
    );
  }

  void register(InstalledQuickjsExtension extension) {
    if (_installed.containsKey(extension.id)) {
      throw StateError(
        'QuickJS extension is already installed: ${extension.id}',
      );
    }
    _installed[extension.id] = extension;
  }

  Future<void> disable(String id) async {
    final item = _require(id);
    await item.session.disable();
  }

  void enable(String id) => _require(id).session.enable();

  Future<void> uninstall(String id, {bool clearStorage = false}) async {
    final item = _installed.remove(id);
    if (item == null) return;
    await item.session.dispose(clearStorage: clearStorage);
  }

  InstalledQuickjsExtension _require(String id) {
    final item = _installed[id];
    if (item == null) {
      throw StateError('QuickJS extension is not installed: $id');
    }
    return item;
  }
}

/// 校验授权并将扩展安装到注册表。
final class QuickjsExtensionInstaller {
  QuickjsExtensionInstaller({
    required this.registry,
    QuickjsExtensionStorage? storage,
  }) : storage = storage ?? SharedPreferencesJsKvStore();

  final QuickjsExtensionRegistry registry;
  final QuickjsExtensionStorage storage;

  InstalledQuickjsExtension install(
    QuickjsExtension extension, {
    Iterable<String> grantedPermissions = const <String>[],
    List<JsFeatures> sharedFeatures = const <JsFeatures>[],
    List<JsFeatures> serviceFeatures = const <JsFeatures>[],
    List<JsFeatures> uiFeatures = const <JsFeatures>[],
    QuickjsExtensionOptionalCapabilities? optionalCapabilities,
    int maxPendingCoreCalls = 64,
    Duration defaultCallTimeout = const Duration(seconds: 30),
    QuickjsExtensionRuntimeFactory? runtimeFactory,
  }) {
    final session = QuickjsExtensionSession(
      extension: extension,
      storage: storage,
      grantedPermissions: grantedPermissions,
      sharedFeatures: sharedFeatures,
      serviceFeatures: serviceFeatures,
      uiFeatures: uiFeatures,
      optionalCapabilities: optionalCapabilities,
      maxPendingCoreCalls: maxPendingCoreCalls,
      defaultCallTimeout: defaultCallTimeout,
      runtimeFactory: runtimeFactory,
    );
    final installed = InstalledQuickjsExtension(
      extension: extension,
      session: session,
    );
    registry.register(installed);
    return installed;
  }
}
