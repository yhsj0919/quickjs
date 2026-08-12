import 'quickjs_extension_manager.dart';

/// 非 IO 平台上的文件 Store 占位实现。
final class QuickjsExtensionFileStore implements QuickjsExtensionStore {
  QuickjsExtensionFileStore({required this.directoryPath});

  final String directoryPath;

  UnsupportedError _unsupported() => UnsupportedError(
    'Extension file store is unavailable on this platform: $directoryPath',
  );

  @override
  Future<List<StoredQuickjsExtension>> loadAll() =>
      Future<List<StoredQuickjsExtension>>.error(_unsupported());

  @override
  Future<StoredQuickjsExtension?> load(String id) =>
      Future<StoredQuickjsExtension?>.error(_unsupported());

  @override
  Future<void> save(StoredQuickjsExtension extension) =>
      Future<void>.error(_unsupported());

  @override
  Future<void> remove(String id) => Future<void>.error(_unsupported());
}
