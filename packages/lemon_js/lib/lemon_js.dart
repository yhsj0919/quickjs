// lemon_js 包的公开导出入口。
///
/// 常用 features：
/// - [FetchFeatures]：注入 Fetch API。
/// - [AxiosFeatures]：组合 Fetch 与 Axios 脚本。
library;

export 'src/runtime/engine.dart' hide createJsContextEngine, createTestJsEngine;
export 'src/module/asset_module_loader.dart';
export 'src/diagnostics/exception.dart' hide parseJsExceptionPayload;
export 'src/runtime/plugin.dart' hide JsPluginFeatures, createPluginFeatures;
export 'src/runtime/plugin_tools.dart';
export 'src/runtime/zip_plugin.dart';
export 'src/runtime/runtime_options.dart';
export 'src/diagnostics/source_map.dart';
export 'src/runtime/value.dart';
export 'src/module/web_crypto_features.dart';
export 'src/module/fetch_features.dart';
export 'src/module/axios_features.dart';
export 'src/module/key_value_storage.dart';
export 'src/module/websocket_features.dart';
