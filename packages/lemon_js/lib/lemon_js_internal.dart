/// Internal integration API shared by Lemon JS packages and package tests.
library;

export 'lemon_js.dart';

import 'src/runtime/plugin.dart';
import 'src/runtime/runtime_options.dart';

/// Internal conversion used by packages that compose plugins into feature slots.
extension JsPluginInternalFeatures on JsPlugin {
  /// 将插件转换为运行时组合层使用的 [JsFeatures]。
  JsFeatures asFeatures({String? name}) =>
      createPluginFeatures(this, name: name);
}
