import 'dart:async';

import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'extension.dart';
import 'extension_capabilities.dart';
import 'extension_compatibility.dart';
import 'extension_default_store.dart';
import 'extension_manifest.dart';
import 'extension_package.dart';
import 'extension_registry.dart';
import 'extension_session.dart';

/// 持久化安装项的启用状态。
enum JsExtensionInstallState {
  /// The extension is active and may be called.
  enabled,

  /// The extension remains installed but cannot be called.
  disabled,
}

/// 可持久化的扩展安装记录。
final class JsExtensionInstallRecord {
  /// Creates a persistent installation record.
  const JsExtensionInstallRecord({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.versionCode,
    this.storageVersion = 0,
    required this.compatibilityCode,
    this.icon,
    this.homepage,
    this.updateUrl,
    this.downloadUrl,
    required this.state,
    required this.grantedPermissions,
    required this.installedAt,
    required this.updatedAt,
  });

  /// Restores an installation record from a persisted map.
  factory JsExtensionInstallRecord.fromMap(Map<String, Object?> map) {
    return JsExtensionInstallRecord(
      id: map['id']! as String,
      name: map['name']! as String,
      description: map['description']! as String,
      version: map['version']! as String,
      versionCode: map['versionCode']! as int,
      storageVersion: (map['storageVersion'] as int?) ?? 0,
      compatibilityCode: map['compatibilityCode']! as String,
      icon: map['icon'] as String?,
      homepage: _recordUri(map['homepage']),
      updateUrl: _recordUri(map['updateUrl']),
      downloadUrl: _recordUri(map['downloadUrl']),
      state: JsExtensionInstallState.values.byName(map['state']! as String),
      grantedPermissions: List<String>.unmodifiable(
        (map['grantedPermissions']! as List).cast<String>(),
      ),
      installedAt: DateTime.parse(map['installedAt']! as String),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
    );
  }

  /// Stable extension identifier.
  final String id;

  /// User-visible extension name captured at installation time.
  final String name;

  /// User-visible description captured at installation time.
  final String description;

  /// Installed user-visible version string.
  final String version;

  /// Installed monotonic version code.
  final int versionCode;

  /// Installed persistent-storage schema version.
  final int storageVersion;

  /// Host compatibility contract identifier.
  final String compatibilityCode;

  /// Package-relative icon path or absolute HTTPS URL.
  final String? icon;

  /// Extension homepage.
  final Uri? homepage;

  /// Endpoint used to check for updates.
  final Uri? updateUrl;

  /// Endpoint used to download updates.
  final Uri? downloadUrl;

  /// Persisted enabled or disabled state.
  final JsExtensionInstallState state;

  /// Permissions granted by the host.
  final List<String> grantedPermissions;

  /// UTC time at which the extension was first installed.
  final DateTime installedAt;

  /// UTC time at which the installation record last changed.
  final DateTime updatedAt;

  /// Returns a record with the supplied mutable installation fields replaced.
  JsExtensionInstallRecord copyWith({
    String? version,
    int? versionCode,
    int? storageVersion,
    JsExtensionInstallState? state,
    List<String>? grantedPermissions,
    DateTime? updatedAt,
  }) => JsExtensionInstallRecord(
    id: id,
    name: name,
    description: description,
    version: version ?? this.version,
    versionCode: versionCode ?? this.versionCode,
    storageVersion: storageVersion ?? this.storageVersion,
    compatibilityCode: compatibilityCode,
    icon: icon,
    homepage: homepage,
    updateUrl: updateUrl,
    downloadUrl: downloadUrl,
    state: state ?? this.state,
    grantedPermissions: List<String>.unmodifiable(
      grantedPermissions ?? this.grantedPermissions,
    ),
    installedAt: installedAt,
    updatedAt: updatedAt ?? this.updatedAt,
  );

  /// Converts this record to a persistable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'id': id,
    'name': name,
    'description': description,
    'version': version,
    'versionCode': versionCode,
    if (storageVersion != 0) 'storageVersion': storageVersion,
    'compatibilityCode': compatibilityCode,
    if (icon != null) 'icon': icon,
    if (homepage != null) 'homepage': homepage.toString(),
    if (updateUrl != null) 'updateUrl': updateUrl.toString(),
    if (downloadUrl != null) 'downloadUrl': downloadUrl.toString(),
    'state': state.name,
    'grantedPermissions': grantedPermissions,
    'installedAt': installedAt.toUtc().toIso8601String(),
    'updatedAt': updatedAt.toUtc().toIso8601String(),
  };
}

/// Store 中保存的安装记录与可恢复包。
final class JsExtensionStoreEntry {
  /// Combines a persistent [record] with its recoverable [package].
  const JsExtensionStoreEntry({required this.record, required this.package});

  /// Restores a stored extension from a persisted map.
  factory JsExtensionStoreEntry.fromMap(Map<String, Object?> map) =>
      JsExtensionStoreEntry(
        record: JsExtensionInstallRecord.fromMap(
          Map<String, Object?>.from(map['record']! as Map),
        ),
        package: JsExtensionPackage.fromMap(
          Map<String, Object?>.from(map['package']! as Map),
        ),
      );

  /// Persistent installation metadata.
  final JsExtensionInstallRecord record;

  /// Recoverable extension package descriptor.
  final JsExtensionPackage package;

  /// Converts this stored extension to a persistable map.
  Map<String, Object?> toMap() => <String, Object?>{
    'record': record.toMap(),
    'package': package.toMap(),
  };
}

/// 安装记录和插件包的持久化接口。
abstract interface class JsExtensionStore {
  /// Loads every persisted extension.
  Future<List<JsExtensionStoreEntry>> loadAll();

  /// Loads the extension identified by [id], or `null` when absent.
  Future<JsExtensionStoreEntry?> load(String id);

  /// Creates or replaces a persisted [extension].
  Future<void> save(JsExtensionStoreEntry extension);

  /// Removes the persisted extension identified by [id].
  Future<void> remove(String id);
}

/// 适合测试或单次进程使用的内存 Store。
final class JsExtensionMemoryStore implements JsExtensionStore {
  final Map<String, JsExtensionStoreEntry> _entries =
      <String, JsExtensionStoreEntry>{};

  @override
  Future<List<JsExtensionStoreEntry>> loadAll() async =>
      List<JsExtensionStoreEntry>.unmodifiable(_entries.values);

  @override
  Future<JsExtensionStoreEntry?> load(String id) async => _entries[id];

  @override
  Future<void> save(JsExtensionStoreEntry extension) async {
    _entries[extension.record.id] = extension;
  }

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
  }
}

/// 恢复扩展时重新提供无法序列化的第三方 JSUI 插件。
typedef JsExtensionUiPluginsResolver =
    FutureOr<List<JsUiPlugin>> Function(String extensionId);

/// 管理器对外展示的插件状态。
enum JsExtensionManagerState {
  /// The extension is installed, active, and callable.
  enabled,

  /// The extension is installed but inactive.
  disabled,

  /// The persisted extension could not be restored.
  broken,
}

/// 一个已管理或恢复失败的插件条目。
final class JsExtensionManagerEntry {
  /// Creates a manager-visible extension snapshot.
  const JsExtensionManagerEntry({
    required this.record,
    required this.state,
    this.installed,
    this.capabilityReport,
    this.error,
  });

  /// Persistent installation record.
  final JsExtensionInstallRecord record;

  /// Current manager state.
  final JsExtensionManagerState state;

  /// Active installation, absent for broken restored entries.
  final JsExtensionInstallation? installed;

  /// Capability availability reported during restore.
  final JsExtensionCapabilityReport? capabilityReport;

  /// Error that prevented restoration, when [state] is [JsExtensionManagerState.broken].
  final Object? error;

  /// Stable extension identifier.
  String get id => record.id;

  /// Installed user-visible version string.
  String get version => record.version;

  /// Installed monotonic version code.
  int get versionCode => record.versionCode;
}

/// 统一管理扩展安装、恢复、更新、调用和卸载。
final class JsExtensionManager {
  /// 创建扩展管理器。
  ///
  /// [constraints] 定义宿主接受的扩展兼容码及公共方法范围。安装、更新和恢复时
  /// 都会执行同一组约束；传入空集合表示宿主不接受任何扩展兼容码。
  /// [features] 提供注入扩展运行时的 storage、network 和 crypto 功能；未传入
  /// 时使用默认实现，可通过 [JsExtensionFeatures.none] 全部关闭。
  /// [maxPendingTasks] 和 [callTimeout] 会应用到 Manager 创建的每个扩展
  /// Session，分别限制等待任务数量和单次调用的默认执行时间。
  JsExtensionManager({
    JsExtensionStore? store,
    required Iterable<JsExtensionConstraint> constraints,
    JsExtensionRegistry? registry,
    JsKvStore? storage,
    this.maxPendingTasks = 64,
    this.callTimeout = const Duration(seconds: 30),
    JsExtensionFeatures? features,
    this.uiPluginsResolver,
    this.runtimeFactory,
  }) : store = store ?? JsExtensionDefaultStore(),
       constraints = JsExtensionConstraints(constraints),
       features = features ?? JsExtensionFeatures.defaults(),
       registry = registry ?? JsExtensionRegistry(),
       storage = storage ?? JsSharedPreferencesKvStore() {
    if (maxPendingTasks < 1 || callTimeout <= Duration.zero) {
      throw ArgumentError(
        'Extension maxPendingTasks and callTimeout must be positive',
      );
    }
    _installer = JsExtensionInstaller(
      registry: this.registry,
      storage: this.storage,
    );
  }

  /// Persistent store used for installation records and recoverable packages.
  final JsExtensionStore store;

  /// 安装、更新和恢复扩展时使用的宿主接口约束集合。
  final JsExtensionConstraints constraints;

  /// Registry that owns active extension sessions.
  final JsExtensionRegistry registry;

  /// Namespaced key-value storage shared by installed extensions.
  final JsKvStore storage;

  /// 每个扩展 Core service 执行队列允许等待的最大任务数。
  final int maxPendingTasks;

  /// 每个扩展 Core service 单次调用的默认超时时间。
  final Duration callTimeout;

  /// 注入每个扩展运行时的宿主功能。
  final JsExtensionFeatures features;

  /// Restores non-serializable JSUI plugins for a persisted extension.
  final JsExtensionUiPluginsResolver? uiPluginsResolver;

  /// Optional factory used to create each extension's Core runtime.
  final JsExtensionRuntimeFactory? runtimeFactory;
  late final JsExtensionInstaller _installer;
  final Map<String, JsExtensionManagerEntry> _managed =
      <String, JsExtensionManagerEntry>{};

  /// Immutable snapshot of all managed extensions.
  List<JsExtensionManagerEntry> get extensions =>
      List<JsExtensionManagerEntry>.unmodifiable(_managed.values);

  /// Finds a managed extension by [id].
  JsExtensionManagerEntry? find(String id) => _managed[id];

  /// Returns enabled services that implement [contract].
  Iterable<JsExtensionManagerEntry> servicesForContract(String contract) =>
      _managed.values.where(
        (item) =>
            item.state == JsExtensionManagerState.enabled &&
            item.installed?.extension.service?.contract == contract,
      );

  /// Whether an enabled extension publicly exposes [method].
  bool supports(String pluginId, String method) {
    final item = _managed[pluginId];
    return item != null &&
        item.state == JsExtensionManagerState.enabled &&
        (item.installed?.extension.service?.publicExports.contains(method) ??
            false);
  }

  /// Returns enabled services that implement [contract] and expose [method].
  Iterable<JsExtensionManagerEntry> servicesForMethod(
    String contract,
    String method,
  ) => servicesForContract(contract).where((item) => supports(item.id, method));

  /// Finds a registered business flow by extension and flow identifier.
  JsExtensionFlowReference? findFlow(String pluginId, String flowId) =>
      registry.findFlow(pluginId, flowId);

  /// 解析安装包并报告其能力在当前宿主中的可用性，不写入安装状态。
  Future<JsExtensionCapabilityReport> inspectPackage(
    JsExtensionPackage package,
  ) async {
    final extension = await JsExtension.load(package);
    constraints.validate(extension.manifest);
    return _inspectCapabilities(extension.manifest.capabilities);
  }

  /// Rebuilds manager state from every extension in [store].
  Future<void> restore() async {
    for (final current in _managed.values.toList()) {
      if (current.installed != null) await registry.uninstall(current.id);
    }
    _managed.clear();
    for (final stored in await store.loadAll()) {
      await _restoreOne(stored);
    }
  }

  /// Installs, persists, and activates [package].
  Future<JsExtensionManagerEntry> install(
    JsExtensionPackage package, {
    Iterable<String> grantedPermissions = const <String>[],
  }) async {
    final extension = await JsExtension.load(package);
    constraints.validate(extension.manifest);
    _requireCapabilities(extension.manifest.capabilities);
    if (_managed.containsKey(extension.id) ||
        registry.find(extension.id) != null ||
        await store.load(extension.id) != null) {
      throw StateError('Extension is already installed: ${extension.id}');
    }
    final now = DateTime.now().toUtc();
    final record = JsExtensionInstallRecord(
      id: extension.id,
      name: extension.manifest.name,
      description: extension.manifest.description,
      version: extension.version,
      versionCode: extension.manifest.versionCode,
      storageVersion: extension.manifest.storageVersion,
      compatibilityCode: extension.manifest.compatibilityCode,
      icon: extension.manifest.icon,
      homepage: extension.manifest.homepage,
      updateUrl: extension.manifest.updateUrl,
      downloadUrl: extension.manifest.downloadUrl,
      state: JsExtensionInstallState.enabled,
      grantedPermissions: grantedPermissions.toSet().toList(growable: false),
      installedAt: now,
      updatedAt: now,
    );
    final stored = JsExtensionStoreEntry(record: record, package: package);
    await store.save(stored);
    try {
      return await _activate(stored, extension);
    } catch (_) {
      await store.remove(extension.id);
      rethrow;
    }
  }

  /// Replaces an installed extension with [package].
  Future<JsExtensionManagerEntry> update(
    String id,
    JsExtensionPackage package, {
    Iterable<String>? grantedPermissions,
    bool allowDowngrade = false,
    bool allowSameVersion = false,
  }) async {
    final previous = await store.load(id);
    if (previous == null || !_managed.containsKey(id)) {
      throw StateError('Extension is not installed: $id');
    }
    final extension = await JsExtension.load(package);
    constraints.validate(extension.manifest);
    _requireCapabilities(extension.manifest.capabilities);
    if (extension.id != id) {
      throw ArgumentError(
        'Updated extension id does not match: ${extension.id}',
      );
    }
    if (extension.manifest.compatibilityCode !=
        previous.record.compatibilityCode) {
      throw const FormatException(
        'Updated extension compatibilityCode does not match installed record',
      );
    }
    final nextCode = extension.manifest.versionCode;
    final currentCode = previous.record.versionCode;
    if (nextCode < currentCode && !allowDowngrade) {
      throw StateError(
        'Extension downgrade is not allowed: $nextCode < $currentCode',
      );
    }
    if (nextCode == currentCode && !allowSameVersion) {
      throw StateError('Extension versionCode is already installed: $nextCode');
    }
    Map<String, Object?>? storageSnapshot;
    final nextStorageVersion = extension.manifest.storageVersion;
    final currentStorageVersion = previous.record.storageVersion;
    if (nextStorageVersion != currentStorageVersion) {
      storageSnapshot = await _snapshotStorage(id);
      try {
        await _runStorageMigration(
          extension,
          fromVersion: currentStorageVersion,
          toVersion: nextStorageVersion,
          grantedPermissions:
              grantedPermissions ?? previous.record.grantedPermissions,
        );
      } catch (_) {
        await _restoreStorage(id, storageSnapshot);
        rethrow;
      }
    }
    final record = previous.record.copyWith(
      version: extension.version,
      versionCode: extension.manifest.versionCode,
      storageVersion: nextStorageVersion,
      grantedPermissions: grantedPermissions?.toSet().toList(growable: false),
      updatedAt: DateTime.now().toUtc(),
    );
    final replacement = JsExtensionStoreEntry(record: record, package: package);
    try {
      await store.save(replacement);
      await registry.uninstall(id);
      return await _activate(replacement, extension);
    } catch (_) {
      await store.save(previous);
      if (storageSnapshot != null) {
        await _restoreStorage(id, storageSnapshot);
      }
      if (registry.find(id) == null) {
        await _restoreOne(previous);
      }
      rethrow;
    }
  }

  /// Disables the installed extension identified by [id].
  Future<void> disable(String id) async {
    final stored = await _requireStored(id);
    await registry.disable(id);
    final record = stored.record.copyWith(
      state: JsExtensionInstallState.disabled,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await store.save(
        JsExtensionStoreEntry(record: record, package: stored.package),
      );
    } catch (_) {
      registry.enable(id);
      rethrow;
    }
    _managed[id] = JsExtensionManagerEntry(
      record: record,
      state: JsExtensionManagerState.disabled,
      installed: registry.find(id),
    );
  }

  /// Enables the installed extension identified by [id].
  Future<void> enable(String id) async {
    final stored = await _requireStored(id);
    final current = _managed[id];
    if (current?.state == JsExtensionManagerState.broken) {
      final enabled = stored.copyWithState(JsExtensionInstallState.enabled);
      await store.save(enabled);
      await _restoreOne(enabled);
      return;
    }
    registry.enable(id);
    final record = stored.record.copyWith(
      state: JsExtensionInstallState.enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await store.save(
        JsExtensionStoreEntry(record: record, package: stored.package),
      );
    } catch (_) {
      await registry.disable(id);
      rethrow;
    }
    _managed[id] = JsExtensionManagerEntry(
      record: record,
      state: JsExtensionManagerState.enabled,
      installed: registry.find(id),
    );
  }

  /// Uninstalls [id], optionally deleting its namespaced key-value data.
  Future<void> uninstall(String id, {bool clearStorage = false}) async {
    final stored = await store.load(id);
    if (stored == null) {
      _managed.remove(id);
      await registry.uninstall(id, clearStorage: clearStorage);
      return;
    }
    await store.remove(id);
    try {
      await registry.uninstall(id, clearStorage: clearStorage);
      _managed.remove(id);
    } catch (_) {
      await store.save(stored);
      rethrow;
    }
  }

  /// Releases active sessions without removing persisted installations.
  Future<void> dispose() async {
    for (final item in _managed.values.toList()) {
      if (item.installed != null) await registry.uninstall(item.id);
    }
    _managed.clear();
  }

  /// 重建指定插件的 Core Runtime；内存状态会丢失，且不会自动重放业务调用。
  Future<void> restartRuntime(String pluginId) =>
      _requireEnabled(pluginId).session.restart();

  /// Calls a public [method] on the enabled extension [pluginId].
  Future<Object?> call(
    String pluginId,
    String method, {
    List<Object?> arguments = const <Object?>[],
    Duration? timeout,
  }) {
    return _requireEnabled(
      pluginId,
    ).session.callPublic(method, arguments: arguments, timeout: timeout);
  }

  JsExtensionInstallation _requireEnabled(String pluginId) {
    final managed = _managed[pluginId];
    if (managed == null) {
      throw StateError('Extension is not installed: $pluginId');
    }
    if (managed.state != JsExtensionManagerState.enabled ||
        managed.installed == null) {
      throw StateError('Extension is not enabled: $pluginId');
    }
    return managed.installed!;
  }

  /// Calls [method] on an enabled service implementing [contract].
  Future<Object?> callContract(
    String contract,
    String method, {
    String? pluginId,
    List<Object?> arguments = const <Object?>[],
    Duration? timeout,
  }) {
    final candidates = servicesForContract(contract).toList();
    final selected = pluginId == null
        ? switch (candidates) {
            [final only] => only,
            [] => throw StateError('No enabled extension implements $contract'),
            _ => throw StateError(
              'Multiple extensions implement $contract; pluginId is required',
            ),
          }
        : candidates.where((item) => item.id == pluginId).firstOrNull;
    if (selected == null) {
      throw StateError('Extension $pluginId does not implement $contract');
    }
    return call(selected.id, method, arguments: arguments, timeout: timeout);
  }

  Future<void> _restoreOne(JsExtensionStoreEntry stored) async {
    try {
      final plugins = await uiPluginsResolver?.call(stored.record.id);
      final package = plugins == null
          ? stored.package
          : stored.package.copyWithUiPlugins(plugins);
      final normalized = JsExtensionStoreEntry(
        record: stored.record,
        package: package,
      );
      final extension = await JsExtension.load(package);
      if (extension.id != stored.record.id ||
          extension.version != stored.record.version) {
        throw const FormatException(
          'Stored extension identity does not match its install record',
        );
      }
      if (extension.manifest.versionCode != stored.record.versionCode ||
          extension.manifest.storageVersion != stored.record.storageVersion ||
          extension.manifest.compatibilityCode !=
              stored.record.compatibilityCode) {
        throw const FormatException(
          'Stored extension compatibility does not match its install record',
        );
      }
      constraints.validate(extension.manifest);
      _requireCapabilities(extension.manifest.capabilities);
      await _activate(normalized, extension);
    } catch (error) {
      _managed[stored.record.id] = JsExtensionManagerEntry(
        record: stored.record,
        state: JsExtensionManagerState.broken,
        error: error,
      );
    }
  }

  Future<JsExtensionManagerEntry> _activate(
    JsExtensionStoreEntry stored,
    JsExtension extension,
  ) async {
    final installed = _installer.install(
      extension,
      grantedPermissions: stored.record.grantedPermissions,
      maxPendingTasks: maxPendingTasks,
      callTimeout: callTimeout,
      features: features,
      runtimeFactory: runtimeFactory,
    );
    if (stored.record.state == JsExtensionInstallState.disabled) {
      await registry.disable(extension.id);
    }
    final managed = JsExtensionManagerEntry(
      record: stored.record,
      state: stored.record.state == JsExtensionInstallState.enabled
          ? JsExtensionManagerState.enabled
          : JsExtensionManagerState.disabled,
      installed: installed,
      capabilityReport: _inspectCapabilities(extension.manifest.capabilities),
    );
    _managed[extension.id] = managed;
    return managed;
  }

  Future<JsExtensionStoreEntry> _requireStored(String id) async {
    final stored = await store.load(id);
    if (stored == null) throw StateError('Extension is not installed: $id');
    return stored;
  }

  JsExtensionCapabilityReport _inspectCapabilities(
    JsExtensionCapabilityManifest declaration,
  ) {
    final supported = features.versions;
    Map<String, int> missing(Map<String, int> requested) => Map.unmodifiable({
      for (final entry in requested.entries)
        if ((supported[entry.key] ?? 0) < entry.value) entry.key: entry.value,
    });
    return JsExtensionCapabilityReport(
      required: declaration.required,
      optional: declaration.optional,
      supported: supported,
      missingRequired: missing(declaration.required),
      missingOptional: missing(declaration.optional),
    );
  }

  void _requireCapabilities(JsExtensionCapabilityManifest declaration) {
    final report = _inspectCapabilities(declaration);
    if (!report.canInstall) {
      throw JsExtensionCapabilityException(report);
    }
  }

  Future<Map<String, Object?>> _snapshotStorage(String id) async {
    final snapshot = <String, Object?>{};
    for (final key in await storage.keys(namespace: id)) {
      snapshot[key] = await storage.get(key, namespace: id);
    }
    return snapshot;
  }

  Future<void> _restoreStorage(String id, Map<String, Object?> snapshot) async {
    await storage.clear(namespace: id);
    for (final entry in snapshot.entries) {
      await storage.set(entry.key, entry.value, namespace: id);
    }
  }

  Future<void> _runStorageMigration(
    JsExtension extension, {
    required int fromVersion,
    required int toVersion,
    required Iterable<String> grantedPermissions,
  }) async {
    if (extension.service?.storageMigrationExport == null) {
      throw StateError(
        'Extension ${extension.id} changes storageVersion from $fromVersion '
        'to $toVersion without service.storageMigrationExport',
      );
    }
    final session = JsExtensionSession(
      extension: extension,
      storage: storage,
      grantedPermissions: grantedPermissions,
      features: features,
      maxPendingTasks: maxPendingTasks,
      callTimeout: callTimeout,
      runtimeFactory: runtimeFactory,
    );
    try {
      await session.migrateStorage(fromVersion, toVersion);
    } finally {
      await session.dispose();
    }
  }
}

extension on JsExtensionStoreEntry {
  JsExtensionStoreEntry copyWithState(JsExtensionInstallState state) =>
      JsExtensionStoreEntry(
        record: record.copyWith(
          state: state,
          updatedAt: DateTime.now().toUtc(),
        ),
        package: package,
      );
}

Uri? _recordUri(Object? value) =>
    value == null ? null : Uri.parse(value as String);
