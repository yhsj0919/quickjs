import 'package:lemon_js/lemon_js.dart';

/// Optional application-layer permission policy for quickjs_ui pages.
///
/// The policy only validates the page manifest. It does not expose host APIs or
/// grant native capabilities by itself; callable APIs still come from explicit
/// [JsFeatures] values.
final class JsUiPermissionPolicy {
  /// Creates a policy that accepts every manifest permission.
  const JsUiPermissionPolicy.unrestricted()
    : _restricted = false,
      _allowedPermissions = const <String>{};

  /// Creates a policy restricted to permission names in [allowed].
  JsUiPermissionPolicy.restricted({required Iterable<String> allowed})
    : _restricted = true,
      _allowedPermissions = Set<String>.unmodifiable(allowed);

  final bool _restricted;
  final Set<String> _allowedPermissions;

  /// Whether manifest permissions must pass the allowlist and grant checks.
  bool get isRestricted => _restricted;

  /// The immutable permission allowlist used by a restricted policy.
  Set<String> get allowedPermissions => _allowedPermissions;

  /// Validates the permissions requested by [plugin].
  ///
  /// A restricted policy requires every requested permission to appear in both
  /// [allowedPermissions] and [grantedPermissions]. Throws
  /// [JsUiPermissionException] with both failure sets when validation fails.
  void validate({
    required JsPlugin plugin,
    Iterable<String> grantedPermissions = const <String>[],
  }) {
    if (!_restricted) {
      return;
    }
    final requested = plugin.manifest.permissions.toSet();
    final granted = grantedPermissions.toSet();
    final deniedByPolicy = requested.difference(_allowedPermissions);
    final missingGrants = requested.difference(granted);
    if (deniedByPolicy.isEmpty && missingGrants.isEmpty) {
      return;
    }
    throw JsUiPermissionException(
      pluginId: plugin.manifest.id,
      requestedPermissions: requested,
      allowedPermissions: _allowedPermissions,
      grantedPermissions: granted,
      deniedByPolicy: deniedByPolicy,
      missingGrants: missingGrants,
    );
  }

  @override
  bool operator ==(Object other) {
    return other is JsUiPermissionPolicy &&
        other._restricted == _restricted &&
        _setEquals(other._allowedPermissions, _allowedPermissions);
  }

  @override
  int get hashCode => Object.hash(
    _restricted,
    Object.hashAll(_allowedPermissions.toList()..sort()),
  );
}

/// Reports permissions rejected by policy or absent from runtime feature grants.
final class JsUiPermissionException implements Exception {
  /// Creates a permission validation failure with its diagnostic sets.
  const JsUiPermissionException({
    required this.pluginId,
    required this.requestedPermissions,
    required this.allowedPermissions,
    required this.grantedPermissions,
    required this.deniedByPolicy,
    required this.missingGrants,
  });

  /// Identifier of the plugin whose manifest failed validation.
  final String pluginId;

  /// All permissions requested by the plugin manifest.
  final Set<String> requestedPermissions;

  /// Permissions accepted by the application policy.
  final Set<String> allowedPermissions;

  /// Permissions provided to validation by the installed runtime features.
  final Set<String> grantedPermissions;

  /// Requested permissions absent from [allowedPermissions].
  final Set<String> deniedByPolicy;

  /// Requested permissions absent from [grantedPermissions].
  final Set<String> missingGrants;

  @override
  String toString() {
    final details = <String>[];
    if (deniedByPolicy.isNotEmpty) {
      details.add('denied by policy: ${_sorted(deniedByPolicy).join(', ')}');
    }
    if (missingGrants.isNotEmpty) {
      details.add(
        'not granted by features: ${_sorted(missingGrants).join(', ')}',
      );
    }
    return 'JsUiPermissionException(plugin: $pluginId, ${details.join('; ')})';
  }
}

bool _setEquals(Set<String> left, Set<String> right) {
  if (left.length != right.length) {
    return false;
  }
  return left.containsAll(right);
}

List<String> _sorted(Set<String> values) => values.toList()..sort();
