import 'package:lemon_js/lemon_js.dart';

import 'extension.dart';
import 'extension_capabilities.dart';
import 'extension_session.dart';

/// 已安装扩展及其共享 Session。
final class JsExtensionInstallation {
  /// Creates an installed extension backed by its shared [session].
  const JsExtensionInstallation({
    required this.extension,
    required this.session,
  });

  /// Parsed extension package and manifest.
  final JsExtension extension;

  /// Session that owns Core and UI runtime state.
  final JsExtensionSession session;

  /// Stable extension identifier.
  String get id => extension.id;

  /// Whether the session currently accepts calls and UI routes.
  bool get enabled =>
      session.state != JsExtensionSessionState.disabled &&
      session.state != JsExtensionSessionState.disposed;
}

/// 可直接打开的扩展交互流程引用。
final class JsExtensionFlowReference {
  /// Creates a reference to a declared interaction flow.
  const JsExtensionFlowReference({
    required this.installed,
    required this.flowId,
    required this.route,
  });

  /// Installed extension that owns the flow.
  final JsExtensionInstallation installed;

  /// Flow identifier from the extension manifest.
  final String flowId;

  /// JSUI route used to perform the flow.
  final String route;
}

/// 保存并查询当前宿主已安装扩展的内存注册表。
final class JsExtensionRegistry {
  final Map<String, JsExtensionInstallation> _installed =
      <String, JsExtensionInstallation>{};

  /// Enabled extensions currently registered with the host.
  Iterable<JsExtensionInstallation> get installed =>
      _installed.values.where((item) => item.enabled);

  /// Finds an extension by [id], including disabled entries.
  JsExtensionInstallation? find(String id) => _installed[id];

  /// Returns enabled services implementing [contract].
  Iterable<JsExtensionInstallation> servicesForContract(String contract) =>
      installed.where((item) => item.extension.service?.contract == contract);

  /// Finds an enabled extension's declared [flowId].
  JsExtensionFlowReference? findFlow(String extensionId, String flowId) {
    final item = _installed[extensionId];
    if (item == null || !item.enabled) return null;
    final flow = item.extension.manifest.flows[flowId];
    if (flow == null) return null;
    return JsExtensionFlowReference(
      installed: item,
      flowId: flowId,
      route: flow.route,
    );
  }

  /// Registers a newly installed [extension].
  void register(JsExtensionInstallation extension) {
    if (_installed.containsKey(extension.id)) {
      throw StateError('JS extension is already installed: ${extension.id}');
    }
    _installed[extension.id] = extension;
  }

  /// Disables [id] while retaining its session and storage.
  Future<void> disable(String id) async {
    final item = _require(id);
    await item.session.disable();
  }

  /// Enables a previously disabled extension.
  void enable(String id) => _require(id).session.enable();

  /// Unregisters and disposes [id], optionally clearing its storage.
  Future<void> uninstall(String id, {bool clearStorage = false}) async {
    final item = _installed.remove(id);
    if (item == null) return;
    await item.session.dispose(clearStorage: clearStorage);
  }

  JsExtensionInstallation _require(String id) {
    final item = _installed[id];
    if (item == null) {
      throw StateError('JS extension is not installed: $id');
    }
    return item;
  }
}

/// 校验授权并将扩展安装到注册表。
final class JsExtensionInstaller {
  /// Creates a low-level installer for [registry].
  JsExtensionInstaller({required this.registry, JsKvStore? storage})
    : storage = storage ?? JsSharedPreferencesKvStore();

  /// Registry that receives successful installations.
  final JsExtensionRegistry registry;

  /// Key-value store shared through per-extension namespaces.
  final JsKvStore storage;

  /// Validates, creates, and registers a session for [extension].
  JsExtensionInstallation install(
    JsExtension extension, {
    Iterable<String> grantedPermissions = const <String>[],
    List<JsFeatures> sharedFeatures = const <JsFeatures>[],
    List<JsFeatures> serviceFeatures = const <JsFeatures>[],
    List<JsFeatures> uiFeatures = const <JsFeatures>[],
    JsExtensionFeatures? features,
    int maxPendingTasks = 64,
    Duration callTimeout = const Duration(seconds: 30),
    JsExtensionRuntimeFactory? runtimeFactory,
  }) {
    final session = JsExtensionSession(
      extension: extension,
      storage: storage,
      grantedPermissions: grantedPermissions,
      sharedFeatures: sharedFeatures,
      serviceFeatures: serviceFeatures,
      uiFeatures: uiFeatures,
      features: features,
      maxPendingTasks: maxPendingTasks,
      callTimeout: callTimeout,
      runtimeFactory: runtimeFactory,
    );
    final installed = JsExtensionInstallation(
      extension: extension,
      session: session,
    );
    registry.register(installed);
    return installed;
  }
}
