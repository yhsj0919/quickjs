import 'dart:async';

import 'package:quickjs/quickjs.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_helpers.dart';

final class QuickjsUiSession {
  // Keep the public constructor parameter named `engine`.
  // ignore: prefer_initializing_formals
  QuickjsUiSession({Quickjs? engine}) : _engine = engine;

  Quickjs? _engine;
  QuickjsPlugin? _plugin;
  QuickjsPluginClient? _client;
  Map<String, Object?> _props = const <String, Object?>{};
  List<QuickjsHostMount> _mounts = const <QuickjsHostMount>[];
  Object? _state;
  QuickjsUiNode? _node;
  bool _ownsEngine = false;
  bool _disposed = false;

  Quickjs? get engine => _engine;
  QuickjsPlugin? get plugin => _plugin;
  Map<String, Object?> get props => _props;
  List<QuickjsHostMount> get mounts => _mounts;
  Object? get state => _state;
  QuickjsUiNode? get node => _node;
  bool get isDisposed => _disposed;

  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
  }) async {
    _ensureActive();
    final engine =
        _engine ??
        await Quickjs.create(
          options: QuickjsRuntimeOptions(
            mounts: <QuickjsHostMount>[quickjsUiHelperMount, ...mounts],
          ),
        );
    _ownsEngine = _engine == null;
    _engine = engine;
    if (!_ownsEngine) {
      await _ensureHelperModuleMounted(engine);
    }
    await engine.mount(
      plugin.asMount(name: 'quickjs_ui:page:${plugin.manifest.id}'),
      conflictPolicy: QuickjsHostMountConflictPolicy.replace,
    );
    _plugin = plugin;
    _props = Map<String, Object?>.unmodifiable(initialProps);
    _mounts = List<QuickjsHostMount>.unmodifiable(mounts);
    _client = QuickjsPluginClient(engine, plugin);
    await _client!.validate();
    _state = plugin.manifest.init == null
        ? <String, Object?>{}
        : await _client!.init(_props);
    await refresh();
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    _ensureActive();
    final nextState = await _requireClient().call('dispatch', <Object?>[
      _state,
      event,
      _props,
    ]);
    if (nextState != null) {
      _state = nextState;
    }
    await refresh();
  }

  Future<void> setState(Map<String, Object?> patch) async {
    _ensureActive();
    final current = _state;
    if (current is Map) {
      _state = <String, Object?>{
        ...current.map(
          (key, value) => MapEntry<String, Object?>('$key', value),
        ),
        ...patch,
      };
    } else {
      _state = Map<String, Object?>.of(patch);
    }
    await refresh();
  }

  Future<void> refresh() async {
    _ensureActive();
    final rendered = await _requireClient().call('render', <Object?>[
      _state,
      _props,
    ]);
    if (rendered is! Map) {
      throw const FormatException(
        'quickjs_ui render() must return a UI node object',
      );
    }
    _node = QuickjsUiNode.fromMap(
      rendered.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }

  Future<void> reload() async {
    _ensureActive();
    final plugin = _plugin;
    if (plugin == null) {
      return;
    }
    await loadPlugin(plugin, initialProps: _props, mounts: _mounts);
  }

  void attach(Quickjs engine) {
    _ensureActive();
    _engine = engine;
    _ownsEngine = false;
  }

  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    final client = _client;
    final plugin = _plugin;
    final engine = _engine;
    _client = null;
    _engine = null;
    _plugin = null;
    if (client != null && plugin?.manifest.dispose != null) {
      unawaited(client.dispose().catchError((_) => null));
    }
    if (_ownsEngine) {
      unawaited(engine?.dispose() ?? Future<void>.value());
    }
  }

  QuickjsPluginClient _requireClient() {
    final client = _client;
    if (client == null) {
      throw StateError('QuickjsUiSession has no loaded page');
    }
    return client;
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiSession is disposed');
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
