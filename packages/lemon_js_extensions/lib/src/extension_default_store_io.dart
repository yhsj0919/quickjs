import 'dart:async';

import 'package:path_provider/path_provider.dart';

import 'extension_file_store.dart';
import 'extension_manager.dart';

/// 原生平台默认将安装记录保存在应用支持目录。
final class JsExtensionDefaultStore implements JsExtensionStore {
  /// 创建一个延迟解析应用支持目录的默认 Store。
  JsExtensionDefaultStore();

  Future<JsExtensionStore>? _delegate;

  Future<JsExtensionStore> get _store => _delegate ??= _createDefaultStore();

  @override
  Future<List<JsExtensionStoreEntry>> loadAll() async =>
      (await _store).loadAll();

  @override
  Future<JsExtensionStoreEntry?> load(String id) async =>
      (await _store).load(id);

  @override
  Future<void> save(JsExtensionStoreEntry extension) async =>
      (await _store).save(extension);

  @override
  Future<void> remove(String id) async => (await _store).remove(id);
}

Future<JsExtensionStore> _createDefaultStore() async {
  final directory = await getApplicationSupportDirectory();
  return JsExtensionFileStore(
    directoryPath: '${directory.path}/lemon_js_extensions',
  );
}
