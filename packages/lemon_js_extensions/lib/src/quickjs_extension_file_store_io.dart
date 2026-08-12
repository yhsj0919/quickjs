import 'dart:convert';
import 'dart:io';

import 'quickjs_extension_manager.dart';

/// 将每个扩展持久化为独立 JSON 文件的本地 Store。
final class QuickjsExtensionFileStore implements QuickjsExtensionStore {
  QuickjsExtensionFileStore({required this.directoryPath});

  final String directoryPath;

  Directory get _directory => Directory(directoryPath);

  @override
  Future<List<StoredQuickjsExtension>> loadAll() async {
    final directory = _directory;
    if (!await directory.exists()) return const <StoredQuickjsExtension>[];
    final entries = <StoredQuickjsExtension>[];
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
  Future<StoredQuickjsExtension?> load(String id) async {
    final file = _fileFor(id);
    return await file.exists() ? _read(file) : null;
  }

  @override
  Future<void> save(StoredQuickjsExtension extension) async {
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

  Future<StoredQuickjsExtension> _read(File file) async {
    final value = jsonDecode(await file.readAsString(encoding: utf8));
    if (value is! Map) {
      throw const FormatException('Extension store entry must be an object');
    }
    return StoredQuickjsExtension.fromMap(Map<String, Object?>.from(value));
  }
}
