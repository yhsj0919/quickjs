import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

import 'quickjs_extension_manager.dart';

/// Web 等非 IO 平台使用 SharedPreferences 后端持久化安装记录。
final class QuickjsExtensionDefaultStore implements QuickjsExtensionStore {
  QuickjsExtensionDefaultStore();

  static const _indexKey = 'lemon_js_extensions.installations';
  static const _entryPrefix = 'lemon_js_extensions.installation.';

  final SharedPreferencesAsync _preferences = SharedPreferencesAsync();

  @override
  Future<List<StoredQuickjsExtension>> loadAll() async {
    final ids = await _preferences.getStringList(_indexKey) ?? const <String>[];
    final entries = <StoredQuickjsExtension>[];
    for (final id in ids) {
      final entry = await load(id);
      if (entry != null) entries.add(entry);
    }
    entries.sort((left, right) => left.record.id.compareTo(right.record.id));
    return entries;
  }

  @override
  Future<StoredQuickjsExtension?> load(String id) async {
    final source = await _preferences.getString(_key(id));
    if (source == null) return null;
    final decoded = jsonDecode(source);
    if (decoded is! Map) {
      throw const FormatException('Extension store entry must be an object');
    }
    return StoredQuickjsExtension.fromMap(Map<String, Object?>.from(decoded));
  }

  @override
  Future<void> save(StoredQuickjsExtension extension) async {
    final id = extension.record.id;
    await _preferences.setString(_key(id), jsonEncode(extension.toMap()));
    final ids =
        (await _preferences.getStringList(_indexKey) ?? <String>[]).toSet()
          ..add(id);
    final sorted = ids.toList()..sort();
    await _preferences.setStringList(_indexKey, sorted);
  }

  @override
  Future<void> remove(String id) async {
    await _preferences.remove(_key(id));
    final ids = (await _preferences.getStringList(_indexKey) ?? <String>[])
        .where((item) => item != id)
        .toList();
    await _preferences.setStringList(_indexKey, ids);
  }

  String _key(String id) => '$_entryPrefix${base64Url.encode(utf8.encode(id))}';
}
