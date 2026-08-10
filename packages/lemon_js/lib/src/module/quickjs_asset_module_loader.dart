import 'package:flutter/services.dart';

import '../runtime/quickjs_runtime_options.dart';

/// Creates a [QuickjsModuleLoader] backed by a Flutter [AssetBundle].
///
/// The incoming module name is used as the asset key. For package assets, use
/// Flutter's canonical `packages/<package>/<path>` key.
QuickjsModuleLoader quickjsAssetModuleLoader({
  AssetBundle? bundle,
  String prefix = '',
}) {
  final resolvedBundle = bundle ?? rootBundle;
  return (moduleName) {
    final key = prefix.isEmpty ? moduleName : '$prefix$moduleName';
    return resolvedBundle.loadString(key);
  };
}
