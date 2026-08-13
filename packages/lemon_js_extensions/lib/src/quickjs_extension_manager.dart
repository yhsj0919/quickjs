import 'dart:async';

import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'quickjs_extension.dart';
import 'quickjs_extension_capabilities.dart';
import 'quickjs_extension_compatibility.dart';
import 'quickjs_extension_default_store.dart';
import 'quickjs_extension_manifest.dart';
import 'quickjs_extension_package.dart';
import 'quickjs_extension_package_format.dart';
import 'quickjs_extension_registry.dart';
import 'quickjs_extension_session.dart';
import 'quickjs_extension_storage.dart';

/// 持久化安装项的启用状态。
enum QuickjsExtensionInstallState { enabled, disabled }

/// 可持久化的扩展安装记录。
final class QuickjsExtensionInstallRecord {
  const QuickjsExtensionInstallRecord({
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

  factory QuickjsExtensionInstallRecord.fromMap(Map<String, Object?> map) {
    return QuickjsExtensionInstallRecord(
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
      state: QuickjsExtensionInstallState.values.byName(
        map['state']! as String,
      ),
      grantedPermissions: List<String>.unmodifiable(
        (map['grantedPermissions']! as List).cast<String>(),
      ),
      installedAt: DateTime.parse(map['installedAt']! as String),
      updatedAt: DateTime.parse(map['updatedAt']! as String),
    );
  }

  final String id;
  final String name;
  final String description;
  final String version;
  final int versionCode;
  final int storageVersion;
  final String compatibilityCode;
  final String? icon;
  final Uri? homepage;
  final Uri? updateUrl;
  final Uri? downloadUrl;
  final QuickjsExtensionInstallState state;
  final List<String> grantedPermissions;
  final DateTime installedAt;
  final DateTime updatedAt;

  QuickjsExtensionInstallRecord copyWith({
    String? version,
    int? versionCode,
    int? storageVersion,
    QuickjsExtensionInstallState? state,
    List<String>? grantedPermissions,
    DateTime? updatedAt,
  }) => QuickjsExtensionInstallRecord(
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
final class StoredQuickjsExtension {
  const StoredQuickjsExtension({required this.record, required this.package});

  factory StoredQuickjsExtension.fromMap(Map<String, Object?> map) =>
      StoredQuickjsExtension(
        record: QuickjsExtensionInstallRecord.fromMap(
          Map<String, Object?>.from(map['record']! as Map),
        ),
        package: QuickjsExtensionPackage.fromMap(
          Map<String, Object?>.from(map['package']! as Map),
        ),
      );

  final QuickjsExtensionInstallRecord record;
  final QuickjsExtensionPackage package;

  Map<String, Object?> toMap() => <String, Object?>{
    'record': record.toMap(),
    'package': package.toMap(),
  };
}

/// 安装记录和插件包的持久化接口。
abstract interface class QuickjsExtensionStore {
  Future<List<StoredQuickjsExtension>> loadAll();

  Future<StoredQuickjsExtension?> load(String id);

  Future<void> save(StoredQuickjsExtension extension);

  Future<void> remove(String id);
}

/// 适合测试或单次进程使用的内存 Store。
final class InMemoryQuickjsExtensionStore implements QuickjsExtensionStore {
  final Map<String, StoredQuickjsExtension> _entries =
      <String, StoredQuickjsExtension>{};

  @override
  Future<List<StoredQuickjsExtension>> loadAll() async =>
      List<StoredQuickjsExtension>.unmodifiable(_entries.values);

  @override
  Future<StoredQuickjsExtension?> load(String id) async => _entries[id];

  @override
  Future<void> save(StoredQuickjsExtension extension) async {
    _entries[extension.record.id] = extension;
  }

  @override
  Future<void> remove(String id) async {
    _entries.remove(id);
  }
}

/// 恢复扩展时重新提供无法序列化的第三方 JSUI 插件。
typedef QuickjsExtensionUiPluginsResolver =
    FutureOr<List<QuickjsUiPlugin>> Function(String extensionId);

/// 管理器对外展示的插件状态。
enum ManagedQuickjsExtensionState { enabled, disabled, broken }

/// 一个已管理或恢复失败的插件条目。
final class ManagedQuickjsExtension {
  const ManagedQuickjsExtension({
    required this.record,
    required this.state,
    this.installed,
    this.capabilityInspection,
    this.error,
  });

  final QuickjsExtensionInstallRecord record;
  final ManagedQuickjsExtensionState state;
  final InstalledQuickjsExtension? installed;
  final QuickjsExtensionCapabilityInspection? capabilityInspection;
  final Object? error;

  String get id => record.id;
  String get version => record.version;
  int get versionCode => record.versionCode;
}

/// 统一管理扩展安装、恢复、更新、调用和卸载。
final class QuickjsExtensionManager {
  QuickjsExtensionManager({
    QuickjsExtensionStore? store,
    required this.compatibilityRegistry,
    QuickjsExtensionRegistry? registry,
    QuickjsExtensionStorage? storage,
    this.maxPendingCoreCalls = 64,
    this.defaultCallTimeout = const Duration(seconds: 30),
    QuickjsExtensionOptionalCapabilities? optionalCapabilities,
    this.uiPluginsResolver,
    this.runtimeFactory,
  }) : store = store ?? QuickjsExtensionDefaultStore(),
       optionalCapabilities =
           optionalCapabilities ??
           QuickjsExtensionOptionalCapabilities.defaults(),
       registry = registry ?? QuickjsExtensionRegistry(),
       storage = storage ?? SharedPreferencesJsKvStore() {
    if (maxPendingCoreCalls < 1 || defaultCallTimeout <= Duration.zero) {
      throw ArgumentError(
        'Extension call queue limit and default timeout must be positive',
      );
    }
    _installer = QuickjsExtensionInstaller(
      registry: this.registry,
      storage: this.storage,
    );
  }

  final QuickjsExtensionStore store;
  final QuickjsExtensionCompatibilityRegistry compatibilityRegistry;
  final QuickjsExtensionRegistry registry;
  final QuickjsExtensionStorage storage;
  final int maxPendingCoreCalls;
  final Duration defaultCallTimeout;
  final QuickjsExtensionOptionalCapabilities optionalCapabilities;
  final QuickjsExtensionUiPluginsResolver? uiPluginsResolver;
  final QuickjsExtensionRuntimeFactory? runtimeFactory;
  late final QuickjsExtensionInstaller _installer;
  final Map<String, ManagedQuickjsExtension> _managed =
      <String, ManagedQuickjsExtension>{};

  List<ManagedQuickjsExtension> get extensions =>
      List<ManagedQuickjsExtension>.unmodifiable(_managed.values);

  ManagedQuickjsExtension? find(String id) => _managed[id];

  Iterable<ManagedQuickjsExtension> servicesForContract(String contract) =>
      _managed.values.where(
        (item) =>
            item.state == ManagedQuickjsExtensionState.enabled &&
            item.installed?.extension.service?.contract == contract,
      );

  bool supports(String pluginId, String method) {
    final item = _managed[pluginId];
    return item != null &&
        item.state == ManagedQuickjsExtensionState.enabled &&
        (item.installed?.extension.service?.publicExports.contains(method) ??
            false);
  }

  Iterable<ManagedQuickjsExtension> servicesForMethod(
    String contract,
    String method,
  ) => servicesForContract(contract).where((item) => supports(item.id, method));

  QuickjsExtensionFlowReference? findFlow(String pluginId, String flowId) =>
      registry.findFlow(pluginId, flowId);

  /// 解析安装包并报告其能力在当前宿主中的可用性，不写入安装状态。
  Future<QuickjsExtensionCapabilityInspection> inspectPackage(
    QuickjsExtensionPackage package,
  ) async {
    final extension = await QuickjsExtension.load(package);
    compatibilityRegistry.validate(extension.manifest);
    return _inspectCapabilities(extension.manifest.capabilities);
  }

  Future<void> restore() async {
    for (final current in _managed.values.toList()) {
      if (current.installed != null) await registry.uninstall(current.id);
    }
    _managed.clear();
    for (final stored in await store.loadAll()) {
      await _restoreOne(stored);
    }
  }

  Future<ManagedQuickjsExtension> install(
    QuickjsExtensionPackage package, {
    Iterable<String> grantedPermissions = const <String>[],
  }) async {
    final extension = await QuickjsExtension.load(package);
    compatibilityRegistry.validate(extension.manifest);
    _requireCapabilities(extension.manifest.capabilities);
    if (_managed.containsKey(extension.id) ||
        registry.find(extension.id) != null ||
        await store.load(extension.id) != null) {
      throw StateError('Extension is already installed: ${extension.id}');
    }
    final now = DateTime.now().toUtc();
    final record = QuickjsExtensionInstallRecord(
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
      state: QuickjsExtensionInstallState.enabled,
      grantedPermissions: grantedPermissions.toSet().toList(growable: false),
      installedAt: now,
      updatedAt: now,
    );
    final stored = StoredQuickjsExtension(record: record, package: package);
    await store.save(stored);
    try {
      return await _activate(stored, extension);
    } catch (_) {
      await store.remove(extension.id);
      rethrow;
    }
  }

  Future<ManagedQuickjsExtension> installAsset({
    required String manifestAsset,
    AssetBundle? bundle,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.asset(
      manifestAsset: manifestAsset,
      bundle: bundle,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installFile({
    required String manifestPath,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.file(
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installNetwork({
    required Uri manifestUrl,
    http.Client? client,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.network(
      manifestUrl: manifestUrl,
      client: client,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installAssetZip({
    required String assetKey,
    AssetBundle? bundle,
    String? manifestPath,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.formattedAssetZip(
      assetKey: assetKey,
      bundle: bundle,
      format: format,
      coreAdapter: coreAdapter,
      uiAdapter: uiAdapter,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installFileZip({
    required String path,
    String? manifestPath,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.formattedFileZip(
      path: path,
      format: format,
      coreAdapter: coreAdapter,
      uiAdapter: uiAdapter,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installNetworkZip({
    required Uri url,
    http.Client? client,
    String? manifestPath,
    QuickjsExtensionPackageFormat format =
        QuickjsExtensionPackageFormat.extension,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(
    await QuickjsExtensionPackage.formattedNetworkZip(
      url: url,
      client: client,
      format: format,
      coreAdapter: coreAdapter,
      uiAdapter: uiAdapter,
      manifestPath: manifestPath,
      uiPlugins: uiPlugins,
    ),
    grantedPermissions: grantedPermissions,
  );

  Future<ManagedQuickjsExtension> installAssetEntry({
    required String entryAsset,
    required QuickjsExtensionPackageFormat format,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    AssetBundle? bundle,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(switch (format) {
    QuickjsExtensionPackageFormat.extension => throw ArgumentError(
      'Extension format requires a manifest; use installAsset',
    ),
    QuickjsExtensionPackageFormat.core =>
      await QuickjsExtensionPackage.coreAsset(
        entryAsset: entryAsset,
        adapter: coreAdapter ?? (throw ArgumentError.notNull('coreAdapter')),
        bundle: bundle,
      ),
    QuickjsExtensionPackageFormat.ui => await QuickjsExtensionPackage.uiAsset(
      entryAsset: entryAsset,
      adapter: uiAdapter ?? (throw ArgumentError.notNull('uiAdapter')),
      bundle: bundle,
      uiPlugins: uiPlugins,
    ),
  }, grantedPermissions: grantedPermissions);

  Future<ManagedQuickjsExtension> installFileEntry({
    required String entryPath,
    required QuickjsExtensionPackageFormat format,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(switch (format) {
    QuickjsExtensionPackageFormat.extension => throw ArgumentError(
      'Extension format requires a manifest; use installFile',
    ),
    QuickjsExtensionPackageFormat.core =>
      await QuickjsExtensionPackage.coreFile(
        entryPath: entryPath,
        adapter: coreAdapter ?? (throw ArgumentError.notNull('coreAdapter')),
      ),
    QuickjsExtensionPackageFormat.ui => await QuickjsExtensionPackage.uiFile(
      entryPath: entryPath,
      adapter: uiAdapter ?? (throw ArgumentError.notNull('uiAdapter')),
      uiPlugins: uiPlugins,
    ),
  }, grantedPermissions: grantedPermissions);

  Future<ManagedQuickjsExtension> installNetworkEntry({
    required Uri entryUrl,
    required QuickjsExtensionPackageFormat format,
    QuickjsCorePackageAdapter? coreAdapter,
    QuickjsUiPackageAdapter? uiAdapter,
    http.Client? client,
    Iterable<String> grantedPermissions = const <String>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) async => install(switch (format) {
    QuickjsExtensionPackageFormat.extension => throw ArgumentError(
      'Extension format requires a manifest; use installNetwork',
    ),
    QuickjsExtensionPackageFormat.core =>
      await QuickjsExtensionPackage.coreNetwork(
        entryUrl: entryUrl,
        adapter: coreAdapter ?? (throw ArgumentError.notNull('coreAdapter')),
        client: client,
      ),
    QuickjsExtensionPackageFormat.ui => await QuickjsExtensionPackage.uiNetwork(
      entryUrl: entryUrl,
      adapter: uiAdapter ?? (throw ArgumentError.notNull('uiAdapter')),
      client: client,
      uiPlugins: uiPlugins,
    ),
  }, grantedPermissions: grantedPermissions);

  Future<ManagedQuickjsExtension> update(
    String id,
    QuickjsExtensionPackage package, {
    Iterable<String>? grantedPermissions,
    bool allowDowngrade = false,
    bool allowSameVersion = false,
  }) async {
    final previous = await store.load(id);
    if (previous == null || !_managed.containsKey(id)) {
      throw StateError('Extension is not installed: $id');
    }
    final extension = await QuickjsExtension.load(package);
    compatibilityRegistry.validate(extension.manifest);
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
    final replacement = StoredQuickjsExtension(
      record: record,
      package: package,
    );
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

  Future<void> disable(String id) async {
    final stored = await _requireStored(id);
    await registry.disable(id);
    final record = stored.record.copyWith(
      state: QuickjsExtensionInstallState.disabled,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await store.save(
        StoredQuickjsExtension(record: record, package: stored.package),
      );
    } catch (_) {
      registry.enable(id);
      rethrow;
    }
    _managed[id] = ManagedQuickjsExtension(
      record: record,
      state: ManagedQuickjsExtensionState.disabled,
      installed: registry.find(id),
    );
  }

  Future<void> enable(String id) async {
    final stored = await _requireStored(id);
    final current = _managed[id];
    if (current?.state == ManagedQuickjsExtensionState.broken) {
      final enabled = stored.copyWithState(
        QuickjsExtensionInstallState.enabled,
      );
      await store.save(enabled);
      await _restoreOne(enabled);
      return;
    }
    registry.enable(id);
    final record = stored.record.copyWith(
      state: QuickjsExtensionInstallState.enabled,
      updatedAt: DateTime.now().toUtc(),
    );
    try {
      await store.save(
        StoredQuickjsExtension(record: record, package: stored.package),
      );
    } catch (_) {
      await registry.disable(id);
      rethrow;
    }
    _managed[id] = ManagedQuickjsExtension(
      record: record,
      state: ManagedQuickjsExtensionState.enabled,
      installed: registry.find(id),
    );
  }

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

  Future<void> dispose() async {
    for (final item in _managed.values.toList()) {
      if (item.installed != null) await registry.uninstall(item.id);
    }
    _managed.clear();
  }

  /// 重建指定插件的 Core Runtime；内存状态会丢失，且不会自动重放业务调用。
  Future<void> restartRuntime(String pluginId) =>
      _requireEnabled(pluginId).session.restart();

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

  InstalledQuickjsExtension _requireEnabled(String pluginId) {
    final managed = _managed[pluginId];
    if (managed == null) {
      throw StateError('Extension is not installed: $pluginId');
    }
    if (managed.state != ManagedQuickjsExtensionState.enabled ||
        managed.installed == null) {
      throw StateError('Extension is not enabled: $pluginId');
    }
    return managed.installed!;
  }

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

  Future<void> _restoreOne(StoredQuickjsExtension stored) async {
    try {
      final plugins = await uiPluginsResolver?.call(stored.record.id);
      final package = plugins == null
          ? stored.package
          : stored.package.copyWithUiPlugins(plugins);
      final normalized = StoredQuickjsExtension(
        record: stored.record,
        package: package,
      );
      final extension = await QuickjsExtension.load(package);
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
      compatibilityRegistry.validate(extension.manifest);
      _requireCapabilities(extension.manifest.capabilities);
      await _activate(normalized, extension);
    } catch (error) {
      _managed[stored.record.id] = ManagedQuickjsExtension(
        record: stored.record,
        state: ManagedQuickjsExtensionState.broken,
        error: error,
      );
    }
  }

  Future<ManagedQuickjsExtension> _activate(
    StoredQuickjsExtension stored,
    QuickjsExtension extension,
  ) async {
    final installed = _installer.install(
      extension,
      grantedPermissions: stored.record.grantedPermissions,
      maxPendingCoreCalls: maxPendingCoreCalls,
      defaultCallTimeout: defaultCallTimeout,
      optionalCapabilities: optionalCapabilities,
      runtimeFactory: runtimeFactory,
    );
    if (stored.record.state == QuickjsExtensionInstallState.disabled) {
      await registry.disable(extension.id);
    }
    final managed = ManagedQuickjsExtension(
      record: stored.record,
      state: stored.record.state == QuickjsExtensionInstallState.enabled
          ? ManagedQuickjsExtensionState.enabled
          : ManagedQuickjsExtensionState.disabled,
      installed: installed,
      capabilityInspection: _inspectCapabilities(
        extension.manifest.capabilities,
      ),
    );
    _managed[extension.id] = managed;
    return managed;
  }

  Future<StoredQuickjsExtension> _requireStored(String id) async {
    final stored = await store.load(id);
    if (stored == null) throw StateError('Extension is not installed: $id');
    return stored;
  }

  QuickjsExtensionCapabilityInspection _inspectCapabilities(
    QuickjsExtensionCapabilityManifest declaration,
  ) {
    final supported = optionalCapabilities.versions;
    Map<String, int> missing(Map<String, int> requested) => Map.unmodifiable({
      for (final entry in requested.entries)
        if ((supported[entry.key] ?? 0) < entry.value) entry.key: entry.value,
    });
    return QuickjsExtensionCapabilityInspection(
      required: declaration.required,
      optional: declaration.optional,
      supported: supported,
      missingRequired: missing(declaration.required),
      missingOptional: missing(declaration.optional),
    );
  }

  void _requireCapabilities(QuickjsExtensionCapabilityManifest declaration) {
    final inspection = _inspectCapabilities(declaration);
    if (!inspection.canInstall) {
      throw QuickjsExtensionCapabilityException(inspection);
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
    QuickjsExtension extension, {
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
    final session = QuickjsExtensionSession(
      extension: extension,
      storage: storage,
      grantedPermissions: grantedPermissions,
      optionalCapabilities: optionalCapabilities,
      maxPendingCoreCalls: maxPendingCoreCalls,
      defaultCallTimeout: defaultCallTimeout,
      runtimeFactory: runtimeFactory,
    );
    try {
      await session.migrateStorage(fromVersion, toVersion);
    } finally {
      await session.dispose();
    }
  }
}

extension on StoredQuickjsExtension {
  StoredQuickjsExtension copyWithState(QuickjsExtensionInstallState state) =>
      StoredQuickjsExtension(
        record: record.copyWith(
          state: state,
          updatedAt: DateTime.now().toUtc(),
        ),
        package: package,
      );
}

Uri? _recordUri(Object? value) =>
    value == null ? null : Uri.parse(value as String);
