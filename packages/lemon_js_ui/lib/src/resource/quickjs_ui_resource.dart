import '../schema/quickjs_ui_props.dart';

enum QuickjsUiResourceKind { asset, file, network, data, custom }

final class QuickjsUiResourcePolicy {
  const QuickjsUiResourcePolicy({required this.allowedSchemes});

  const QuickjsUiResourcePolicy.rendererDefault()
    : allowedSchemes = const <String>{'asset', 'file', 'http', 'https', 'data'};

  final Set<String> allowedSchemes;

  bool allows(String scheme) {
    return allowedSchemes.contains(scheme);
  }
}

final class QuickjsUiResourceReference {
  const QuickjsUiResourceReference({
    required this.location,
    required this.kind,
    this.mimeType,
    this.sha256,
    this.cacheKey,
    this.headers = const <String, String>{},
  });

  final String location;
  final QuickjsUiResourceKind kind;
  final String? mimeType;
  final String? sha256;
  final String? cacheKey;
  final Map<String, String> headers;

  Uri? get uri => Uri.tryParse(location);

  bool get isCacheable =>
      cacheKey != null ||
      sha256 != null ||
      kind == QuickjsUiResourceKind.asset ||
      kind == QuickjsUiResourceKind.network;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'kind': kind.name,
      'uri': location,
      if (mimeType != null) 'mimeType': mimeType,
      if (sha256 != null) 'sha256': sha256,
      if (cacheKey != null) 'cacheKey': cacheKey,
      if (headers.isNotEmpty) 'headers': headers,
    };
  }

  static QuickjsUiResourceReference parse(
    Object? value, {
    String name = 'resource',
    QuickjsUiResourcePolicy policy =
        const QuickjsUiResourcePolicy.rendererDefault(),
  }) {
    if (value is String) {
      return _fromParts(
        location: value,
        kind: null,
        name: name,
        policy: policy,
      );
    }
    final props = QuickjsUiProps.map(value, name: name);
    final location =
        QuickjsUiProps.string(
          props['uri'] ??
              props['url'] ??
              props['src'] ??
              props['source'] ??
              props['path'],
          name: '$name uri',
        ) ??
        '';
    final kind = _kind(QuickjsUiProps.string(props['kind'] ?? props['type']));
    return _fromParts(
      location: location,
      kind: kind,
      name: name,
      policy: policy,
      mimeType: QuickjsUiProps.string(props['mimeType'] ?? props['mime']),
      sha256: QuickjsUiProps.string(
        props['sha256'] ?? props['checksum'],
        name: '$name sha256',
      ),
      cacheKey: QuickjsUiProps.string(props['cacheKey']),
      headers: _headers(props['headers']),
    );
  }

  static QuickjsUiResourceReference _fromParts({
    required String location,
    required QuickjsUiResourceKind? kind,
    required String name,
    required QuickjsUiResourcePolicy policy,
    String? mimeType,
    String? sha256,
    String? cacheKey,
    Map<String, String> headers = const <String, String>{},
  }) {
    if (location.isEmpty) {
      throw FormatException('quickjs_ui $name uri must not be empty');
    }
    final inferred = kind ?? _inferKind(location);
    final scheme = _schemeFor(inferred, location);
    if (!policy.allows(scheme)) {
      throw FormatException('quickjs_ui $name scheme is not allowed: $scheme');
    }
    if (sha256 != null && !RegExp(r'^[0-9a-fA-F]{64}$').hasMatch(sha256)) {
      throw FormatException('quickjs_ui $name sha256 must be 64 hex chars');
    }
    return QuickjsUiResourceReference(
      location: location,
      kind: inferred,
      mimeType: mimeType,
      sha256: sha256?.toLowerCase(),
      cacheKey: cacheKey,
      headers: Map<String, String>.unmodifiable(headers),
    );
  }

  static QuickjsUiResourceKind _inferKind(String location) {
    final uri = Uri.tryParse(location);
    return switch (uri?.scheme) {
      'http' || 'https' => QuickjsUiResourceKind.network,
      'file' => QuickjsUiResourceKind.file,
      'data' => QuickjsUiResourceKind.data,
      '' || null => QuickjsUiResourceKind.asset,
      _ => QuickjsUiResourceKind.custom,
    };
  }

  static QuickjsUiResourceKind? _kind(String? value) {
    return switch (value) {
      null => null,
      'asset' => QuickjsUiResourceKind.asset,
      'file' => QuickjsUiResourceKind.file,
      'network' || 'http' || 'https' => QuickjsUiResourceKind.network,
      'data' => QuickjsUiResourceKind.data,
      'custom' => QuickjsUiResourceKind.custom,
      _ => throw FormatException('Unknown quickjs_ui resource kind: $value'),
    };
  }

  static String _schemeFor(QuickjsUiResourceKind kind, String location) {
    if (kind == QuickjsUiResourceKind.network) {
      final scheme = Uri.tryParse(location)?.scheme;
      return scheme == 'http' ? 'http' : 'https';
    }
    if (kind == QuickjsUiResourceKind.custom) {
      return Uri.tryParse(location)?.scheme ?? 'custom';
    }
    return kind.name;
  }

  static Map<String, String> _headers(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    final props = QuickjsUiProps.map(value, name: 'resource headers');
    return Map<String, String>.unmodifiable(
      props.map((key, value) {
        if (value is! String) {
          throw const FormatException(
            'quickjs_ui resource header values must be strings',
          );
        }
        return MapEntry<String, String>(key, value);
      }),
    );
  }
}
