import 'dart:convert';

import 'package:http/http.dart' as http;

import 'quickjs_extension_manager.dart';
import 'quickjs_extension_package.dart';

/// 远程更新描述。
final class QuickjsExtensionUpdateInfo {
  const QuickjsExtensionUpdateInfo({
    required this.id,
    required this.version,
    required this.versionCode,
    required this.compatibilityCode,
    required this.downloadUrl,
    this.releaseNotes,
  });

  factory QuickjsExtensionUpdateInfo.fromMap(Map<String, Object?> map) {
    final downloadUrl = Uri.parse(map['downloadUrl']! as String);
    if (downloadUrl.scheme != 'https' || downloadUrl.host.isEmpty) {
      throw const FormatException(
        'Extension update downloadUrl must use HTTPS',
      );
    }
    return QuickjsExtensionUpdateInfo(
      id: map['id']! as String,
      version: map['version']! as String,
      versionCode: map['versionCode']! as int,
      compatibilityCode: map['compatibilityCode']! as String,
      downloadUrl: downloadUrl,
      releaseNotes: map['releaseNotes'] as String?,
    );
  }

  static QuickjsExtensionUpdateInfo parse(String source) {
    final value = jsonDecode(source);
    if (value is! Map) {
      throw const FormatException(
        'Extension update descriptor must be an object',
      );
    }
    return QuickjsExtensionUpdateInfo.fromMap(Map<String, Object?>.from(value));
  }

  final String id;
  final String version;
  final int versionCode;
  final String compatibilityCode;
  final Uri downloadUrl;
  final String? releaseNotes;
}

/// 一次远程更新检查的结果。
final class QuickjsExtensionUpdateCheck {
  const QuickjsExtensionUpdateCheck({
    required this.info,
    required this.available,
  });

  final QuickjsExtensionUpdateInfo info;
  final bool available;
}

/// 为 Manager 提供更新描述获取、ZIP 下载和事务更新。
extension QuickjsExtensionManagerUpdates on QuickjsExtensionManager {
  Future<QuickjsExtensionUpdateCheck> checkForUpdate(
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
      final info = QuickjsExtensionUpdateInfo.parse(
        utf8.decode(response.bodyBytes),
      );
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
      return QuickjsExtensionUpdateCheck(
        info: info,
        available: info.versionCode > current.versionCode,
      );
    } finally {
      if (ownedClient) resolvedClient.close();
    }
  }

  Future<ManagedQuickjsExtension> downloadAndUpdate(
    String id,
    QuickjsExtensionUpdateInfo info, {
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
      final package = await QuickjsExtensionPackage.zipBytes(
        response.bodyBytes,
      );
      final manifest = package.manifest;
      if (manifest.versionCode != info.versionCode ||
          manifest.version != info.version) {
        throw const FormatException(
          'Downloaded extension version does not match update descriptor',
        );
      }
      return update(
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
