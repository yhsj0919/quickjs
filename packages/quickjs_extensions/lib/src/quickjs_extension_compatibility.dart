import 'quickjs_extension.dart';
import 'quickjs_extension_manifest.dart';

/// 一个兼容码允许的 Extension 能力集合。
final class QuickjsExtensionCompatibilityPolicy {
  QuickjsExtensionCompatibilityPolicy({
    required this.compatibilityCode,
    this.requireService = true,
    Iterable<String> requiredPublicExports = const <String>[],
    Iterable<String> optionalPublicExports = const <String>[],
  }) : requiredPublicExports = Set<String>.unmodifiable(requiredPublicExports),
       optionalPublicExports = Set<String>.unmodifiable(optionalPublicExports) {
    if (compatibilityCode.trim().isEmpty) {
      throw ArgumentError.value(
        compatibilityCode,
        'compatibilityCode',
        'must not be empty',
      );
    }
    final overlap = this.requiredPublicExports.intersection(
      this.optionalPublicExports,
    );
    if (overlap.isNotEmpty) {
      throw ArgumentError(
        'Required and optional public exports overlap: ${overlap.join(', ')}',
      );
    }
  }

  final String compatibilityCode;
  final bool requireService;
  final Set<String> requiredPublicExports;
  final Set<String> optionalPublicExports;

  Set<String> get allowedPublicExports => <String>{
    ...requiredPublicExports,
    ...optionalPublicExports,
  };

  void validate(QuickjsExtensionManifest manifest) {
    if (manifest.compatibilityCode != compatibilityCode) {
      throw FormatException(
        'Extension compatibilityCode does not match $compatibilityCode',
      );
    }
    final service = manifest.service;
    if (requireService && service == null) {
      throw FormatException(
        'Extension $compatibilityCode requires a Core service',
      );
    }
    if (service == null) return;
    final declared = service.publicExports.toSet();
    final missing = requiredPublicExports.difference(declared);
    if (missing.isNotEmpty) {
      throw FormatException(
        'Extension is missing required public exports: ${missing.join(', ')}',
      );
    }
    final unknown = declared.difference(allowedPublicExports);
    if (unknown.isNotEmpty) {
      throw FormatException(
        'Extension declares unsupported public exports: ${unknown.join(', ')}',
      );
    }
  }

  bool supports(QuickjsExtension extension, String method) =>
      extension.service?.publicExports.contains(method) ?? false;
}

/// 宿主允许安装的兼容码注册表。
final class QuickjsExtensionCompatibilityRegistry {
  QuickjsExtensionCompatibilityRegistry(
    Iterable<QuickjsExtensionCompatibilityPolicy> policies,
  ) : _policies = Map<String, QuickjsExtensionCompatibilityPolicy>.unmodifiable(
        <String, QuickjsExtensionCompatibilityPolicy>{
          for (final policy in policies) policy.compatibilityCode: policy,
        },
      ) {
    if (_policies.length != policies.length) {
      throw ArgumentError('Compatibility policies contain duplicate codes');
    }
  }

  final Map<String, QuickjsExtensionCompatibilityPolicy> _policies;

  QuickjsExtensionCompatibilityPolicy require(String code) {
    final policy = _policies[code];
    if (policy == null) {
      throw FormatException('Unsupported extension compatibilityCode: $code');
    }
    return policy;
  }

  QuickjsExtensionCompatibilityPolicy validate(
    QuickjsExtensionManifest manifest,
  ) {
    final policy = require(manifest.compatibilityCode);
    policy.validate(manifest);
    return policy;
  }
}
