import 'package:flutter/foundation.dart';

/// Development-time options for quickjs_ui pages.
///
/// Controls error overlay visibility, reload behavior, and diagnostic logging.
final class QuickjsUiDevOptions {
  const QuickjsUiDevOptions({
    this.showErrorOverlay = true,
    this.preserveStateOnReload = false,
    this.logSchema = false,
    this.logDiff = false,
    this.logResources = false,
  });

  /// Shows [QuickjsUiErrorOverlay] for runtime/schema errors when no custom
  /// [QuickjsUiErrorBuilder] is provided.
  final bool showErrorOverlay;

  /// Keeps the current JS page state when [QuickjsUiController.reload] runs.
  final bool preserveStateOnReload;

  /// Logs the current UI schema after each successful render.
  final bool logSchema;

  /// Logs renderer diff statistics after each build pass.
  final bool logDiff;

  /// Logs network/resource loader events.
  final bool logResources;

  /// Convenient defaults for local debugging.
  static const QuickjsUiDevOptions debug = QuickjsUiDevOptions(
    logDiff: true,
    logSchema: false,
    logResources: true,
  );

  /// Production-safe defaults.
  static const QuickjsUiDevOptions release = QuickjsUiDevOptions();

  /// Debug-mode defaults used when callers do not pass explicit options.
  static QuickjsUiDevOptions get defaults =>
      kDebugMode ? debug : release;
}
