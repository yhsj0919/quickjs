import 'package:quickjs/quickjs.dart';

/// Optional application-layer permission policy for quickjs_ui pages.
///
/// The policy only validates the page manifest. It does not mount host APIs or
/// grant native capabilities by itself; callable APIs still come from explicit
/// [QuickjsHostMount] values.
final class QuickjsUiPermissionPolicy {
  const QuickjsUiPermissionPolicy.unrestricted()
    : _restricted = false,
      _allowedPermissions = const <String>{};

  QuickjsUiPermissionPolicy.restricted({required Iterable<String> allowed})
    : _restricted = true,
      _allowedPermissions = Set<String>.unmodifiable(allowed);

  final bool _restricted;
  final Set<String> _allowedPermissions;

  bool get isRestricted => _restricted;
  Set<String> get allowedPermissions => _allowedPermissions;

  void validate({
    required QuickjsPlugin plugin,
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
    throw QuickjsUiPermissionException(
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
    return other is QuickjsUiPermissionPolicy &&
        other._restricted == _restricted &&
        _setEquals(other._allowedPermissions, _allowedPermissions);
  }

  @override
  int get hashCode => Object.hash(
    _restricted,
    Object.hashAll(_allowedPermissions.toList()..sort()),
  );
}

final class QuickjsUiPermissionException implements Exception {
  const QuickjsUiPermissionException({
    required this.pluginId,
    required this.requestedPermissions,
    required this.allowedPermissions,
    required this.grantedPermissions,
    required this.deniedByPolicy,
    required this.missingGrants,
  });

  final String pluginId;
  final Set<String> requestedPermissions;
  final Set<String> allowedPermissions;
  final Set<String> grantedPermissions;
  final Set<String> deniedByPolicy;
  final Set<String> missingGrants;

  @override
  String toString() {
    final details = <String>[];
    if (deniedByPolicy.isNotEmpty) {
      details.add('denied by policy: ${_sorted(deniedByPolicy).join(', ')}');
    }
    if (missingGrants.isNotEmpty) {
      details.add(
        'not granted by mounts: ${_sorted(missingGrants).join(', ')}',
      );
    }
    return 'QuickjsUiPermissionException(plugin: $pluginId, ${details.join('; ')})';
  }
}

bool _setEquals(Set<String> left, Set<String> right) {
  if (left.length != right.length) {
    return false;
  }
  return left.containsAll(right);
}

List<String> _sorted(Set<String> values) => values.toList()..sort();
