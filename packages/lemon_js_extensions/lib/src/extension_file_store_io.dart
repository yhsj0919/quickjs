import 'dart:convert';
import 'dart:io';

import 'extension_manager.dart';

/// 将每个扩展持久化为独立 JSON 文件的本地 Store。
final class JsExtensionFileStore implements JsExtensionStore {
  /// 创建将记录保存在 [directoryPath] 下的文件 Store。
  JsExtensionFileStore({required this.directoryPath});

  /// 安装记录所在的目录路径。
  final String directoryPath;

  Directory get _directory => Directory(directoryPath);

  @override
  Future<List<JsExtensionStoreEntry>> loadAll() async {
    final directory = _directory;
    if (!await directory.exists()) return const <JsExtensionStoreEntry>[];
    final entries = <JsExtensionStoreEntry>[];
    await for (final entity in directory.list(followLinks: false)) {
      if (entity is! File || !entity.path.endsWith('.json')) continue;
      if (entity.path.endsWith('.tmp.json') ||
          entity.path.endsWith('.backup.json')) {
        continue;
      }
      entries.add(await _read(entity));
    }
    entries.sort((left, right) => left.record.id.compareTo(right.record.id));
    return entries;
  }

  @override
  Future<JsExtensionStoreEntry?> load(String id) async {
    final file = _fileFor(id);
    return await file.exists() ? _read(file) : null;
  }

  @override
  Future<void> save(JsExtensionStoreEntry extension) async {
    await _directory.create(recursive: true);
    final target = _fileFor(extension.record.id);
    final temporary = File('${target.path}.tmp.json');
    final backup = File('${target.path}.backup.json');
    await temporary.writeAsString(
      jsonEncode(extension.toMap()),
      encoding: utf8,
      flush: true,
    );
    if (await backup.exists()) await backup.delete();
    final hadTarget = await target.exists();
    if (hadTarget) await target.rename(backup.path);
    try {
      await temporary.rename(target.path);
      if (await backup.exists()) await backup.delete();
    } catch (_) {
      if (await target.exists()) await target.delete();
      if (await backup.exists()) await backup.rename(target.path);
      rethrow;
    } finally {
      if (await temporary.exists()) await temporary.delete();
    }
  }

  @override
  Future<void> remove(String id) async {
    final file = _fileFor(id);
    if (await file.exists()) await file.delete();
  }

  File _fileFor(String id) {
    final encoded = base64Url.encode(utf8.encode(id)).replaceAll('=', '');
    return File('${_directory.path}${Platform.pathSeparator}$encoded.json');
  }

  Future<JsExtensionStoreEntry> _read(File file) async {
    final value = jsonDecode(await file.readAsString(encoding: utf8));
    if (value is! Map) {
      throw const FormatException('Extension store entry must be an object');
    }
    return JsExtensionStoreEntry.fromMap(Map<String, Object?>.from(value));
  }
}
