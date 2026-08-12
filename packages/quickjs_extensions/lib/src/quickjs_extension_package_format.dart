import 'quickjs_extension_manifest.dart';

/// Manager 输入包采用的解析格式。
enum QuickjsExtensionPackageFormat { extension, core, ui }

/// 裸 Core/UI 插件进入统一管理时共用的展示和版本信息。
abstract base class QuickjsExtensionPackageAdapter {
  const QuickjsExtensionPackageAdapter({
    required this.id,
    required this.name,
    required this.description,
    required this.version,
    required this.versionCode,
    required this.compatibilityCode,
    this.icon,
    this.homepage,
    this.updateUrl,
    this.downloadUrl,
    this.permissions = const <String>[],
  });

  final String id;
  final String name;
  final String description;
  final String version;
  final int versionCode;
  final String compatibilityCode;
  final String? icon;
  final Uri? homepage;
  final Uri? updateUrl;
  final Uri? downloadUrl;
  final List<String> permissions;
}

/// 裸 Core 插件所需的显式统一管理信息。
final class QuickjsCorePackageAdapter extends QuickjsExtensionPackageAdapter {
  const QuickjsCorePackageAdapter({
    required super.id,
    required super.name,
    required super.description,
    required super.version,
    required super.versionCode,
    required super.compatibilityCode,
    required this.contract,
    required this.publicExports,
    this.uiExports = const <String>[],
    super.icon,
    super.homepage,
    super.updateUrl,
    super.downloadUrl,
    super.permissions,
  });

  final String contract;
  final List<String> publicExports;
  final List<String> uiExports;
}

/// 裸 JSUI 插件所需的显式统一管理信息。
final class QuickjsUiPackageAdapter extends QuickjsExtensionPackageAdapter {
  const QuickjsUiPackageAdapter({
    required super.id,
    required super.name,
    required super.description,
    required super.version,
    required super.versionCode,
    required super.compatibilityCode,
    this.route = 'main',
    this.title,
    this.display = 'standalone',
    super.icon,
    super.homepage,
    super.updateUrl,
    super.downloadUrl,
    super.permissions,
  });

  final String route;
  final String? title;
  final String display;
}

QuickjsExtensionManifest quickjsCoreAdapterManifest(
  QuickjsCorePackageAdapter adapter,
  String entry,
) => QuickjsExtensionManifest(
  id: adapter.id,
  name: adapter.name,
  description: adapter.description,
  version: adapter.version,
  versionCode: adapter.versionCode,
  compatibilityCode: adapter.compatibilityCode,
  icon: adapter.icon,
  homepage: adapter.homepage,
  updateUrl: adapter.updateUrl,
  downloadUrl: adapter.downloadUrl,
  permissions: adapter.permissions,
  service: QuickjsServiceManifest(
    entry: entry,
    contract: adapter.contract,
    publicExports: adapter.publicExports,
    uiExports: adapter.uiExports,
  ),
);

QuickjsExtensionManifest quickjsUiAdapterManifest(
  QuickjsUiPackageAdapter adapter,
  String entry,
) => QuickjsExtensionManifest(
  id: adapter.id,
  name: adapter.name,
  description: adapter.description,
  version: adapter.version,
  versionCode: adapter.versionCode,
  compatibilityCode: adapter.compatibilityCode,
  icon: adapter.icon,
  homepage: adapter.homepage,
  updateUrl: adapter.updateUrl,
  downloadUrl: adapter.downloadUrl,
  permissions: adapter.permissions,
  entry: QuickjsExtensionEntry(route: adapter.route, display: adapter.display),
  ui: QuickjsUiExtensionManifest(
    routes: <String, QuickjsExtensionRoute>{
      adapter.route: QuickjsExtensionRoute(entry: entry, title: adapter.title),
    },
  ),
);
