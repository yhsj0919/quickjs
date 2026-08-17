import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import '../runtime/runtime_options.dart';

/// 可替换的异步命名空间 KV 存储。
abstract interface class JsKvStore {
  /// 读取 [namespace] 中 [key] 对应的值；不存在时返回 `null`。
  Future<Object?> get(String key, {String? namespace});

  /// 在 [namespace] 中写入 [key] 对应的 JSON 兼容值。
  Future<void> set(String key, Object? value, {String? namespace});

  /// 判断 [namespace] 中是否存在 [key]。
  Future<bool> containsKey(String key, {String? namespace});

  /// 从 [namespace] 删除 [key]。
  Future<void> remove(String key, {String? namespace});

  /// 返回 [namespace] 中的全部键。
  Future<List<String>> keys({String? namespace});

  /// 清空 [namespace] 中的全部条目。
  Future<void> clear({String? namespace});
}

/// 适合测试和临时 Session 的内存 KV 实现。
final class JsMemoryKvStore implements JsKvStore {
  final Map<String, Map<String, Object?>> _namespaces =
      <String, Map<String, Object?>>{};

  String _namespace(String? namespace) => namespace ?? '';

  @override
  Future<Object?> get(String key, {String? namespace}) async =>
      _namespaces[_namespace(namespace)]?[key];

  @override
  Future<void> set(String key, Object? value, {String? namespace}) async {
    // 验证值可以稳定穿过 Dart/JS JSON 边界。
    jsonEncode(value);
    (_namespaces[_namespace(namespace)] ??= <String, Object?>{})[key] = value;
  }

  @override
  Future<bool> containsKey(String key, {String? namespace}) async =>
      _namespaces[_namespace(namespace)]?.containsKey(key) ?? false;

  @override
  Future<void> remove(String key, {String? namespace}) async {
    _namespaces[_namespace(namespace)]?.remove(key);
  }

  @override
  Future<List<String>> keys({String? namespace}) async =>
      List<String>.unmodifiable(
        _namespaces[_namespace(namespace)]?.keys ?? const <String>[],
      );

  @override
  Future<void> clear({String? namespace}) async {
    _namespaces.remove(_namespace(namespace));
  }
}

/// 使用 Flutter shared_preferences 提供的默认持久化 KV 实现。
///
/// 所有值统一编码为 JSON，因此支持 null、bool、num、String、List 和
/// `Map<String, Object?>`。它适合配置、认证状态和少量缓存，不用于数据库查询、事务或
/// 关键数据的可靠刷盘。
final class JsSharedPreferencesKvStore implements JsKvStore {
  /// 创建持久化 Store；可注入 [preferences] 以共享实例或便于测试。
  JsSharedPreferencesKvStore({SharedPreferencesAsync? preferences})
    : _injectedPreferences = preferences;

  static const String _prefix = 'lemon_js.kv.v1.';
  final SharedPreferencesAsync? _injectedPreferences;
  SharedPreferencesAsync? _createdPreferences;

  SharedPreferencesAsync get _preferences =>
      _injectedPreferences ??
      (_createdPreferences ??= SharedPreferencesAsync());

  @override
  Future<Object?> get(String key, {String? namespace}) async {
    final source = await _preferences.getString(_storageKey(namespace, key));
    if (source == null) return null;
    final envelope = jsonDecode(source);
    if (envelope is! Map || !envelope.containsKey('value')) {
      throw const FormatException('Invalid lemon_js KV value envelope');
    }
    return envelope['value'];
  }

  @override
  Future<void> set(String key, Object? value, {String? namespace}) async {
    final source = jsonEncode(<String, Object?>{'value': value});
    await _preferences.setString(_storageKey(namespace, key), source);
  }

  @override
  Future<bool> containsKey(String key, {String? namespace}) =>
      _preferences.containsKey(_storageKey(namespace, key));

  @override
  Future<void> remove(String key, {String? namespace}) =>
      _preferences.remove(_storageKey(namespace, key));

  @override
  Future<List<String>> keys({String? namespace}) async {
    final prefix = _namespacePrefix(namespace);
    final result = <String>[];
    for (final key in await _preferences.getKeys()) {
      if (!key.startsWith(prefix)) continue;
      result.add(_decode(key.substring(prefix.length)));
    }
    result.sort();
    return List<String>.unmodifiable(result);
  }

  @override
  Future<void> clear({String? namespace}) async {
    final prefix = _namespacePrefix(namespace);
    final matching = (await _preferences.getKeys())
        .where((key) => key.startsWith(prefix))
        .toList(growable: false);
    for (final key in matching) {
      await _preferences.remove(key);
    }
  }

  String _storageKey(String? namespace, String key) {
    _validateKey(key);
    return '${_namespacePrefix(namespace)}${_encode(key)}';
  }

  String _namespacePrefix(String? namespace) =>
      '$_prefix${_encode(namespace ?? '')}.';
}

/// 将一个已经绑定命名空间的 KV Store 暴露为 ES module。
base class StorageFeatures extends JsFeatures {
  /// 创建导出 KV Store ES module 的默认能力集合。
  factory StorageFeatures({
    JsKvStore? store,
    String? namespace,
    String moduleSpecifier = 'lemon_js/storage',
    String? name,
  }) => StorageFeatures.custom(
    store: store ?? JsSharedPreferencesKvStore(),
    namespace: namespace,
    moduleSpecifier: moduleSpecifier,
    name: name,
  );

  /// 供需要自定义模块名的组合层使用。
  StorageFeatures.custom({
    required JsKvStore store,
    required String? namespace,
    required String moduleSpecifier,
    required String? name,
  }) : super(
         name: name ?? 'lemon_js.storage.${_encode(namespace ?? '')}',
         methods: <JsHostMethod>[
           JsHostMethod(
             name:
                 '${name ?? 'lemon_js.storage.${_encode(namespace ?? '')}'}.call',
             debugName: 'kv-storage:${namespace ?? 'default'}',
             callback: (arguments, context) async {
               final command = _command(arguments);
               final operation = command['op'];
               final key = command['key'];
               if (operation != 'clear' && operation != 'keys') {
                 if (key is! String || key.isEmpty) {
                   throw ArgumentError('KV storage key is required');
                 }
               }
               final result = switch (operation) {
                 'get' => await store.get(key! as String, namespace: namespace),
                 'set' =>
                   await store
                       .set(
                         key! as String,
                         command['value'],
                         namespace: namespace,
                       )
                       .then<Object?>((_) => null),
                 'containsKey' => await store.containsKey(
                   key! as String,
                   namespace: namespace,
                 ),
                 'remove' =>
                   await store
                       .remove(key! as String, namespace: namespace)
                       .then<Object?>((_) => null),
                 'keys' => await store.keys(namespace: namespace),
                 'clear' =>
                   await store
                       .clear(namespace: namespace)
                       .then<Object?>((_) => null),
                 _ => throw ArgumentError(
                   'Unsupported KV storage operation: $operation',
                 ),
               };
               context.throwIfCancelled();
               return result;
             },
           ),
         ],
         modules: <JsModule>[
           JsModule(
             name: moduleSpecifier,
             source: _storageModuleSource(
               '${name ?? 'lemon_js.storage.${_encode(namespace ?? '')}'}.call',
             ),
           ),
         ],
       );
}

Map<String, Object?> _command(List<Object?> arguments) {
  if (arguments.length != 1 || arguments.single is! Map) {
    throw ArgumentError('KV storage expects one command object');
  }
  return (arguments.single! as Map).map(
    (key, value) => MapEntry('$key', value),
  );
}

String _storageModuleSource(String methodName) =>
    '''
const method = globalThis.__jsHostMethods['$methodName'];

export const storage = Object.freeze({
  get(key) { return method({op: 'get', key: String(key)}); },
  set(key, value) { return method({op: 'set', key: String(key), value}); },
  containsKey(key) { return method({op: 'containsKey', key: String(key)}); },
  remove(key) { return method({op: 'remove', key: String(key)}); },
  keys() { return method({op: 'keys'}); },
  clear() { return method({op: 'clear'}); },
});

export default storage;
''';

String _encode(String value) => base64Url.encode(utf8.encode(value));

String _decode(String value) => utf8.decode(base64Url.decode(value));

void _validateKey(String key) {
  if (key.isEmpty) throw ArgumentError.value(key, 'key', 'must not be empty');
}
