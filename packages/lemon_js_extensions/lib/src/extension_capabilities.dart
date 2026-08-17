import 'package:lemon_js/lemon_js.dart';

import 'extension_storage.dart';

/// 为一个插件创建带独立命名空间的 storage 功能。
typedef JsKvStoreFactory =
    JsFeatures Function(String extensionId, JsKvStore storage);

/// 创建插件独享的 HTTP 会话。
typedef JsExtensionHttpFactory = JsHttpSession Function();

/// 创建插件独享的加密功能集合。
typedef JsExtensionCryptoFactory = JsFeatures Function();

/// 宿主提供给扩展 Core 与 JSUI 的运行时功能集合。
///
/// 它负责提供 storage、network 和 crypto 的具体实现，与 manifest 中声明所需
/// 能力的 `capabilities` 字段相互独立。将 factory 设为 `null` 可关闭对应功能，
/// 也可传入自定义 factory 替换默认实现。
final class JsExtensionFeatures {
  /// Creates the set of host features available to extension runtimes.
  const JsExtensionFeatures({
    this.storageFactory,
    this.httpFactory,
    this.cryptoFactory,
    this.extraCapabilities = const <String, int>{},
  });

  /// Creates the default storage, network, and cryptography feature set.
  factory JsExtensionFeatures.defaults() => JsExtensionFeatures(
    storageFactory: _defaultStorageFeatures,
    httpFactory: JsHttpSession.new,
    cryptoFactory: _defaultCryptoFeatures,
  );

  /// Creates a feature set with every built-in capability disabled.
  const JsExtensionFeatures.none()
    : storageFactory = null,
      httpFactory = null,
      cryptoFactory = null,
      extraCapabilities = const <String, int>{};

  /// Creates namespaced storage features for an extension.
  final JsKvStoreFactory? storageFactory;

  /// Creates the HTTP session owned by an extension.
  final JsExtensionHttpFactory? httpFactory;

  /// Creates cryptography features for an extension.
  final JsExtensionCryptoFactory? cryptoFactory;

  /// 除内置 storage、network 和 crypto 外，宿主支持的能力及其版本号。
  ///
  /// 版本号必须大于零；这些条目只参与 manifest 能力检查，不会自动注入实现。
  final Map<String, int> extraCapabilities;

  /// Capability names and versions advertised to manifests.
  Map<String, int> get versions {
    for (final entry in extraCapabilities.entries) {
      if (entry.value < 1) {
        throw ArgumentError.value(
          entry.value,
          'extraCapabilities.${entry.key}',
          'must be positive',
        );
      }
    }
    return Map<String, int>.unmodifiable(<String, int>{
      if (storageFactory != null) 'storage': 1,
      if (httpFactory != null) 'network': 1,
      if (cryptoFactory != null) 'crypto': 1,
      ...extraCapabilities,
    });
  }
}

/// 安装前插件能力与宿主能力的比对结果。
final class JsExtensionCapabilityReport {
  /// Creates a capability compatibility report.
  const JsExtensionCapabilityReport({
    required this.required,
    required this.optional,
    required this.supported,
    required this.missingRequired,
    required this.missingOptional,
  });

  /// Capabilities required by the extension.
  final Map<String, int> required;

  /// Capabilities optionally used by the extension.
  final Map<String, int> optional;

  /// Capabilities and versions supplied by the host.
  final Map<String, int> supported;

  /// Required capabilities unavailable from the host.
  final Map<String, int> missingRequired;

  /// Optional capabilities unavailable from the host.
  final Map<String, int> missingOptional;

  /// Whether every required capability is available.
  bool get canInstall => missingRequired.isEmpty;
}

/// 插件声明的必需能力不受当前宿主支持。
final class JsExtensionCapabilityException implements Exception {
  /// Creates an installation failure for [report].
  const JsExtensionCapabilityException(this.report);

  /// Capability comparison that prevented installation.
  final JsExtensionCapabilityReport report;

  @override
  String toString() =>
      'JS extension requires unavailable capabilities: '
      '${report.missingRequired.entries.map((e) => '${e.key}@${e.value}').join(', ')}';
}

JsFeatures _defaultStorageFeatures(String extensionId, JsKvStore storage) =>
    JsKvStoreFeatures(extensionId: extensionId, storage: storage);

JsFeatures _defaultCryptoFeatures() => WebCryptoFeatures(
  randomUUID: true,
  getRandomValues: true,
  subtleDigest: true,
  subtleHmac: true,
);
