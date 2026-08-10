import 'package:flutter/services.dart';

import '../runtime/quickjs_runtime_options.dart';
import 'quickjs_fetch_mount.dart';

/// 将 Axios 与它所依赖的 Fetch/XHR 宿主能力打包为一个 [QuickjsHostMount]。
///
/// 典型用法：在 [QuickjsUiView] 或 [Quickjs.create] 的 `mounts` 中传入
/// `QuickjsAxiosMount(assetKey: 'assets/js/axios.js')`，即可在 JS 侧使用
/// `axios`，无需再单独配置 [QuickjsFetchMount] 和 [QuickjsHostScript]。
///
/// [assetKey] 为必填项，用于指定要加载的 Axios 脚本所在 Flutter asset 路径。
final class QuickjsAxiosMount extends QuickjsHostMount {
  /// 创建 Axios 组合 mount。
  ///
  /// - [assetKey]：Axios JavaScript 文件的 asset 路径（必填）。
  /// - [bundle]：可选的 asset 读取源；默认使用 [rootBundle]。
  /// - [allowedOrigins]：允许访问的 HTTP(S) 源白名单；`null` 或空表示不限制。
  /// - [timeout]：单次请求超时时间。
  /// - [maxRequestBytes]：请求体最大字节数。
  /// - [maxResponseBytes]：响应体最大字节数。
  /// - [maxRedirects]：单次请求允许跟随的最大重定向次数。
  /// - [defaultHeaders]：注入到每次请求中的默认 HTTP 头。
  /// - [name]：mount 在 runtime 中的稳定名称，用于冲突检测与调试。
  /// - [scriptName]：Axios 脚本在 QuickJS 堆栈中的 source 名称；默认等于 [assetKey]。
  factory QuickjsAxiosMount({
    required String assetKey,
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
    final fetchMount = QuickjsFetchMount(
      allowedOrigins: allowedOrigins,
      timeout: timeout,
      maxRequestBytes: maxRequestBytes,
      maxResponseBytes: maxResponseBytes,
      maxRedirects: maxRedirects,
      defaultHeaders: defaultHeaders,
    );
    return QuickjsAxiosMount._(
      name: name,
      assetKey: assetKey,
      bundle: bundle,
      fetchMount: fetchMount,
      scriptName: scriptName ?? assetKey,
    );
  }

  QuickjsAxiosMount._({
    required super.name,
    required this.assetKey,
    required this.bundle,
    required this.fetchMount,
    required String scriptName,
  }) : super(
         environmentPatches: <QuickjsHostScript>[
           ...fetchMount.environmentPatches,
           QuickjsHostScript.asset(
             name: scriptName,
             assetKey: assetKey,
             bundle: bundle,
             globals: const <String>['axios'],
           ),
         ],
         providers: fetchMount.providers,
       );

  /// Axios 脚本所在的 Flutter asset 路径。
  final String assetKey;

  /// 读取 [assetKey] 时使用的 asset bundle；为 `null` 时使用 [rootBundle]。
  final AssetBundle? bundle;

  /// 内部用于实现 `fetch` / `XMLHttpRequest` 的 [QuickjsFetchMount] 实例。
  final QuickjsFetchMount fetchMount;
}
