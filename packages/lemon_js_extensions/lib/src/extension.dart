import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'extension_manifest.dart';
import 'extension_package.dart';

/// 扩展中包含的能力类型。
enum JsExtensionKind {
  /// 仅包含数据与业务逻辑。
  js,

  /// 仅包含 JSUI 页面。
  ui,

  /// 同时包含 Core 与 JSUI 能力。
  hybrid,
}

/// 扩展的 Core 服务组件。
final class JsExtensionServiceComponent {
  /// 创建并校验服务组件。
  JsExtensionServiceComponent({
    required this.plugin,
    required this.contract,
    required List<String> publicExports,
    List<String> uiExports = const <String>[],
    this.storageMigrationExport,
  }) : publicExports = List<String>.unmodifiable(publicExports),
       uiExports = List<String>.unmodifiable(uiExports) {
    final declared = plugin.manifest.exports.toSet();
    final requiredExports = <String>{
      ...publicExports,
      ...uiExports,
      ?storageMigrationExport,
    };
    final missing = requiredExports.difference(declared);
    if (missing.isNotEmpty) {
      throw ArgumentError(
        'Service exports are missing from JsPlugin manifest: '
        '${missing.join(', ')}',
      );
    }
  }

  /// 承载服务模块的 Lemon JS 插件。
  final JsPlugin plugin;

  /// 服务实现的数据协议名称。
  final String contract;

  /// 允许宿主直接调用的导出方法。
  final List<String> publicExports;

  /// 仅允许同一扩展 UI 调用的导出方法。
  final List<String> uiExports;

  /// 仅供 Manager 在 KV 版本升级时调用的内部导出。
  final String? storageMigrationExport;
}

/// 扩展的 JSUI 页面组件。
final class JsExtensionUiComponent {
  /// 创建并校验 UI 组件。
  JsExtensionUiComponent({
    required this.bundle,
    required Map<String, JsExtensionRoute> routes,
    List<JsUiPlugin> plugins = const <JsUiPlugin>[],
  }) : routes = Map<String, JsExtensionRoute>.unmodifiable(routes),
       plugins = List<JsUiPlugin>.unmodifiable(plugins) {
    if (routes.isEmpty) {
      throw ArgumentError.value(routes, 'routes', 'must not be empty');
    }
    final modules = bundle.modules.keys.toSet();
    for (final entry in routes.entries) {
      if (!modules.contains(entry.value.entry)) {
        throw ArgumentError(
          'UI route "${entry.key}" entry is missing from bundle modules: '
          '${entry.value.entry}',
        );
      }
    }
  }

  /// JSUI 模块包。
  final JsUiBundle bundle;

  /// 以入口名称索引的页面路由。
  final Map<String, JsExtensionRoute> routes;

  /// 页面依赖的第三方 JSUI 插件。
  final List<JsUiPlugin> plugins;
}

/// 将 Core、JSUI 或二者组合为统一安装单元的扩展。
final class JsExtension {
  /// 从内存包解析并构建扩展。
  static Future<JsExtension> load(JsExtensionPackage package) async {
    final manifest = JsExtensionManifest.parse(package.manifestSource);
    final serviceManifest = manifest.service;
    final uiManifest = manifest.ui;
    final service = serviceManifest == null
        ? null
        : JsExtensionServiceComponent(
            plugin: package.buildServicePlugin(manifest),
            contract: serviceManifest.contract,
            publicExports: serviceManifest.publicExports,
            uiExports: serviceManifest.uiExports,
            storageMigrationExport: serviceManifest.storageMigrationExport,
          );
    final ui = uiManifest == null
        ? null
        : JsExtensionUiComponent(
            bundle: package.buildUiBundle(manifest),
            routes: uiManifest.routes,
            plugins: package.uiPlugins,
          );
    return switch ((service, ui)) {
      (final JsExtensionServiceComponent value, null) => JsExtension.js(
        manifest: manifest,
        service: value,
      ),
      (null, final JsExtensionUiComponent value) => JsExtension.ui(
        manifest: manifest,
        ui: value,
      ),
      (
        final JsExtensionServiceComponent core,
        final JsExtensionUiComponent view,
      ) =>
        JsExtension.hybrid(manifest: manifest, service: core, ui: view),
      _ => throw const FormatException(
        'JS extension package does not contain a component',
      ),
    };
  }

  /// 创建仅包含 Core 服务的扩展。
  JsExtension.js({required this.manifest, required this.service}) : ui = null {
    _validate(expectedKind: JsExtensionKind.js);
  }

  /// 创建仅包含 JSUI 页面的扩展。
  JsExtension.ui({required this.manifest, required this.ui}) : service = null {
    _validate(expectedKind: JsExtensionKind.ui);
  }

  /// 创建同时包含 Core 服务和 JSUI 页面的混合扩展。
  JsExtension.hybrid({
    required this.manifest,
    required this.service,
    required this.ui,
  }) {
    _validate(expectedKind: JsExtensionKind.hybrid);
  }

  /// 扩展清单。
  final JsExtensionManifest manifest;

  /// Core 服务组件；纯 UI 扩展中为空。
  final JsExtensionServiceComponent? service;

  /// JSUI 组件；纯 Core 扩展中为空。
  final JsExtensionUiComponent? ui;

  /// 扩展的唯一标识。
  String get id => manifest.id;

  /// 扩展版本。
  String get version => manifest.version;

  /// 根据实际组件得到扩展类型。
  JsExtensionKind get kind => switch ((service, ui)) {
    (final JsExtensionServiceComponent _, null) => JsExtensionKind.js,
    (null, final JsExtensionUiComponent _) => JsExtensionKind.ui,
    (final JsExtensionServiceComponent _, final JsExtensionUiComponent _) =>
      JsExtensionKind.hybrid,
    _ => throw StateError('JS extension has no components'),
  };

  void _validate({required JsExtensionKind expectedKind}) {
    if (kind != expectedKind) {
      throw ArgumentError('JS extension constructor does not match components');
    }
    if ((manifest.service != null) != (service != null) ||
        (manifest.ui != null) != (ui != null)) {
      throw ArgumentError(
        'JS extension components do not match manifest declarations',
      );
    }
    final serviceComponent = service;
    final serviceManifest = manifest.service;
    if (serviceComponent != null && serviceManifest != null) {
      if (serviceComponent.plugin.manifest.id != manifest.id ||
          serviceComponent.plugin.manifest.version != manifest.version) {
        throw ArgumentError(
          'JS service plugin identity must match extension manifest',
        );
      }
      if (serviceComponent.plugin.manifest.entry !=
          '${manifest.id}/${serviceManifest.entry}') {
        throw ArgumentError(
          'JS service plugin entry must match extension manifest',
        );
      }
      if (serviceComponent.contract != serviceManifest.contract ||
          !_sameStrings(
            serviceComponent.publicExports,
            serviceManifest.publicExports,
          ) ||
          !_sameStrings(
            serviceComponent.uiExports,
            serviceManifest.uiExports,
          ) ||
          serviceComponent.storageMigrationExport !=
              serviceManifest.storageMigrationExport) {
        throw ArgumentError(
          'JS service component does not match extension manifest',
        );
      }
    }
    final uiComponent = ui;
    final uiManifest = manifest.ui;
    if (uiComponent != null && uiManifest != null) {
      if (uiComponent.bundle.id != manifest.id ||
          uiComponent.bundle.version != manifest.version) {
        throw ArgumentError(
          'JSUI bundle identity must match extension manifest',
        );
      }
      if (!_sameRoutes(uiComponent.routes, uiManifest.routes)) {
        throw ArgumentError(
          'JSUI component routes do not match extension manifest',
        );
      }
    }
  }
}

bool _sameStrings(List<String> left, List<String> right) =>
    left.length == right.length && left.toSet().containsAll(right);

bool _sameRoutes(
  Map<String, JsExtensionRoute> left,
  Map<String, JsExtensionRoute> right,
) {
  if (left.length != right.length) return false;
  for (final entry in left.entries) {
    final other = right[entry.key];
    if (other == null || other.entry != entry.value.entry) return false;
  }
  return true;
}
