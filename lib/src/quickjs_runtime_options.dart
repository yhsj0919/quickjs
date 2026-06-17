import 'dart:async';

/// Loads an ES module source by its normalized module name.
///
/// Relative specifiers are normalized by [Quickjs] before the loader is called,
/// so a loader can use the incoming [moduleName] as its cache key. Returning
/// `null` means the module cannot be resolved.
typedef QuickjsModuleLoader = FutureOr<String?> Function(String moduleName);

/// Browser-like global aliases that can be explicitly installed into a runtime.
final class QuickjsBrowserGlobals {
  const QuickjsBrowserGlobals({this.window = false, this.self = false});

  /// Installs `globalThis.window = globalThis` when true.
  final bool window;

  /// Installs `globalThis.self = globalThis` when true.
  final bool self;

  bool get isEmpty => !window && !self;
}

/// Minimal `crypto` APIs that can be explicitly installed into a runtime.
final class QuickjsCryptoCapabilities {
  const QuickjsCryptoCapabilities({this.randomUUID = false});

  /// Installs `crypto.randomUUID()`.
  final bool randomUUID;

  bool get isEmpty => !randomUUID;
}

/// Optional host capabilities exposed to JavaScript.
///
/// Capabilities are opt-in so a runtime does not expose browser or platform
/// objects unless the caller explicitly asks for them.
final class QuickjsHostCapabilities {
  const QuickjsHostCapabilities({
    this.browserGlobals = const QuickjsBrowserGlobals(),
    this.crypto = const QuickjsCryptoCapabilities(),
  });

  /// No extra host capabilities.
  static const none = QuickjsHostCapabilities();

  /// Browser-like aliases for code that checks `window` or `self`.
  final QuickjsBrowserGlobals browserGlobals;

  /// Minimal Web Crypto-compatible APIs.
  final QuickjsCryptoCapabilities crypto;

  bool get isEmpty => browserGlobals.isEmpty && crypto.isEmpty;
}

/// Resource and module-loading options used when creating a QuickJS runtime.
final class QuickjsRuntimeOptions {
  const QuickjsRuntimeOptions({
    this.memoryLimitBytes,
    this.stackLimitBytes,
    this.moduleLoader,
    this.hostCapabilities = QuickjsHostCapabilities.none,
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

  /// Explicit host capabilities installed into this runtime.
  ///
  /// Defaults to [QuickjsHostCapabilities.none].
  final QuickjsHostCapabilities hostCapabilities;
}
