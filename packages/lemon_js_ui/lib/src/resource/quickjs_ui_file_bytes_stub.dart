// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:typed_data';

Future<Uint8List> readJsUiFileBytes(String path) {
  throw UnsupportedError(
    'quickjs_ui file bundles are not supported on this platform: $path',
  );
}
