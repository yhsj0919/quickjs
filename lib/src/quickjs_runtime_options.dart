import 'dart:async';

/// Loads an ES module source by its normalized module name.
///
/// Relative specifiers are normalized by [Quickjs] before the loader is called,
/// so a loader can use the incoming [moduleName] as its cache key. Returning
/// `null` means the module cannot be resolved.
typedef QuickjsModuleLoader = FutureOr<String?> Function(String moduleName);

/// Resource and module-loading options used when creating a QuickJS runtime.
final class QuickjsRuntimeOptions {
  const QuickjsRuntimeOptions({
    this.memoryLimitBytes,
    this.stackLimitBytes,
    this.moduleLoader,
  });

  /// Maximum memory for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Exceeding the limit is reported as
  /// `JsOutOfMemoryException` by the public API.
  final int? memoryLimitBytes;

  /// Maximum native call stack for a single runtime, in bytes.
  ///
  /// `null` keeps the QuickJS default. Native uses `JS_SetMaxStackSize`; the
  /// current web backend does not expose an equivalent WASM option yet.
  final int? stackLimitBytes;

  /// Runtime-scoped ES module source loader.
  ///
  /// [Quickjs.evalModule] uses this loader to prebuild the dependency graph
  /// before sending a module evaluation request to the native isolate or web
  /// worker.
  final QuickjsModuleLoader? moduleLoader;
}
