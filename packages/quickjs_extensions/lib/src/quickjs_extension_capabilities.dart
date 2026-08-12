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
      cryptoMountFactory = null;

  final QuickjsExtensionStorageMountFactory? storageMountFactory;
  final QuickjsExtensionHttpSessionFactory? httpSessionFactory;
  final QuickjsExtensionCryptoMountFactory? cryptoMountFactory;
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
