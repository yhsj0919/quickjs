import 'package:lemon_js/lemon_js.dart';

/// 由插件 ID 分区的 KV 存储接口。
abstract interface class QuickjsExtensionStorage {
  Future<Object?> get(String extensionId, String key);

  Future<void> set(String extensionId, String key, Object? value);

  Future<void> remove(String extensionId, String key);

  Future<void> clear(String extensionId);
}

/// 适合测试与开发的内存 KV 存储。
final class InMemoryQuickjsExtensionStorage implements QuickjsExtensionStorage {
  final Map<String, Map<String, Object?>> _namespaces =
      <String, Map<String, Object?>>{};

  @override
  Future<Object?> get(String extensionId, String key) async =>
      _namespaces[extensionId]?[key];

  @override
  Future<void> set(String extensionId, String key, Object? value) async {
    (_namespaces[extensionId] ??= <String, Object?>{})[key] = value;
  }

  @override
  Future<void> remove(String extensionId, String key) async {
    _namespaces[extensionId]?.remove(key);
  }

  @override
  Future<void> clear(String extensionId) async {
    _namespaces.remove(extensionId);
  }
}

/// 向 JavaScript 注入当前扩展专属存储模块的挂载点。
final class QuickjsExtensionStorageMount extends QuickjsHostMount {
  QuickjsExtensionStorageMount({
    required String extensionId,
    required QuickjsExtensionStorage storage,
  }) : super(
         name: 'quickjs_extensions.storage.$extensionId',
         providers: <QuickjsHostProvider>[
           QuickjsHostProvider.dart(
             name: 'quickjs_extensions.storage.$extensionId.call',
             debugName: 'extension-storage:$extensionId',
             callback: (args, context) async {
               if (args.length != 1 || args.single is! Map) {
                 throw ArgumentError(
                   'Extension storage expects one command object',
                 );
               }
               final command = (args.single! as Map).map(
                 (key, value) => MapEntry('$key', value),
               );
               final operation = command['op'];
               final key = command['key'];
               if (operation != 'clear' && (key is! String || key.isEmpty)) {
                 throw ArgumentError('Extension storage key is required');
               }
               final result = switch (operation) {
                 'get' => await storage.get(extensionId, key! as String),
                 'set' =>
                   await storage
                       .set(extensionId, key! as String, command['value'])
                       .then<Object?>((_) => null),
                 'remove' =>
                   await storage
                       .remove(extensionId, key! as String)
                       .then<Object?>((_) => null),
                 'clear' =>
                   await storage.clear(extensionId).then<Object?>((_) => null),
                 _ => throw ArgumentError(
                   'Unsupported extension storage operation: $operation',
                 ),
               };
               context.throwIfCancelled();
               return result;
             },
           ),
         ],
         modules: <QuickjsHostModule>[
           QuickjsHostModule.esModule(
             specifier: 'quickjs_extensions/storage',
             source: _storageModuleSource(extensionId),
           ),
         ],
       );
}

String _storageModuleSource(String extensionId) {
  final providerName = 'quickjs_extensions.storage.$extensionId.call';
  return '''
const provider = globalThis.__quickjsHostProviders['$providerName'];

export const storage = Object.freeze({
  get(key) { return provider({op: 'get', key: String(key)}); },
  set(key, value) { return provider({op: 'set', key: String(key), value}); },
  remove(key) { return provider({op: 'remove', key: String(key)}); },
  clear() { return provider({op: 'clear'}); },
});

export default storage;
''';
}
