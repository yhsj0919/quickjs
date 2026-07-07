import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readQuickjsUiFileBytes(String path) {
  return File(path).readAsBytes();
}
