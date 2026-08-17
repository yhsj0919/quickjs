import '../schema/quickjs_ui_props.dart';

/// Identifies how a JSUI resource location is resolved.
enum JsUiResourceKind {
  /// A Flutter asset or package-relative path.
  asset,

  /// A local file URI.
  file,

  /// An HTTP or HTTPS resource.
  network,

  /// An inline data URI.
  data,

  /// A resource handled by an application-defined scheme.
  custom,
}

/// Restricts URI schemes accepted while parsing resource references.
final class JsUiResourcePolicy {
  /// Creates a policy from its exact scheme allowlist.
  const JsUiResourcePolicy({required this.allowedSchemes});

  /// Creates the default renderer policy.
  const JsUiResourcePolicy.renderer()
    : allowedSchemes = const <String>{'asset', 'file', 'http', 'https', 'data'};

  /// URI schemes accepted by this policy.
  final Set<String> allowedSchemes;

  /// Whether [scheme] is accepted.
  bool allows(String scheme) {
    return allowedSchemes.contains(scheme);
  }
}

/// A validated, typed reference to a JSUI resource.
final class JsUiResourceReference {
  /// Creates a resource reference from validated values.
  const JsUiResourceReference({
    required this.uri,
    required this.kind,
    this.mimeType,
    this.sha256,
    this.cacheKey,
    this.headers = const <String, String>{},
  });

  /// Resource identifier, URL, asset path, file URI, or data URI.
  final String uri;

  /// Resource resolution kind.
  final JsUiResourceKind kind;

  /// Optional MIME type hint.
  final String? mimeType;

  /// Optional lowercase SHA-256 integrity digest.
  final String? sha256;

  /// Optional application-defined cache identity.
  final String? cacheKey;

  /// Headers used for network resource requests.
  final Map<String, String> headers;

  /// [uri] parsed as a [Uri], or `null` when parsing fails.
  Uri? get parsedUri => Uri.tryParse(uri);

  /// Whether this reference has a stable or explicit cache identity.
  bool get isCacheable =>
      cacheKey != null ||
      sha256 != null ||
      kind == JsUiResourceKind.asset ||
      kind == JsUiResourceKind.network;

  /// Serializes this reference to manifest-compatible structured data.
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'kind': kind.name,
      'uri': uri,
      if (mimeType != null) 'mimeType': mimeType,
      if (sha256 != null) 'sha256': sha256,
      if (cacheKey != null) 'cacheKey': cacheKey,
      if (headers.isNotEmpty) 'headers': headers,
    };
  }

  /// Parses a string or structured resource reference under [policy].
  ///
  /// Throws [FormatException] for invalid locations, kinds, headers, hashes,
  /// or disallowed schemes.
  static JsUiResourceReference parse(
    Object? value, {
    String name = 'resource',
    JsUiResourcePolicy policy = const JsUiResourcePolicy.renderer(),
  }) {
    if (value is String) {
      return _fromParts(
        location: value,
        kind: null,
        name: name,
        policy: policy,
      );
    }
    final props = JsUiProps.map(value, name: name);
    final location =
        JsUiProps.string(
          props['uri'] ??
              props['url'] ??
              props['src'] ??
              props['source'] ??
              props['path'],
          name: '$name uri',
        ) ??
        '';
    final kind = _kind(JsUiProps.string(props['kind'] ?? props['type']));
    return _fromParts(
      location: location,
      kind: kind,
      name: name,
      policy: policy,
      mimeType: JsUiProps.string(props['mimeType'] ?? props['mime']),
      sha256: JsUiProps.string(
        props['sha256'] ?? props['checksum'],
        name: '$name sha256',
      ),
      cacheKey: JsUiProps.string(props['cacheKey']),
      headers: _headers(props['headers']),
    );
  }

  static JsUiResourceReference _fromParts({
    required String location,
    required JsUiResourceKind? kind,
    required String name,
    required JsUiResourcePolicy policy,
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
    return JsUiResourceReference(
      uri: location,
      kind: inferred,
      mimeType: mimeType,
      sha256: sha256?.toLowerCase(),
      cacheKey: cacheKey,
      headers: Map<String, String>.unmodifiable(headers),
    );
  }

  static JsUiResourceKind _inferKind(String location) {
    final uri = Uri.tryParse(location);
    return switch (uri?.scheme) {
      'http' || 'https' => JsUiResourceKind.network,
      'file' => JsUiResourceKind.file,
      'data' => JsUiResourceKind.data,
      '' || null => JsUiResourceKind.asset,
      _ => JsUiResourceKind.custom,
    };
  }

  static JsUiResourceKind? _kind(String? value) {
    return switch (value) {
      null => null,
      'asset' => JsUiResourceKind.asset,
      'file' => JsUiResourceKind.file,
      'network' || 'http' || 'https' => JsUiResourceKind.network,
      'data' => JsUiResourceKind.data,
      'custom' => JsUiResourceKind.custom,
      _ => throw FormatException('Unknown quickjs_ui resource kind: $value'),
    };
  }

  static String _schemeFor(JsUiResourceKind kind, String location) {
    if (kind == JsUiResourceKind.network) {
      final scheme = Uri.tryParse(location)?.scheme;
      return scheme == 'http' ? 'http' : 'https';
    }
    if (kind == JsUiResourceKind.custom) {
      return Uri.tryParse(location)?.scheme ?? 'custom';
    }
    return kind.name;
  }

  static Map<String, String> _headers(Object? value) {
    if (value == null) {
      return const <String, String>{};
    }
    final props = JsUiProps.map(value, name: 'resource headers');
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
