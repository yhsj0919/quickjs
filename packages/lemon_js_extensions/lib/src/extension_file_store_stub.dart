import 'extension_manager.dart';

/// 非 IO 平台上的文件 Store 占位实现。
final class JsExtensionFileStore implements JsExtensionStore {
  /// 创建非 IO 平台占位 Store；所有操作都会报告不支持。
  JsExtensionFileStore({required this.directoryPath});

  /// 调用方请求使用的目录路径。
  final String directoryPath;

  UnsupportedError _unsupported() => UnsupportedError(
    'Extension file store is unavailable on this platform: $directoryPath',
  );

  @override
  Future<List<JsExtensionStoreEntry>> loadAll() =>
      Future<List<JsExtensionStoreEntry>>.error(_unsupported());

  @override
  Future<JsExtensionStoreEntry?> load(String id) =>
      Future<JsExtensionStoreEntry?>.error(_unsupported());

  @override
  Future<void> save(JsExtensionStoreEntry extension) =>
      Future<void>.error(_unsupported());

  @override
  Future<void> remove(String id) => Future<void>.error(_unsupported());
}
