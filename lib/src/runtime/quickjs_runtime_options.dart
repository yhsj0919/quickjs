import 'dart:async';
import 'dart:convert';

import 'package:flutter/services.dart';

import '../diagnostics/quickjs_exception.dart';

part '../module/quickjs_essential_host_mount.dart';
part '../module/quickjs_node_host_mount.dart';
part '../module/quickjs_web_host_mount.dart';

/// Loads an ES module source by its normalized module name.
///
/// Relative specifiers are normalized by [Quickjs] before the loader is called,
/// so a loader can use the incoming [moduleName] as its cache key. Returning
/// `null` means the module cannot be resolved.
typedef QuickjsModuleLoader = FutureOr<String?> Function(String moduleName);

/// Callback used by a Dart host provider.
///
/// JavaScript wrappers call providers through a Promise-returning bridge. The
/// callback receives already-converted JavaScript arguments and may return any
/// value supported by the structured value codec.
typedef QuickjsHostProviderCallback =
    FutureOr<Object?> Function(
      List<Object?> args,
      QuickjsHostProviderContext context,
    );

/// Lifecycle context for one async host-provider invocation.
///
/// [cancelled] completes when the owning runtime is stopped, disposed, or
/// rebuilt. Provider implementations that own cancellable work should stop it
/// promptly, then call [throwIfCancelled] before returning a value.
final class QuickjsHostProviderContext {
  /// Creates an invocation context.
  ///
  /// Provider users normally receive this from the runtime rather than
  /// constructing one directly.
  QuickjsHostProviderContext();

  final Completer<void> _cancelled = Completer<void>();
  Object? _cancellationReason;

  /// Completes when this invocation no longer belongs to a live runtime.
  Future<void> get cancelled => _cancelled.future;

  /// Whether the owning runtime has cancelled this invocation.
  bool get isCancelled => _cancelled.isCompleted;

  /// The runtime lifecycle error that caused cancellation, when available.
  Object? get cancellationReason => _cancellationReason;

  /// Throws [cancellationReason] if this invocation has been cancelled.
  void throwIfCancelled() {
    final reason = _cancellationReason;
    if (reason != null) {
      throw reason;
    }
  }

  /// Cancels this invocation with [reason]. Repeated calls are ignored.
  void cancel(Object reason) {
    if (_cancelled.isCompleted) {
      return;
    }
    _cancellationReason = reason;
    _cancelled.complete();
  }
}

/// Browser-like global aliases that can be explicitly installed into a runtime.
final class QuickjsBrowserGlobals {
  const QuickjsBrowserGlobals({this.window = false, this.self = false});

  /// Installs `globalThis.window = globalThis` when true.
  final bool window;

  /// Installs `globalThis.self = globalThis` when true.
  final bool self;

  bool get isEmpty => !window && !self;
}

/// Optional host capabilities exposed to JavaScript.
///
/// Capabilities are opt-in so a runtime does not expose browser or platform
/// objects unless the caller explicitly asks for them.
final class QuickjsHostCapabilities {
  const QuickjsHostCapabilities({
    this.browserGlobals = const QuickjsBrowserGlobals(),
  });

  /// No extra host capabilities.
  static const none = QuickjsHostCapabilities();

  /// Browser-like aliases for code that checks `window` or `self`.
  final QuickjsBrowserGlobals browserGlobals;

  bool get isEmpty => browserGlobals.isEmpty;
}

/// Startup/bootstrap JavaScript installed into every freshly-created runtime.
///
/// Host scripts are evaluated after the built-in console and explicit host
/// capabilities are installed. They are also re-evaluated if the runtime is
/// rebuilt after `stop()`. Use them for opt-in globals or polyfills such as
/// `crypto`, `Buffer`, `location`, or other application-specific objects.
final class QuickjsHostScript {
  const QuickjsHostScript.js({
    required this.name,
    required this.source,
    this.globals = const <String>[],
  });

  factory QuickjsHostScript.providerGlobals({
    required String name,
    required Map<String, String> globals,
  }) {
    final entries = globals.entries.map((entry) {
      final globalName = _validateHostScriptGlobalName(entry.key);
      final providerName = _validateHostScriptProviderName(entry.value);
      return '''
globalThis[${jsonEncode(globalName)}] = (...args) =>
  globalThis.__quickjsHostProviders[${jsonEncode(providerName)}](...args);
''';
    }).join();
    return QuickjsHostScript.js(
      name: name,
      source: entries,
      globals: List<String>.unmodifiable(globals.keys),
    );
  }

  static Future<QuickjsHostScript> asset({
    required String name,
    required String assetKey,
    AssetBundle? bundle,
    List<String> globals = const <String>[],
  }) async {
    return QuickjsHostScript.js(
      name: name,
      source: await (bundle ?? rootBundle).loadString(assetKey),
      globals: globals,
    );
  }

  /// Source name used in QuickJS stack traces.
  final String name;

  /// JavaScript source to evaluate in the runtime.
  final String source;

  /// Global names installed by this script.
  ///
  /// Mount validation rejects duplicate declared globals before rebuilding a
  /// runtime. Scripts that do not install globals may leave this empty.
  final List<String> globals;
}

String _validateHostScriptGlobalName(String name) {
  final isIdentifier = RegExp(r'^[A-Za-z_$][A-Za-z0-9_$]*$').hasMatch(name);
  if (!isIdentifier) {
    throw JsValueConversionException(
      'QuickJS host script global name must be a JavaScript identifier: $name',
    );
  }
  return name;
}

String _validateHostScriptProviderName(String name) {
  if (name.isEmpty) {
    throw JsValueConversionException(
      'QuickJS host script provider name must not be empty',
    );
  }
  if (name.contains('\u0000')) {
    throw JsValueConversionException(
      'QuickJS host script provider name must not contain NUL',
    );
  }
  return name;
}

/// JavaScript module source explicitly registered with a runtime.
///
/// ES modules are loaded when JavaScript imports [specifier]. CommonJS modules
/// are loaded when JavaScript requires [specifier] through [Quickjs.evalCommonJs].
final class QuickjsHostModule {
  const QuickjsHostModule({
    required this.specifier,
    required this.source,
    this.format = QuickjsHostModuleFormat.esModule,
  });

  /// Creates an ES module host module.
  const QuickjsHostModule.esModule({
    required String specifier,
    required String source,
  }) : this(
         specifier: specifier,
         source: source,
         format: QuickjsHostModuleFormat.esModule,
       );

  /// Creates a CommonJS host module.
  const QuickjsHostModule.commonJs({
    required String specifier,
    required String source,
  }) : this(
         specifier: specifier,
         source: source,
         format: QuickjsHostModuleFormat.commonJs,
       );

  /// Module specifier used by `import` or `require`.
  final String specifier;

  /// JavaScript source for the module.
  final String source;

  /// Module format.
  final QuickjsHostModuleFormat format;
}

/// Supported host module source formats.
enum QuickjsHostModuleFormat {
  /// ES module source for `import` / dynamic `import()`.
  esModule,

  /// CommonJS source for `require()`.
  commonJs,
}

/// Host function implementation available to startup scripts or host modules.
///
/// Providers are intentionally not exposed as user-facing globals by
/// themselves. A startup script or host module should wrap a provider into the
/// desired JavaScript API shape, such as `fetch()` or `crypto.subtle.digest()`.
final class QuickjsHostProvider {
  const QuickjsHostProvider.dart({
    required this.name,
    required this.callback,
    this.debugName,
    this.globalName,
    this.implementation = QuickjsHostProviderImplementation.dart,
  });

  factory QuickjsHostProvider.global({
    required String name,
    required QuickjsHostProviderCallback callback,
    String? debugName,
    QuickjsHostProviderImplementation implementation =
        QuickjsHostProviderImplementation.dart,
  }) {
    final globalName = _validateHostScriptGlobalName(name);
    return QuickjsHostProvider.dart(
      name: 'global.$globalName',
      globalName: globalName,
      debugName: debugName,
      implementation: implementation,
      callback: callback,
    );
  }

  /// Runtime-scoped provider name used by JavaScript wrappers.
  final String name;

  /// Optional readable name for debug snapshots.
  final String? debugName;

  /// Optional global function name installed as a direct wrapper for [name].
  ///
  /// Use this for simple `globalThis.foo(...)` APIs. Leave it null when a
  /// startup script or module needs to expose a richer API shape, such as
  /// `fetch()` or `crypto.subtle.digest()`.
  final String? globalName;

  /// Declared source of the provider implementation.
  ///
  /// This is inspector metadata and does not change callback behavior. All
  /// current providers use the asynchronous callback bridge.
  final QuickjsHostProviderImplementation implementation;

  /// Dart/Flutter implementation. JS receives a Promise for each call.
  ///
  /// The per-call context is cancelled when the runtime stops, is disposed,
  /// or is rebuilt. Await [QuickjsHostProviderContext.cancelled] when the
  /// underlying operation supports cooperative cancellation.
  final QuickjsHostProviderCallback callback;
}

/// Source of a host-provider implementation.
enum QuickjsHostProviderImplementation {
  /// Pure Dart or Flutter code running in the host isolate.
  dart,

  /// A Dart callback backed by a platform API or platform channel.
  platform,

  /// A Dart callback backed by a browser/Web API.
  web,
}

/// Named bundle of environment patches, modules, and host providers.
///
/// A mount installs one composable capability bundle into a runtime.
base class QuickjsHostMount {
  const QuickjsHostMount({
    required this.name,
    this.capabilities = QuickjsHostCapabilities.none,
    this.environmentPatches = const <QuickjsHostScript>[],
    this.modules = const <QuickjsHostModule>[],
    this.providers = const <QuickjsHostProvider>[],
  });

  /// Creates a minimal browser-like global environment.
  ///
  /// This installs `window` / `self` aliases by default plus small
  /// startup-script implementations for `location`, `navigator`, `URL`,
  /// `localStorage`, and `sessionStorage`. It does not install `fetch`, Web
  /// Crypto, DOM APIs, networking, or platform storage.
  factory QuickjsHostMount.web({
    String locationHref = 'about:blank',
    String userAgent = 'QuickJS',
    bool window = true,
    bool self = true,
    bool storage = true,
  }) => _quickjsWebHostMount(
    locationHref: locationHref,
    userAgent: userAgent,
    window: window,
    self: self,
    storage: storage,
  );

  /// Creates a small low-risk host environment for common utility APIs.
  ///
  /// The current essential preset installs `buffer` / `node:buffer` as both an
  /// ES module and a CommonJS module. Set [globalBuffer] to true to also install
  /// `globalThis.Buffer` as a startup global.
  factory QuickjsHostMount.essential({bool globalBuffer = false}) =>
      _quickjsEssentialHostMount(globalBuffer: globalBuffer);

  /// Creates a minimal Node-like module environment.
  ///
  /// This preset installs pure-JS host modules for `buffer`, `crypto`, `path`,
  /// `process`, and `timers`, all available through both bare and `node:`
  /// specifiers.
  /// `Buffer` and `process` are not installed as globals unless explicitly
  /// requested. It does not install Node `fs`, networking, or a full npm
  /// resolver. The `crypto` module is a minimal compatibility subset.
  factory QuickjsHostMount.node({
    bool globalBuffer = false,
    bool globalProcess = false,
    Map<String, String> env = const <String, String>{},
    String platform = 'quickjs',
    String cwd = '/',
  }) => _quickjsNodeHostMount(
    globalBuffer: globalBuffer,
    globalProcess: globalProcess,
    env: env,
    platform: platform,
    cwd: cwd,
  );

  /// Stable name used for conflict detection and debug inspection.
  final String name;

  /// Runtime capabilities installed before environment patches.
  final QuickjsHostCapabilities capabilities;

  /// Ordered scripts that complete the runtime global environment.
  final List<QuickjsHostScript> environmentPatches;

  /// ES module and CommonJS definitions included in this mount.
  final List<QuickjsHostModule> modules;

  /// Dart/Flutter providers included in this mount.
  final List<QuickjsHostProvider> providers;
}

/// Resource and module-loading options used when creating a QuickJS runtime.
final class QuickjsRuntimeOptions {
  const QuickjsRuntimeOptions({
    this.memoryLimitBytes,
    this.stackLimitBytes,
    this.moduleLoader,
    this.hostCapabilities = QuickjsHostCapabilities.none,
    this.environmentPatches = const <QuickjsHostScript>[],
    this.modules = const <QuickjsHostModule>[],
    this.providers = const <QuickjsHostProvider>[],
    this.mounts = const <QuickjsHostMount>[],
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

  /// User-provided JavaScript installed into this runtime at creation time.
  ///
  /// Defaults to an empty list. Scripts are installed in list order.
  final List<QuickjsHostScript> environmentPatches;

  /// User-provided modules available to `import` and `require`.
  ///
  /// Defaults to an empty list. Host module specifiers are runtime-scoped.
  final List<QuickjsHostModule> modules;

  /// User-provided providers available to startup scripts and host modules.
  ///
  /// Providers are installed before [environmentPatches]. They are exposed through the
  /// non-enumerable `globalThis.__quickjsHostProviders` registry and return
  /// Promises when called from JavaScript.
  final List<QuickjsHostProvider> providers;

  /// Named capability bundles installed before direct host configuration.
  final List<QuickjsHostMount> mounts;
}
