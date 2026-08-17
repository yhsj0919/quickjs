import 'dart:typed_data';

/// 在不支持文件 IO 的平台报告扩展包字节读取不可用。
Future<Uint8List> readJsExtensionFileBytes(String path) =>
    Future<Uint8List>.error(
      UnsupportedError('Extension file loading is unavailable: $path'),
    );

/// 在不支持文件 IO 的平台报告扩展包文本读取不可用。
Future<String> readJsExtensionFileString(String path) => Future<String>.error(
  UnsupportedError('Extension file loading is unavailable: $path'),
);
