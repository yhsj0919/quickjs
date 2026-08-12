import 'dart:typed_data';

Future<Uint8List> readQuickjsExtensionFileBytes(String path) =>
    Future<Uint8List>.error(
      UnsupportedError('Extension file loading is unavailable: $path'),
    );

Future<String> readQuickjsExtensionFileString(String path) =>
    Future<String>.error(
      UnsupportedError('Extension file loading is unavailable: $path'),
    );
