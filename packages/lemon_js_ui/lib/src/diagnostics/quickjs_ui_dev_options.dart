import 'package:flutter/foundation.dart';

/// Development-time options for quickjs_ui pages.
///
/// Controls error overlay visibility, reload behavior, and diagnostic logging.
final class JsUiDevOptions {
  /// 创建一组页面开发期诊断选项。
  const JsUiDevOptions({
    this.showErrorOverlay = true,
    this.preserveStateOnReload = false,
    this.logSchema = false,
    this.logDiff = false,
    this.logResources = false,
  });

  /// Shows [JsUiErrorOverlay] for runtime/schema errors when no custom
  /// [JsUiErrorBuilder] is provided.
  final bool showErrorOverlay;

  /// Keeps the current JS page state when [JsUiController.reload] runs.
  final bool preserveStateOnReload;

  /// Logs the current UI schema after each successful render.
  final bool logSchema;

  /// Logs renderer diff statistics after each build pass.
  final bool logDiff;

  /// Logs network/resource loader events.
  final bool logResources;

  /// Convenient defaults for local debugging.
  static const JsUiDevOptions debug = JsUiDevOptions(
    logDiff: true,
    logSchema: false,
    logResources: true,
  );

  /// Production-safe defaults.
  static const JsUiDevOptions release = JsUiDevOptions();

  /// Debug-mode defaults used when callers do not pass explicit options.
  static JsUiDevOptions get defaults => kDebugMode ? debug : release;
}
