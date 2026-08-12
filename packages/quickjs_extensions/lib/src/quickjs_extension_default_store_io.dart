import 'dart:async';

import 'package:path_provider/path_provider.dart';

import 'quickjs_extension_file_store.dart';
import 'quickjs_extension_manager.dart';

/// 原生平台默认将安装记录保存在应用支持目录。
final class QuickjsExtensionDefaultStore implements QuickjsExtensionStore {
  QuickjsExtensionDefaultStore();

  Future<QuickjsExtensionStore>? _delegate;

  Future<QuickjsExtensionStore> get _store =>
      _delegate ??= _createDefaultStore();

  @override
  Future<List<StoredQuickjsExtension>> loadAll() async =>
      (await _store).loadAll();

  @override
  Future<StoredQuickjsExtension?> load(String id) async =>
      (await _store).load(id);

  @override
  Future<void> save(StoredQuickjsExtension extension) async =>
      (await _store).save(extension);

  @override
  Future<void> remove(String id) async => (await _store).remove(id);
}

Future<QuickjsExtensionStore> _createDefaultStore() async {
  final directory = await getApplicationSupportDirectory();
  return QuickjsExtensionFileStore(
    directoryPath: '${directory.path}/quickjs_extensions',
  );
}
