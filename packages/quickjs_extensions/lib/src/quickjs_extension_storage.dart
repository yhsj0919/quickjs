import 'package:lemon_js/lemon_js.dart';

/// 向后兼容名称；统一存储协议现由 lemon_js 核心提供。
typedef QuickjsExtensionStorage = QuickjsKeyValueStore;

/// 向后兼容名称；适合测试与临时 Session。
typedef InMemoryQuickjsExtensionStorage = InMemoryQuickjsKeyValueStore;

/// 为扩展绑定插件 ID 命名空间，并保留原有模块名。
final class QuickjsExtensionStorageMount extends QuickjsKeyValueStorageMount {
  QuickjsExtensionStorageMount({
    required String extensionId,
    required QuickjsKeyValueStore storage,
  }) : super.custom(
         store: storage,
         namespace: extensionId,
         moduleSpecifier: 'quickjs_extensions/storage',
         name: 'quickjs_extensions.storage.$extensionId',
       );
}
