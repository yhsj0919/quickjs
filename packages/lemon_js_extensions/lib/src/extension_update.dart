import 'dart:convert';

import 'package:http/http.dart' as http;

import 'extension_manager.dart';
import 'extension_package.dart';

/// 远程更新描述。
final class JsExtensionUpdateInfo {
  /// Creates a remote update descriptor.
  const JsExtensionUpdateInfo({
    required this.id,
    required this.version,
    required this.versionCode,
    required this.compatibilityCode,
    required this.downloadUrl,
    this.releaseNotes,
  });

  /// Parses an update descriptor from a decoded JSON object.
  factory JsExtensionUpdateInfo.fromMap(Map<String, Object?> map) {
    final downloadUrl = Uri.parse(map['downloadUrl']! as String);
    if (downloadUrl.scheme != 'https' || downloadUrl.host.isEmpty) {
      throw const FormatException(
        'Extension update downloadUrl must use HTTPS',
      );
    }
    return JsExtensionUpdateInfo(
      id: map['id']! as String,
      version: map['version']! as String,
      versionCode: map['versionCode']! as int,
      compatibilityCode: map['compatibilityCode']! as String,
      downloadUrl: downloadUrl,
      releaseNotes: map['releaseNotes'] as String?,
    );
  }

  /// Parses an update descriptor from JSON [source].
  static JsExtensionUpdateInfo parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException(
        'Extension update descriptor must be an object',
      );
    }
    return JsExtensionUpdateInfo.fromMap(Map<String, Object?>.from(value));
  }

  /// Extension identifier expected in the downloaded package.
  final String id;

  /// User-visible remote version string.
  final String version;

  /// Monotonic remote version code.
  final int versionCode;

  /// Compatibility contract expected in the downloaded package.
  final String compatibilityCode;

  /// HTTPS URL of the extension archive.
  final Uri downloadUrl;

  /// Optional user-visible release notes.
  final String? releaseNotes;
}

/// 一次远程更新检查的结果。
final class JsExtensionUpdateCheck {
  /// Creates the result of comparing remote and installed versions.
  const JsExtensionUpdateCheck({required this.info, required this.available});

  /// Validated remote update descriptor.
  final JsExtensionUpdateInfo info;

  /// Whether the remote version code is newer than the installed one.
  final bool available;
}

/// 为 Manager 提供更新描述获取、ZIP 下载和事务更新。
extension JsExtensionManagerUpdates on JsExtensionManager {
  /// 获取远程更新描述，并比较已安装的 `versionCode`。不会下载安装包。
  Future<JsExtensionUpdateCheck> checkForUpdate(
    String id, {
    http.Client? client,
  }) async {
    final current = find(id);
    if (current == null) throw StateError('Extension is not installed: $id');
    final updateUrl = current.record.updateUrl;
    if (updateUrl == null) {
      throw StateError('Extension does not declare updateUrl: $id');
    }
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    try {
      final response = await resolvedClient.get(updateUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Extension update check failed with HTTP ${response.statusCode}',
          updateUrl,
        );
      }
      final info = JsExtensionUpdateInfo.parse(utf8.decode(response.bodyBytes));
      if (info.id != id) {
        throw const FormatException(
          'Extension update descriptor id does not match installed extension',
        );
      }
      if (info.compatibilityCode != current.record.compatibilityCode) {
        throw const FormatException(
          'Extension update compatibilityCode does not match installed extension',
        );
      }
      return JsExtensionUpdateCheck(
        info: info,
        available: info.versionCode > current.versionCode,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  /// 下载 [info] 指向的 ZIP，并通过 Manager 的事务更新流程完成安装。
  Future<JsExtensionManagerEntry> downloadAndUpdate(
    String id,
    JsExtensionUpdateInfo info, {
    http.Client? client,
    bool allowDowngrade = false,
    bool allowSameVersion = false,
  }) async {
    final current = find(id);
    if (current == null) throw StateError('Extension is not installed: $id');
    if (info.id != id ||
        info.compatibilityCode != current.record.compatibilityCode) {
      throw const FormatException(
        'Extension update descriptor does not match installed extension',
      );
    }
    final ownedClient = client == null;
    final resolvedClient = client ?? http.Client();
    try {
      final response = await resolvedClient.get(info.downloadUrl);
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw http.ClientException(
          'Extension update download failed with HTTP ${response.statusCode}',
          info.downloadUrl,
        );
      }
      final package = await JsExtensionPackage.zipBytes(response.bodyBytes);
      final manifest = package.manifest;
      if (manifest.versionCode != info.versionCode ||
          manifest.version != info.version) {
        throw const FormatException(
          'Downloaded extension version does not match update descriptor',
        );
      }
      return await update(
        id,
        package,
        allowDowngrade: allowDowngrade,
        allowSameVersion: allowSameVersion,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }
}
