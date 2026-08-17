import 'package:flutter/services.dart';

import '../runtime/runtime_options.dart';

/// Creates a [JsModuleLoader] backed by a Flutter [AssetBundle].
///
/// The incoming module name is used as the asset key. For package assets, use
/// Flutter's canonical `packages/<package>/<path>` key.
JsModuleLoader assetModuleLoader({AssetBundle? bundle, String prefix = ''}) {
  final resolvedBundle = bundle ?? rootBundle;
  return (name) {
    final key = prefix.isEmpty ? name : '$prefix$name';
    return resolvedBundle.loadString(key);
  };
}
