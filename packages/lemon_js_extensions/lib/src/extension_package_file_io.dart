import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

/// 从 [path] 读取扩展包的原始字节。
Future<Uint8List> readJsExtensionFileBytes(String path) =>
    File(path).readAsBytes();

/// 从 [path] 读取并以 UTF-8 解码扩展包文本。
Future<String> readJsExtensionFileString(String path) async =>
    utf8.decode(await readJsExtensionFileBytes(path));
