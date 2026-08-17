import 'package:flutter/services.dart';

import '../runtime/runtime_options.dart';
import 'fetch_features.dart';

const _axiosAsset = 'packages/lemon_js/assets/js/axios.js';

/// 将 Axios 与它所依赖的 Fetch/XHR 宿主能力打包为一个 [JsFeatures]。
///
/// 典型用法：在 [JsUiView] 或 [JsEngine.create] 的 `features` 中传入
/// `AxiosFeatures()`，即可在 JS 侧使用
/// `axios`，无需再单独配置 [FetchFeatures] 和 [JsScript]。
///
/// 默认加载包内 Axios 脚本；传入 [path] 可替换为应用自带版本。
final class AxiosFeatures extends JsFeatures {
  /// 使用共享网络会话创建 Axios features。
  factory AxiosFeatures.session({
    String path = _axiosAsset,
    required JsHttpSession session,
    AssetBundle? bundle,
    String name = 'axios',
    String? scriptName,
  }) => AxiosFeatures._(
    name: name,
    path: path,
    bundle: bundle,
    fetchFeatures: FetchFeatures.session(session),
    scriptName: scriptName ?? path,
  );

  /// 创建 Axios 组合 features。
  ///
  /// - [path]：Axios JavaScript 文件的 asset 路径；默认使用包内版本。
  /// - [bundle]：可选的 asset 读取源；默认使用 [rootBundle]。
  /// - [allowedOrigins]：允许访问的 HTTP(S) 源白名单；`null` 或空表示不限制。
  /// - [timeout]：单次请求超时时间。
  /// - [maxRequestBytes]：请求体最大字节数。
  /// - [maxResponseBytes]：响应体最大字节数。
  /// - [maxRedirects]：单次请求允许跟随的最大重定向次数。
  /// - [defaultHeaders]：注入到每次请求中的默认 HTTP 头。
  /// - [name]：features 在 runtime 中的稳定名称，用于冲突检测与调试。
  /// - [scriptName]：Axios 脚本在 QuickJS 堆栈中的 source 名称；默认等于 [path]。
  factory AxiosFeatures({
    String path = _axiosAsset,
    AssetBundle? bundle,
    Set<String>? allowedOrigins,
    Duration timeout = const Duration(seconds: 30),
    int maxRequestBytes = 1024 * 1024,
    int maxResponseBytes = 10 * 1024 * 1024,
    int maxRedirects = 5,
    Map<String, String> defaultHeaders = const <String, String>{},
    String name = 'axios',
    String? scriptName,
  }) {
    final fetchFeatures = FetchFeatures(
      allowedOrigins: allowedOrigins,
      timeout: timeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      maxRedirects: maxRedirects,
      defaultHeaders: defaultHeaders,
    );
    return AxiosFeatures._(
      name: name,
      path: path,
      bundle: bundle,
      fetchFeatures: fetchFeatures,
      scriptName: scriptName ?? path,
    );
  }

  AxiosFeatures._({
    required super.name,
    required this.path,
    required this.bundle,
    required this.fetchFeatures,
    required String scriptName,
  }) : super(
         scripts: <JsScript>[
           ...fetchFeatures.scripts,
           JsScript.asset(
             name: scriptName,
             path: path,
             bundle: bundle,
             globals: const <String>['axios'],
           ),
         ],
         methods: fetchFeatures.methods,
       );

  /// Axios 脚本所在的 Flutter asset 路径。
  final String path;

  /// 读取 [path] 时使用的 asset bundle；为 `null` 时使用 [rootBundle]。
  final AssetBundle? bundle;

  /// 内部用于实现 `fetch` / `XMLHttpRequest` 的 [FetchFeatures] 实例。
  final FetchFeatures fetchFeatures;
}
