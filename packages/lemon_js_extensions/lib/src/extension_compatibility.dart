import 'extension_manifest.dart';

/// 宿主针对一个扩展兼容码定义的接口约束。
///
/// 安装、更新或恢复扩展时，会根据 manifest 的 [compatibilityCode] 选择
/// 对应约束，并检查 Core service、必需公开方法和允许的可选公开方法。
/// 该类型不校验方法参数、返回值、权限、来源或签名。
final class JsExtensionConstraint {
  /// 创建一条扩展接口约束。
  ///
  /// [requiredPublicExports] 必须全部由扩展声明；
  /// [optionalPublicExports] 可以按需声明；两组之外的方法不允许公开。
  JsExtensionConstraint({
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

  /// 与扩展 manifest `compatibilityCode` 精确匹配的宿主接口标识。
  final String compatibilityCode;

  /// 是否要求扩展必须包含 Core service；默认为 `true`。
  final bool requireService;

  /// 扩展必须声明并实际导出的公共方法。
  final Set<String> requiredPublicExports;

  /// 扩展可以选择声明的公共方法。
  final Set<String> optionalPublicExports;

  /// 此约束允许扩展公开的全部方法。
  Set<String> get allowedPublicExports => <String>{
    ...requiredPublicExports,
    ...optionalPublicExports,
  };

  /// 校验 [manifest] 是否满足当前约束。
  ///
  /// 不满足时抛出 [FormatException]。
  void validate(JsExtensionManifest manifest) {
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
}

/// 宿主支持的全部扩展接口约束及其统一校验入口。
///
/// 每个 `compatibilityCode` 只能对应一条 [JsExtensionConstraint]；重复定义会在
/// 创建时立即报错。未知兼容码不会降级处理，而是拒绝安装、更新或恢复该扩展。
final class JsExtensionConstraints {
  /// 按兼容码建立不可变约束集合。
  JsExtensionConstraints(Iterable<JsExtensionConstraint> constraints)
    : _constraints = Map<String, JsExtensionConstraint>.unmodifiable(
        <String, JsExtensionConstraint>{
          for (final constraint in constraints)
            constraint.compatibilityCode: constraint,
        },
      ) {
    if (_constraints.length != constraints.length) {
      throw ArgumentError('Extension constraints contain duplicate codes');
    }
  }

  final Map<String, JsExtensionConstraint> _constraints;

  /// 返回 [code] 对应的约束；宿主不支持该兼容码时抛出 [FormatException]。
  JsExtensionConstraint require(String code) {
    final constraint = _constraints[code];
    if (constraint == null) {
      throw FormatException('Unsupported extension compatibilityCode: $code');
    }
    return constraint;
  }

  /// 查找 manifest 对应的约束并执行校验，成功时返回所使用的约束。
  JsExtensionConstraint validate(JsExtensionManifest manifest) {
    final constraint = require(manifest.compatibilityCode);
    constraint.validate(manifest);
    return constraint;
  }
}
