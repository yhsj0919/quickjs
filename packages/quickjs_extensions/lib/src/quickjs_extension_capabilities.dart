import 'package:lemon_js/lemon_js.dart';

import 'quickjs_extension_storage.dart';

typedef QuickjsExtensionStorageMountFactory =
    QuickjsHostMount Function(
      String extensionId,
      QuickjsExtensionStorage storage,
    );
typedef QuickjsExtensionHttpSessionFactory = QuickjsHttpSession Function();
typedef QuickjsExtensionCryptoMountFactory = QuickjsHostMount Function();

const quickjsExtensionAxiosAsset =
    'packages/quickjs_extensions/assets/js/axios.js';

/// 混合插件层提供给 Core 与 JSUI 的可选宿主能力集合。
///
/// 它与 manifest 权限声明相互独立。将某个 factory 设为 `null` 即可关闭对应能力，
/// 也可以传入 factory 替换默认实现。
final class QuickjsExtensionOptionalCapabilities {
  const QuickjsExtensionOptionalCapabilities({
    this.storageMountFactory,
    this.httpSessionFactory,
    this.cryptoMountFactory,
    this.additionalVersions = const <String, int>{},
  });

  factory QuickjsExtensionOptionalCapabilities.defaults() =>
      QuickjsExtensionOptionalCapabilities(
        storageMountFactory: _defaultStorageMount,
        httpSessionFactory: QuickjsHttpSession.new,
        cryptoMountFactory: _defaultCryptoMount,
      );

  const QuickjsExtensionOptionalCapabilities.none()
    : storageMountFactory = null,
      httpSessionFactory = null,
      cryptoMountFactory = null,
      additionalVersions = const <String, int>{};

  final QuickjsExtensionStorageMountFactory? storageMountFactory;
  final QuickjsExtensionHttpSessionFactory? httpSessionFactory;
  final QuickjsExtensionCryptoMountFactory? cryptoMountFactory;
  final Map<String, int> additionalVersions;

  Map<String, int> get versions {
    for (final entry in additionalVersions.entries) {
      if (entry.value < 1) {
        throw ArgumentError.value(
          entry.value,
          'additionalVersions.${entry.key}',
          'must be positive',
        );
      }
    }
    return Map<String, int>.unmodifiable(<String, int>{
      if (storageMountFactory != null) 'storage': 1,
      if (httpSessionFactory != null) 'network': 1,
      if (cryptoMountFactory != null) 'crypto': 1,
      ...additionalVersions,
    });
  }
}

/// 安装前插件能力与宿主能力的比对结果。
final class QuickjsExtensionCapabilityInspection {
  const QuickjsExtensionCapabilityInspection({
    required this.required,
    required this.optional,
    required this.supported,
    required this.missingRequired,
    required this.missingOptional,
  });

  final Map<String, int> required;
  final Map<String, int> optional;
  final Map<String, int> supported;
  final Map<String, int> missingRequired;
  final Map<String, int> missingOptional;

  bool get canInstall => missingRequired.isEmpty;
}

/// 插件声明的必需能力不受当前宿主支持。
final class QuickjsExtensionCapabilityException implements Exception {
  const QuickjsExtensionCapabilityException(this.inspection);

  final QuickjsExtensionCapabilityInspection inspection;

  @override
  String toString() =>
      'QuickJS extension requires unavailable capabilities: '
      '${inspection.missingRequired.entries.map((e) => '${e.key}@${e.value}').join(', ')}';
}

QuickjsHostMount _defaultStorageMount(
  String extensionId,
  QuickjsExtensionStorage storage,
) => QuickjsExtensionStorageMount(extensionId: extensionId, storage: storage);

QuickjsHostMount _defaultCryptoMount() => QuickjsWebCryptoMount(
  randomUUID: true,
  getRandomValues: true,
  subtleDigest: true,
  subtleHmac: true,
);
