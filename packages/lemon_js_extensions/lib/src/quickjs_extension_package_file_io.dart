import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readQuickjsExtensionFileBytes(String path) =>
    File(path).readAsBytes();

Future<String> readQuickjsExtensionFileString(String path) async =>
    utf8.decode(await readQuickjsExtensionFileBytes(path));
