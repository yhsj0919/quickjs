import 'extension_manifest.dart';

/// Manager 输入包采用的解析格式。
///
/// [manifest] 是带统一 `manifest.json` 清单的标准扩展包；[core] 和 [ui]
/// 分别表示需要 adapter 补齐清单信息的旧 Core 与 JSUI 格式。
enum JsExtensionPackageFormat {
  /// A standard package containing a unified extension manifest.
  manifest,

  /// A bare legacy Core module that requires an adapter.
  core,

  /// A bare legacy JSUI module that requires an adapter.
  ui,
}

/// 裸 Core/UI 插件进入统一管理时共用的展示和版本信息。
sealed class JsExtensionAdapter {
  const JsExtensionAdapter({
    required this.id,
    required this.name,
    this.description = '',
    required this.version,
    this.versionCode = 0,
    required this.compatibilityCode,
    this.icon,
    this.homepage,
    this.updateUrl,
    this.downloadUrl,
    this.permissions = const <String>[],
  });

  /// Stable extension identifier.
  final String id;

  /// User-visible extension name.
  final String name;

  /// User-visible extension description.
  final String description;

  /// User-visible version string.
  final String version;

  /// Monotonic version used for update ordering.
  final int versionCode;

  /// Host compatibility contract identifier.
  final String compatibilityCode;

  /// Package-relative icon path or HTTPS URL.
  final String? icon;

  /// Extension homepage.
  final Uri? homepage;

  /// Endpoint used to check for updates.
  final Uri? updateUrl;

  /// Endpoint used to download updates.
  final Uri? downloadUrl;

  /// Permissions requested by the adapted extension.
  final List<String> permissions;

  /// 根据裸插件入口生成统一扩展清单。
  JsExtensionManifest buildManifest(String entry);
}

/// 裸 Core 插件所需的显式统一管理信息。
final class JsExtensionCoreAdapter extends JsExtensionAdapter {
  /// Creates an adapter for a bare Core module.
  const JsExtensionCoreAdapter({
    required super.id,
    required super.name,
    super.description,
    required super.version,
    super.versionCode,
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

  /// Service contract implemented by the module.
  final String contract;

  /// Methods callable by the host application.
  final List<String> publicExports;

  /// Methods callable only by the extension UI.
  final List<String> uiExports;

  @override
  JsExtensionManifest buildManifest(String entry) => JsExtensionManifest(
    id: id,
    name: name,
    description: description,
    version: version,
    versionCode: versionCode,
    compatibilityCode: compatibilityCode,
    icon: icon,
    homepage: homepage,
    updateUrl: updateUrl,
    downloadUrl: downloadUrl,
    permissions: permissions,
    service: JsExtensionServiceManifest(
      entry: entry,
      contract: contract,
      publicExports: publicExports,
      uiExports: uiExports,
    ),
  );
}

/// 裸 JSUI 插件所需的显式统一管理信息。
final class JsExtensionUiAdapter extends JsExtensionAdapter {
  /// Creates an adapter for a bare JSUI module.
  const JsExtensionUiAdapter({
    required super.id,
    required super.name,
    super.description,
    required super.version,
    super.versionCode,
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

  /// Route identifier generated for the module.
  final String route;

  /// Optional user-visible route title.
  final String? title;

  /// Presentation mode for the default entry.
  final String display;

  @override
  JsExtensionManifest buildManifest(String entry) => JsExtensionManifest(
    id: id,
    name: name,
    description: description,
    version: version,
    versionCode: versionCode,
    compatibilityCode: compatibilityCode,
    icon: icon,
    homepage: homepage,
    updateUrl: updateUrl,
    downloadUrl: downloadUrl,
    permissions: permissions,
    entry: JsExtensionEntry(route: route, display: display),
    ui: JsExtensionUiManifest(
      routes: <String, JsExtensionRoute>{
        route: JsExtensionRoute(entry: entry, title: title),
      },
    ),
  );
}
