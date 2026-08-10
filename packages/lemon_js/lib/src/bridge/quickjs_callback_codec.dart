import 'dart:typed_data';

Object? decodeCallbackWireValue(Object? value) {
  if (value is List) {
    return [for (final item in value) decodeCallbackWireValue(item)];
  }
  if (value is Map) {
    if (value['__quickjsType'] == 'dartStream') {
      return value;
    }
    if (value['__quickjsType'] == 'bytes') {
      final bytes = value['value'];
      if (bytes is List) {
        return Uint8List.fromList([
          for (final byte in bytes) (byte as num).toInt(),
        ]);
      }
    }
    return {
      for (final entry in value.entries)
        entry.key as String: decodeCallbackWireValue(entry.value),
    };
  }
  return value;
}

Object? encodeCallbackWireValue(Object? value) {
  if (value is Uint8List) {
    return {'__quickjsType': 'bytes', 'value': value.toList()};
  }
  if (value is List) {
    return [for (final item in value) encodeCallbackWireValue(item)];
  }
  if (value is Map) {
    return {
      for (final entry in value.entries)
        _validateStringKey(entry.key): encodeCallbackWireValue(entry.value),
    };
  }
  return value;
}

String _validateStringKey(Object? key) {
  if (key is String) {
    return key;
  }
  throw ArgumentError('QuickJS callback map keys must be strings');
}
