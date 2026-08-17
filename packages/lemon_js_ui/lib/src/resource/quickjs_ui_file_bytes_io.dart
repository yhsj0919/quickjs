// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:io';
import 'dart:typed_data';

Future<Uint8List> readJsUiFileBytes(String path) {
  return File(path).readAsBytes();
}
