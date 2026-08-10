import 'dart:typed_data';

Future<Uint8List> readQuickjsUiFileBytes(String path) {
  throw UnsupportedError(
    'quickjs_ui file bundles are not supported on this platform: $path',
  );
}
