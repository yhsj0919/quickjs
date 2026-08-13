import 'package:lemon_js/lemon_js.dart';

/// 向后兼容名称；统一存储协议现由 lemon_js 核心提供。
typedef QuickjsExtensionStorage = JsKvStore;

/// 向后兼容名称；适合测试与临时 Session。
typedef InMemoryQuickjsExtensionStorage = MemoryJsKvStore;

/// 为扩展绑定插件 ID 命名空间，并保留原有模块名。
final class QuickjsExtensionStorageFeatures extends StorageFeatures {
  QuickjsExtensionStorageFeatures({
    required String extensionId,
    required JsKvStore storage,
  }) : super.custom(
         store: storage,
         namespace: extensionId,
         moduleSpecifier: 'lemon_js_extensions/storage',
         name: 'lemon_js_extensions.storage.$extensionId',
       );
}
