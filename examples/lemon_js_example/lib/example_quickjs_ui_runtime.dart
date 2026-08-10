import 'package:lemon_js_ui/lemon_js_ui.dart';

/// Application-scoped QuickJS UI runtime used by examples that demonstrate
/// one preheated runtime hosting isolated dynamic page contexts.
///
/// The runtime intentionally outlives individual routes. Every page owns a
/// short-lived context; disposing a route releases that context while keeping
/// the native worker and JSRuntime warm.
final QuickjsUiRuntime exampleQuickjsUiRuntime = QuickjsUiRuntime(
  maxCapacity: 2,
);

/// Initializes the shared runtime before Flutter builds the first application
/// frame, keeping native worker startup out of the counter page timing.
Future<void> initExampleQuickjsUiRuntime() {
  return exampleQuickjsUiRuntime.init();
}
