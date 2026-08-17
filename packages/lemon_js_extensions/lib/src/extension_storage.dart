import 'package:lemon_js/lemon_js.dart';

/// 为扩展绑定插件 ID 命名空间，并保留原有模块名。
final class JsKvStoreFeatures extends StorageFeatures {
  /// 为 [extensionId] 创建隔离命名空间的存储能力。
  JsKvStoreFeatures({required String extensionId, required JsKvStore storage})
    : super.custom(
        store: storage,
        namespace: extensionId,
        moduleSpecifier: 'lemon_js_extensions/storage',
        name: 'lemon_js_extensions.storage.$extensionId',
      );
}
