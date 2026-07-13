import 'dart:async';
import 'dart:collection';

// ignore_for_file: prefer_initializing_formals

import 'package:quickjs/quickjs.dart';

import '../diagnostics/quickjs_ui_error.dart';
import '../diagnostics/quickjs_ui_inspector.dart';
import '../diagnostics/quickjs_ui_load_metrics.dart';
import '../host/quickjs_ui_permission_policy.dart';
import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_helpers.dart';
import 'quickjs_ui_runtime.dart';

const int _quickjsUiStackLimitBytes = 1024 * 1024;
const int _minimumSupportedQuickjsUiSchemaVersion = 1;
const int _maximumSupportedQuickjsUiSchemaVersion = quickjsUiSchemaVersion;
const int _currentQuickjsUiRuntimeVersion = 1;
const String _quickjsUiPageMountSlot = 'quickjs_ui:page';

final class QuickjsUiSession {
  static final Expando<Object> _attachedEngineLeases = Expando<Object>(
    'quickjs_ui attached engine lease',
  );

  // Keep the public constructor parameters named `engine` and `onConsole`.
  QuickjsUiSession({
    Quickjs? engine,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    QuickjsUiInspector? inspector,
  }) : assert(engine == null || runtime == null),
       _runtime = runtime,
       _engineBinding = engine == null
           ? null
           : _QuickjsUiEngineBinding.attached(engine),
       _onConsole = onConsole,
       inspector = inspector {
    if (engine != null) {
      _claimAttachedEngine(engine);
    }
  }

  _QuickjsUiEngineBinding? _engineBinding;
  final QuickjsUiRuntime? _runtime;
  final QuickjsConsoleSink? _onConsole;
  QuickjsUiInspector? inspector;
  _QuickjsUiPageBinding? _pageBinding;
  Object? _state;
  QuickjsUiNode? _node;
  QuickjsUiLoadMetrics? _lastLoadMetrics;
  final Object _engineLease = Object();
  bool _disposed = false;
  Future<void>? _disposeFuture;
  bool _disposeLifecycleSent = false;
  int _activeCalls = 0;
  final _SessionOperationScheduler _scheduler = _SessionOperationScheduler();

  Quickjs? get engine => _engineBinding?.engine;
  QuickjsContext? get context => _engineBinding?.context;
  QuickjsPlugin? get plugin => _pageBinding?.plugin;
  Map<String, Object?> get props =>
      _pageBinding?.props ?? const <String, Object?>{};
  List<QuickjsHostMount> get mounts =>
      _pageBinding?.mounts ?? const <QuickjsHostMount>[];
  Set<String> get grantedPermissions =>
      _pageBinding?.grantedPermissions ?? const <String>{};
  QuickjsUiPermissionPolicy? get permissionPolicy =>
      _pageBinding?.permissionPolicy;
  Object? get state => _state;
  QuickjsUiNode? get node => _node;
  QuickjsUiLoadMetrics? get lastLoadMetrics => _lastLoadMetrics;
  bool get isDisposed => _disposed;

  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
  }) async {
    return _enqueue(() async {
      final total = Stopwatch()..start();
      final stages = <String, Duration>{};
      var lap = Duration.zero;
      void record(String name) {
        final elapsed = total.elapsed;
        stages[name] = elapsed - lap;
        lap = elapsed;
      }

      _ensureActive();
      permissionPolicy?.validate(
        plugin: plugin,
        grantedPermissions: grantedPermissions,
      );
      final requestedMounts = List<QuickjsHostMount>.unmodifiable(mounts);
      final host = await _hostForPage(requestedMounts);
      record('runtimeAcquire');
      if (_disposed) {
        if (_engineBinding?.ownsEngine == true) {
          unawaited(_disposeHost(host));
        }
        return;
      }
      await _closeCurrentPage();
      record('pageCleanup');
      if (_disposed) {
        return;
      }
      await _mountPagePlugin(host, plugin);
      record('pluginMount');
      if (_disposed) {
        return;
      }
      _disposeLifecycleSent = false;
      final page = _QuickjsUiPageBinding(
        plugin: plugin,
        client: QuickjsPluginClient(host, plugin),
        props: Map<String, Object?>.unmodifiable(initialProps),
        mounts: requestedMounts,
        grantedPermissions: Set<String>.unmodifiable(grantedPermissions),
        permissionPolicy: permissionPolicy,
      );
      _pageBinding = page;
      try {
        if (plugin.manifest.exports.contains('bootstrap')) {
          _validateRuntimeManifest(plugin);
          final bootstrap = await _clientCall('bootstrap', <Object?>[
            page.props,
          ]);
          record('bootstrap');
          if (_disposed) return;
          _applyBootstrapResult(page, bootstrap);
        } else {
          await page.client.validate();
          record('validate');
          page.lifecycleTypes = await _loadLegacyLifecycleTypes(
            page.client,
            plugin,
          );
          record('capabilities');
          final initialSnapshot = await _clientCall('mount', <Object?>[
            page.props,
          ]);
          record('stateMount');
          if (_disposed) return;
          _applySnapshot(initialSnapshot);
          await _refreshImpl();
          record('firstCommit');
        }
        inspector?.recordLifecycle('widget', 'load');
        _lastLoadMetrics = QuickjsUiLoadMetrics(
          stages: Map<String, Duration>.unmodifiable(stages),
          totalToSchema: total.elapsed,
        );
      } catch (_) {
        if (identical(_pageBinding, page)) {
          _clearPageBinding();
        }
        rethrow;
      }
    });
  }

  Future<QuickjsPluginHost> _hostForPage(
    List<QuickjsHostMount> requestedMounts,
  ) async {
    final currentBinding = _engineBinding;
    if (currentBinding == null) {
      final runtime = _runtime;
      if (runtime != null) {
        final lease = await runtime.acquire(mounts: requestedMounts);
        _engineBinding = _QuickjsUiEngineBinding.leased(lease, requestedMounts);
        return lease.context;
      }
      final created = await _createOwnedEngine(requestedMounts);
      _engineBinding = _QuickjsUiEngineBinding.owned(created, requestedMounts);
      return created;
    }
    final current = currentBinding.host;
    final currentLease = currentBinding.runtimeLease;
    if (currentLease != null) {
      // ES module instances cannot be replaced inside one JSContext. Dynamic
      // page reload therefore releases the old context and creates a fresh one
      // while retaining the shared worker/JSRuntime.
      await _closeCurrentPage();
      _engineBinding = null;
      await currentLease.release();
      final replacement = await _runtime!.acquire(mounts: requestedMounts);
      _engineBinding = _QuickjsUiEngineBinding.leased(
        replacement,
        requestedMounts,
      );
      return replacement.context;
    }
    if (!currentBinding.ownsEngine) {
      if (requestedMounts.isNotEmpty) {
        throw StateError(
          'QuickjsUiSession cannot install host mounts on an attached engine; '
          'configure the Quickjs engine before attaching it',
        );
      }
      await _ensureHelperModuleMounted(currentBinding.engine!);
      return currentBinding.engine!;
    }
    if (_sameMountConfiguration(currentBinding.mounts, requestedMounts)) {
      return current;
    }

    await _closeCurrentPage();
    _engineBinding = null;
    await _disposeHost(current);
    final replacement = await _createOwnedEngine(requestedMounts);
    _engineBinding = _QuickjsUiEngineBinding.owned(
      replacement,
      requestedMounts,
    );
    return replacement;
  }

  Future<Quickjs> _createOwnedEngine(List<QuickjsHostMount> mounts) {
    return Quickjs.create(
      onConsole: _onConsole,
      options: QuickjsRuntimeOptions(
        stackLimitBytes: _quickjsUiStackLimitBytes,
        mounts: <QuickjsHostMount>[quickjsUiHelperMount, ...mounts],
      ),
    );
  }

  Future<void> _mountPagePlugin(QuickjsPluginHost host, QuickjsPlugin plugin) {
    final mount = plugin.asMount(name: _quickjsUiPageMountSlot);
    return switch (host) {
      QuickjsContext context => context.mount(
        mount,
        conflictPolicy: QuickjsHostMountConflictPolicy.replace,
      ),
      Quickjs engine => engine.mount(
        mount,
        conflictPolicy: QuickjsHostMountConflictPolicy.replace,
      ),
      _ => throw StateError('Unsupported QuickJS UI plugin host'),
    };
  }

  Future<void> _disposeHost(QuickjsPluginHost host) {
    return switch (host) {
      QuickjsContext context => context.dispose(),
      Quickjs engine => engine.dispose(),
      _ => Future<void>.value(),
    };
  }

  Future<void> _closeCurrentPage() async {
    final page = _pageBinding;
    if (page == null) {
      return;
    }
    _clearPageBinding();
    await _runCleanupStep(
      () => _sendDisposeLifecycle(
        page.client,
        page.plugin,
        lifecycleTypes: page.lifecycleTypes,
      ),
    );
    await _runCleanupStep(() async {
      await _clientCallWith(page.client, 'dispose', const <Object?>[]);
    });
    if (page.plugin.manifest.dispose != null) {
      await _runCleanupStep(() async {
        await page.client.dispose();
      });
    }
  }

  void _clearPageBinding({bool clearSnapshot = true}) {
    _pageBinding = null;
    _disposeLifecycleSent = false;
    if (clearSnapshot) {
      _state = null;
      _node = null;
    }
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    return dispatchBatch(<Map<String, Object?>>[event]);
  }

  /// Dispatches a burst of events through one session operation and performs
  /// one state sync and one renderer refresh after the whole burst completes.
  /// Event handlers still execute in input order inside QuickJS.
  Future<void> dispatchBatch(Iterable<Map<String, Object?>> events) async {
    final batch = List<Map<String, Object?>>.unmodifiable(events);
    if (batch.isEmpty) {
      return;
    }
    return _enqueue(() async {
      _ensureActive();
      var changed = false;
      for (final event in batch) {
        inspector?.recordAction(event);
        final result = await _clientCall('handleEvent', <Object?>[event]);
        changed = _resultChanged(result) || changed;
      }
      if (!changed || _disposed) {
        return;
      }
      await _syncStateFromJs();
      await _refreshImpl();
    });
  }

  Future<void> setState(Map<String, Object?> patch) async {
    return _enqueue(() async {
      _ensureActive();
      final result = await _clientCall('setState', <Object?>[patch]);
      await _commitCallResult(result);
    });
  }

  Future<bool> lifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) async {
    return _enqueue(() async {
      return _lifecycleImpl(type, payload: payload, render: render);
    });
  }

  Future<bool> routeLifecycle(
    String type, {
    Object? payload,
    bool render = true,
  }) {
    return _enqueue(() async {
      return _lifecycleImpl(
        type,
        payload: payload,
        render: render,
        phase: 'route',
      );
    });
  }

  Future<void> refresh() {
    return _enqueue(_refreshImpl);
  }

  Future<void> pumpTimers() {
    return _enqueue(() async {
      _ensureActive();
      final binding = _engineBinding;
      if (binding == null || _pageBinding == null) {
        return;
      }
      final context = binding.context;
      if (context != null) {
        await context.evalAsync(
          'new Promise((resolve) => setTimeout(() => resolve(null), 0))',
          name: '<quickjs_ui_timer_pump>',
          timeout: const Duration(milliseconds: 250),
        );
      } else {
        await binding.engine!.evalAsync(
          'await new Promise((resolve) => setTimeout(resolve, 0)); return null;',
          name: '<quickjs_ui_timer_pump>',
          timeout: const Duration(milliseconds: 250),
        );
      }
      if (_disposed) {
        return;
      }
      await _syncStateFromJs();
      await _refreshImpl();
    });
  }

  Future<void> _refreshImpl() async {
    return _refreshImplMeasured();
  }

  Future<void> _refreshImplMeasured() async {
    _ensureActive();
    final result = await _clientCall('commit', const <Object?>[]);
    if (_disposed) {
      return;
    }
    if (result is Map && result['changed'] == false) {
      return;
    }
    _applyCommitResult(result);
  }

  void _applyCommitResult(Object? result) {
    final rendered = result is Map ? result['node'] : result;
    if (rendered is! Map) {
      throw const FormatException(
        'quickjs_ui commit() must return a UI node object',
      );
    }
    _node = QuickjsUiNode.fromMap(
      rendered.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
    inspector?.recordSchema(_node!.toMap());
  }

  Future<void> reload() async {
    _ensureActive();
    final page = _pageBinding;
    if (page == null) {
      return;
    }
    await loadPlugin(
      page.plugin,
      initialProps: page.props,
      mounts: page.mounts,
      grantedPermissions: page.grantedPermissions,
      permissionPolicy: page.permissionPolicy,
    );
  }

  /// Binds one externally owned engine before this session loads a page.
  ///
  /// A session cannot switch engines. The attached engine remains exclusively
  /// leased to this session until [dispose] completes.
  void attach(Quickjs engine) {
    _ensureActive();
    final current = _engineBinding?.engine;
    if (identical(current, engine)) {
      return;
    }
    if (current != null || _pageBinding != null) {
      throw StateError(
        'QuickjsUiSession.attach() is only valid before an engine is bound '
        'or a page is loaded',
      );
    }
    _claimAttachedEngine(engine);
    _engineBinding = _QuickjsUiEngineBinding.attached(engine);
  }

  /// Terminates this page session and waits for runtime cleanup.
  ///
  /// If the session owns its engine, the engine is closed. If it uses an
  /// attached engine and a call is active, the engine is stopped to cancel the
  /// call and rebuilt before this future completes, so its owner may reuse it.
  Future<void> dispose() {
    final currentDispose = _disposeFuture;
    if (currentDispose != null) {
      return currentDispose;
    }
    final page = _pageBinding;
    final engineBinding = _engineBinding;
    final engine = engineBinding?.engine;
    final ownsEngine = engineBinding?.ownsEngine ?? false;
    final runtimeLease = engineBinding?.runtimeLease;
    final hasActiveCalls = _activeCalls > 0;
    _disposed = true;
    _clearPageBinding(clearSnapshot: false);
    _engineBinding = null;
    if (hasActiveCalls) {
      return _disposeFuture = _releaseEngineAfter(
        _cancelActiveRuntime(engine, ownsEngine: ownsEngine),
        engine: engine,
        ownsEngine: ownsEngine,
        runtimeLease: runtimeLease,
      );
    }
    return _disposeFuture = _releaseEngineAfter(
      _disposeIdleRuntime(
        client: page?.client,
        plugin: page?.plugin,
        lifecycleTypes: page?.lifecycleTypes ?? const <String>{},
        engine: engine,
        ownsEngine: ownsEngine,
      ),
      engine: engine,
      ownsEngine: ownsEngine,
      runtimeLease: runtimeLease,
    );
  }

  Future<void> _releaseEngineAfter(
    Future<void> cleanup, {
    required Quickjs? engine,
    required bool ownsEngine,
    QuickjsUiRuntimeLease? runtimeLease,
  }) async {
    try {
      await cleanup;
    } finally {
      if (runtimeLease != null) {
        await runtimeLease.release();
      } else if (engine != null && !ownsEngine) {
        _releaseAttachedEngine(engine);
      }
    }
  }

  void _claimAttachedEngine(Quickjs engine) {
    final current = _attachedEngineLeases[engine];
    if (current != null && !identical(current, _engineLease)) {
      throw StateError(
        'QuickjsUiSession requires exclusive access to an attached Quickjs '
        'engine until dispose() completes',
      );
    }
    _attachedEngineLeases[engine] = _engineLease;
  }

  void _releaseAttachedEngine(Quickjs engine) {
    if (identical(_attachedEngineLeases[engine], _engineLease)) {
      _attachedEngineLeases[engine] = null;
    }
  }

  Future<void> _disposeIdleRuntime({
    required QuickjsPluginClient? client,
    required QuickjsPlugin? plugin,
    required Set<String> lifecycleTypes,
    required Quickjs? engine,
    required bool ownsEngine,
  }) async {
    await _runCleanupStep(
      () =>
          _sendDisposeLifecycle(client, plugin, lifecycleTypes: lifecycleTypes),
    );
    if (client != null && plugin != null) {
      await _runCleanupStep(() async {
        await _clientCallWith(client, 'dispose', const <Object?>[]);
      });
    }
    if (client != null && plugin?.manifest.dispose != null) {
      await _runCleanupStep(() async {
        await client.dispose();
      });
    }
    if (ownsEngine && engine != null) {
      await _runCleanupStep(engine.dispose);
    }
  }

  Future<void> _runCleanupStep(Future<void> Function() action) async {
    try {
      await action();
    } catch (_) {
      // Cleanup is best-effort, but every remaining stage must still run.
    }
  }

  Future<void> _cancelActiveRuntime(
    Quickjs? engine, {
    required bool ownsEngine,
  }) async {
    if (engine == null) {
      return;
    }
    // Calling a JS dispose hook while JS is awaiting a host provider would
    // deadlock behind that same call. Runtime cancellation is therefore the
    // session boundary for active work. Attached engines are stopped and
    // rebuilt by Quickjs so their owner can continue using them afterwards.
    try {
      if (ownsEngine) {
        await engine.dispose();
      } else {
        await engine.stop();
      }
    } catch (_) {
      // Session disposal is terminal and cannot surface asynchronous cleanup
      // errors through its synchronous API.
    }
  }

  Future<void> _sendDisposeLifecycle(
    QuickjsPluginClient? client,
    QuickjsPlugin? plugin, {
    required Set<String> lifecycleTypes,
  }) async {
    if (_disposeLifecycleSent ||
        client == null ||
        plugin == null ||
        !plugin.manifest.exports.contains('lifecycle') ||
        !lifecycleTypes.contains('dispose')) {
      return;
    }
    _disposeLifecycleSent = true;
    final event = const <String, Object?>{'type': 'dispose'};
    await _clientCallWith(client, 'lifecycle', <Object?>[
      event,
    ]).catchError((_) => null);
  }

  Future<T> _enqueue<T>(Future<T> Function() action) {
    return _scheduler.schedule(action);
  }

  Future<bool> _lifecycleImpl(
    String type, {
    Object? payload,
    bool render = true,
    String phase = 'widget',
  }) async {
    _ensureActive();
    final page = _pageBinding;
    if (page == null || !_supportsLifecycle(page, type)) {
      inspector?.recordLifecycle(phase, type, payload: payload);
      return false;
    }
    if (type == 'dispose') {
      if (_disposeLifecycleSent) {
        return false;
      }
      _disposeLifecycleSent = true;
    }
    final event = <String, Object?>{'type': type};
    if (payload != null) {
      event['payload'] = payload;
    }
    inspector?.recordLifecycle(phase, type, payload: payload);
    final result = await _clientCall('lifecycle', <Object?>[event]);
    return _commitCallResult(result, render: render);
  }

  Future<bool> _commitCallResult(Object? result, {bool render = true}) async {
    if (_disposed || !_resultChanged(result)) {
      return false;
    }
    await _syncStateFromJs();
    if (render) {
      await _refreshImpl();
    }
    return true;
  }

  bool _supportsLifecycle(_QuickjsUiPageBinding page, String type) {
    return page.plugin.manifest.exports.contains('lifecycle') &&
        page.lifecycleTypes.contains(type);
  }

  QuickjsPluginClient _requireClient() {
    final client = _pageBinding?.client;
    if (client == null) {
      throw StateError('QuickjsUiSession has no loaded page');
    }
    return client;
  }

  Future<Object?> _clientCall(String name, List<Object?> args) {
    return _clientCallWith(_requireClient(), name, args);
  }

  void _validateRuntimeManifest(QuickjsPlugin plugin) {
    final exports = plugin.manifest.exports;
    const requiredExports = <String>{
      'mount',
      'handleEvent',
      'commit',
      'setState',
      'lifecycle',
      'snapshot',
      'capabilities',
      'dispose',
    };
    final missing = requiredExports.where((name) => !exports.contains(name));
    if (missing.isNotEmpty) {
      throw StateError(
        'quickjs_ui plugin does not implement runtime v1 exports: '
        '${missing.join(', ')}',
      );
    }
  }

  Future<Set<String>> _loadLegacyLifecycleTypes(
    QuickjsPluginClient client,
    QuickjsPlugin plugin,
  ) async {
    _validateRuntimeManifest(plugin);
    final value = await _clientCallWith(
      client,
      'capabilities',
      const <Object?>[],
    );
    if (value is! Map) return const <String>{};
    final protocol = value['protocol'];
    if (protocol != quickjsUiRuntimeProtocol) {
      throw StateError('quickjs_ui unsupported runtime protocol: $protocol');
    }
    _validateCompatibility(value);
    final lifecycle = value['lifecycle'];
    return lifecycle is List
        ? Set<String>.unmodifiable(lifecycle.whereType<String>())
        : const <String>{};
  }

  void _applyBootstrapResult(_QuickjsUiPageBinding page, Object? value) {
    if (value is! Map) {
      throw const FormatException(
        'quickjs_ui bootstrap() must return an object',
      );
    }
    final capabilities = value['capabilities'];
    if (capabilities is! Map) {
      throw const FormatException(
        'quickjs_ui bootstrap().capabilities must be an object',
      );
    }
    final protocol = capabilities['protocol'];
    if (protocol != quickjsUiRuntimeProtocol) {
      throw StateError('quickjs_ui unsupported runtime protocol: $protocol');
    }
    _validateCompatibility(capabilities);
    final lifecycle = capabilities['lifecycle'];
    page.lifecycleTypes = lifecycle is List
        ? Set<String>.unmodifiable(lifecycle.whereType<String>())
        : const <String>{};
    _applySnapshot(value['snapshot']);
    _applyCommitResult(value['commit']);
  }

  void _validateCompatibility(Map<Object?, Object?> capabilities) {
    final schemaVersion = _intCapability(
      capabilities,
      'schemaVersion',
      fallback: 1,
    );
    if (schemaVersion < _minimumSupportedQuickjsUiSchemaVersion ||
        schemaVersion > _maximumSupportedQuickjsUiSchemaVersion) {
      throw StateError(
        'quickjs_ui unsupported schema version: $schemaVersion '
        '(supported $_minimumSupportedQuickjsUiSchemaVersion'
        '-$_maximumSupportedQuickjsUiSchemaVersion)',
      );
    }

    final helperVersion = _intCapability(
      capabilities,
      'helperVersion',
      fallback: 1,
    );
    if (helperVersion > quickjsUiHelperVersion) {
      throw StateError(
        'quickjs_ui helper version is newer than runtime: $helperVersion '
        '(runtime $quickjsUiHelperVersion)',
      );
    }

    final minimumRuntime = _intCapability(
      capabilities,
      'minimumQuickjsUiVersion',
      fallback: 1,
    );
    if (minimumRuntime > _currentQuickjsUiRuntimeVersion) {
      throw StateError(
        'quickjs_ui page requires runtime version $minimumRuntime '
        'but current runtime is $_currentQuickjsUiRuntimeVersion',
      );
    }

    final unknownProps = capabilities['unknownProps'];
    if (unknownProps != null &&
        unknownProps != 'ignore' &&
        unknownProps != 'warn' &&
        unknownProps != 'error') {
      throw StateError(
        'quickjs_ui unsupported unknownProps strategy: $unknownProps',
      );
    }

    final deprecatedProps = capabilities['deprecatedProps'];
    if (deprecatedProps != null && deprecatedProps is! Map) {
      throw StateError('quickjs_ui deprecatedProps must be an object');
    }
  }

  int _intCapability(
    Map<Object?, Object?> capabilities,
    String name, {
    required int fallback,
  }) {
    final value = capabilities[name];
    if (value == null) {
      return fallback;
    }
    if (value is num && value.isFinite) {
      return value.toInt();
    }
    throw StateError('quickjs_ui capability "$name" must be a number');
  }

  Future<void> _syncStateFromJs() async {
    _applySnapshot(await _clientCall('snapshot', const <Object?>[]));
  }

  void _applySnapshot(Object? snapshot) {
    if (snapshot is Map) {
      _state = snapshot['state'];
      return;
    }
    _state = snapshot;
  }

  bool _resultChanged(Object? result) {
    if (result is Map) {
      return result['changed'] == true;
    }
    return result == true;
  }

  Future<Object?> _clientCallWith(
    QuickjsPluginClient client,
    String name,
    List<Object?> args,
  ) async {
    _activeCalls += 1;
    final logicalName = _logicalCallName(name);
    final detail = _callDetail(logicalName, args);
    try {
      return await client.call(name, args);
    } catch (error, stackTrace) {
      throw QuickjsUiError.wrap(
        error,
        kind: _errorKindFor(logicalName),
        stackTrace: stackTrace,
        operation: logicalName,
        action: logicalName == 'dispatch' ? detail : null,
        lifecycle: logicalName == 'lifecycle'
            ? _eventField(args, 'type')
            : null,
        route: _eventRoute(args),
        source: _eventField(args, 'source'),
      );
    } finally {
      _activeCalls -= 1;
    }
  }

  String _logicalCallName(String name) {
    return switch (name) {
      'handleEvent' => 'dispatch',
      'commit' => 'render',
      'snapshot' => 'state',
      _ => name,
    };
  }

  String _callDetail(String logicalName, List<Object?> args) {
    return switch (logicalName) {
      'dispatch' => _dispatchDetail(args),
      'render' => 'build',
      'lifecycle' => 'lifecycle',
      'setState' => 'patch',
      'state' => 'snapshot',
      _ => logicalName,
    };
  }

  String _dispatchDetail(List<Object?> args) {
    if (args.isEmpty) {
      return 'unknown';
    }
    final event = args.length == 1 ? args[0] : args[1];
    if (event is! Map) {
      return 'non-object-event';
    }
    final method = event['method'] ?? event['action'];
    final type = event['type'];
    final positionMs = event['positionMs'];
    final isPlaying = event['isPlaying'];
    final payload = event['payload'];
    final playing =
        event['playing'] ?? (payload is Map ? payload['playing'] : null);
    final durationMs = event['durationMs'];
    final value = event['value'] ?? (payload is Map ? payload['value'] : null);
    final buffer = StringBuffer('method=$method');
    if (type != null) {
      buffer.write(' type=$type');
    }
    if (positionMs != null) {
      buffer.write(' positionMs=$positionMs');
    }
    if (value != null) {
      buffer.write(' value=$value');
    }
    if (durationMs != null) {
      buffer.write(' durationMs=$durationMs');
    }
    if (playing != null) {
      buffer.write(' playing=$playing');
    }
    if (isPlaying != null) {
      buffer.write(' isPlaying=$isPlaying');
    }
    return buffer.toString();
  }

  String? _eventField(List<Object?> args, String name) {
    if (args.isEmpty || args.first is! Map) {
      return null;
    }
    final value = (args.first as Map)[name];
    return value == null ? null : '$value';
  }

  String? _eventRoute(List<Object?> args) {
    if (args.isEmpty || args.first is! Map) {
      return null;
    }
    final event = args.first as Map;
    final payload = event['payload'];
    if (payload is! Map) {
      return null;
    }
    final value = payload['route'] ?? payload['to'] ?? payload['from'];
    return value == null ? null : '$value';
  }

  QuickjsUiErrorKind _errorKindFor(String logicalName) {
    return switch (logicalName) {
      'dispatch' => QuickjsUiErrorKind.dispatch,
      'lifecycle' => QuickjsUiErrorKind.lifecycle,
      'setState' || 'state' => QuickjsUiErrorKind.state,
      'render' => QuickjsUiErrorKind.render,
      'bootstrap' || 'mount' || 'capabilities' => QuickjsUiErrorKind.load,
      'dispose' => QuickjsUiErrorKind.disposed,
      _ => QuickjsUiErrorKind.runtime,
    };
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiSession is disposed');
    }
  }
}

final class _QuickjsUiEngineBinding {
  const _QuickjsUiEngineBinding._({
    this.engine,
    this.context,
    required this.ownsEngine,
    required this.mounts,
    this.runtimeLease,
  });

  factory _QuickjsUiEngineBinding.attached(Quickjs engine) {
    return _QuickjsUiEngineBinding._(
      engine: engine,
      ownsEngine: false,
      mounts: const <QuickjsHostMount>[],
    );
  }

  factory _QuickjsUiEngineBinding.owned(
    Quickjs engine,
    List<QuickjsHostMount> mounts,
  ) {
    return _QuickjsUiEngineBinding._(
      engine: engine,
      ownsEngine: true,
      mounts: mounts,
    );
  }

  factory _QuickjsUiEngineBinding.leased(
    QuickjsUiRuntimeLease lease,
    List<QuickjsHostMount> mounts,
  ) {
    return _QuickjsUiEngineBinding._(
      context: lease.context,
      ownsEngine: false,
      mounts: mounts,
      runtimeLease: lease,
    );
  }

  final Quickjs? engine;
  final QuickjsContext? context;
  QuickjsPluginHost get host => context ?? engine!;
  final bool ownsEngine;
  final List<QuickjsHostMount> mounts;
  final QuickjsUiRuntimeLease? runtimeLease;
}

final class _QuickjsUiPageBinding {
  _QuickjsUiPageBinding({
    required this.plugin,
    required this.client,
    required this.props,
    required this.mounts,
    required this.grantedPermissions,
    required this.permissionPolicy,
  });

  final QuickjsPlugin plugin;
  final QuickjsPluginClient client;
  final Map<String, Object?> props;
  final List<QuickjsHostMount> mounts;
  final Set<String> grantedPermissions;
  final QuickjsUiPermissionPolicy? permissionPolicy;
  Set<String> lifecycleTypes = const <String>{};
}

final class _SessionOperationScheduler {
  final Queue<_SessionOperation<Object?>> _queue =
      Queue<_SessionOperation<Object?>>();
  bool _draining = false;

  Future<T> schedule<T>(Future<T> Function() action) {
    final operation = _SessionOperation<T>(action: action);
    _queue.add(operation);
    if (!_draining) {
      unawaited(_drain());
    }
    return operation.future;
  }

  Future<void> _drain() async {
    if (_draining) {
      return;
    }
    _draining = true;
    try {
      while (_queue.isNotEmpty) {
        await _queue.removeFirst().run();
      }
    } finally {
      _draining = false;
      if (_queue.isNotEmpty) {
        unawaited(_drain());
      }
    }
  }
}

final class _SessionOperation<T> {
  _SessionOperation({required Future<T> Function() action}) : _action = action;

  final Future<T> Function() _action;
  final Completer<T> _completer = Completer<T>();

  Future<T> get future => _completer.future;

  Future<void> run() async {
    if (_completer.isCompleted) {
      return;
    }
    try {
      _completer.complete(await _action());
    } catch (error, stackTrace) {
      _completer.completeError(error, stackTrace);
    }
  }
}

Future<void> _ensureHelperModuleMounted(Quickjs engine) async {
  final snapshot = await engine.debugInspect();
  if (snapshot.moduleNames.contains(quickjsUiHelperModuleSpecifier)) {
    return;
  }
  await engine.mount(quickjsUiHelperMount);
}

bool _sameMountConfiguration(
  List<QuickjsHostMount> left,
  List<QuickjsHostMount> right,
) {
  if (left.length != right.length) {
    return false;
  }
  for (var index = 0; index < left.length; index += 1) {
    if (!identical(left[index], right[index])) {
      return false;
    }
  }
  return true;
}
