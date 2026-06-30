import 'package:flutter/foundation.dart';
import 'package:quickjs/quickjs.dart';

import 'quickjs_ui_node.dart';
import 'quickjs_ui_session.dart';

typedef QuickjsUiPluginLoader = Future<QuickjsPlugin> Function();

/// Controller for one quickjs_ui page instance.
///
/// The controller is the Flutter binding layer: it owns loading/error
/// notifications, while [QuickjsUiSession] owns runtime, plugin, state and tree
/// lifecycle.
final class QuickjsUiController extends ChangeNotifier {
  QuickjsUiController({Quickjs? engine})
    : _session = QuickjsUiSession(engine: engine);

  final QuickjsUiSession _session;
  Object? _error;
  QuickjsUiPluginLoader? _loader;
  Map<String, Object?> _initialProps = const <String, Object?>{};
  List<QuickjsHostMount> _mounts = const <QuickjsHostMount>[];
  bool _loading = false;
  bool _disposed = false;

  QuickjsUiSession get session => _session;
  Quickjs? get engine => _session.engine;
  QuickjsPlugin? get plugin => _session.plugin;
  Map<String, Object?> get props => _session.props;
  Object? get state => _session.state;
  QuickjsUiNode? get node => _session.node;
  Object? get error => _error;
  bool get hasError => _error != null;
  bool get isLoading => _loading;
  bool get isDisposed => _disposed;

  Future<void> loadPlugin(
    QuickjsPlugin plugin, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
  }) async {
    _loader = null;
    _initialProps = Map<String, Object?>.unmodifiable(initialProps);
    _mounts = List<QuickjsHostMount>.unmodifiable(mounts);
    await _loadPlugin(plugin, initialProps: initialProps, mounts: mounts);
  }

  Future<void> load(
    QuickjsUiPluginLoader loader, {
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
  }) async {
    _ensureActive();
    _loader = loader;
    _initialProps = Map<String, Object?>.unmodifiable(initialProps);
    _mounts = List<QuickjsHostMount>.unmodifiable(mounts);
    final plugin = await loader();
    await _loadPlugin(plugin, initialProps: initialProps, mounts: mounts);
  }

  Future<void> _loadPlugin(
    QuickjsPlugin plugin, {
    required Map<String, Object?> initialProps,
    required List<QuickjsHostMount> mounts,
  }) async {
    _ensureActive();
    _loading = true;
    _error = null;
    notifyListeners();

    try {
      await _session.loadPlugin(
        plugin,
        initialProps: initialProps,
        mounts: mounts,
      );
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> dispatch(Map<String, Object?> event) async {
    _ensureActive();
    _error = null;
    notifyListeners();
    try {
      await _session.dispatch(event);
      notifyListeners();
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  Future<void> setState(Map<String, Object?> patch) async {
    _ensureActive();
    await _session.setState(patch);
    notifyListeners();
  }

  Future<void> refresh() async {
    _ensureActive();
    _error = null;
    notifyListeners();
    try {
      await _session.refresh();
      notifyListeners();
    } catch (error) {
      _error = error;
      notifyListeners();
    }
  }

  void attach(Quickjs engine) {
    _ensureActive();
    _session.attach(engine);
    _error = null;
    notifyListeners();
  }

  void reportError(Object error) {
    _ensureActive();
    _error = error;
    notifyListeners();
  }

  Future<void> restart() async {
    _ensureActive();
    if (_session.plugin == null) {
      _error = null;
      notifyListeners();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      await _session.reload();
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  Future<void> reload() async {
    _ensureActive();
    if (_session.plugin == null) {
      _error = null;
      notifyListeners();
      return;
    }
    final loader = _loader;
    if (loader == null) {
      await restart();
      return;
    }
    _loading = true;
    _error = null;
    notifyListeners();
    try {
      final plugin = await loader();
      await _session.loadPlugin(
        plugin,
        initialProps: _initialProps,
        mounts: _mounts,
      );
    } catch (error) {
      _error = error;
    } finally {
      _loading = false;
      notifyListeners();
    }
  }

  @override
  void dispose() {
    if (_disposed) {
      return;
    }
    _disposed = true;
    _session.dispose();
    super.dispose();
  }

  void _ensureActive() {
    if (_disposed) {
      throw StateError('QuickjsUiController is disposed');
    }
  }
}
