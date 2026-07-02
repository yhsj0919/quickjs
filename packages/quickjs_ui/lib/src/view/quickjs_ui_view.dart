import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:quickjs/quickjs.dart';

import '../host/quickjs_ui_permission_policy.dart';
import '../renderer/quickjs_ui_component_registry.dart';
import '../renderer/quickjs_ui_renderer.dart';
import '../resource/quickjs_ui_bundle.dart';
import '../resource/quickjs_ui_network_loader.dart';
import '../runtime/quickjs_ui_controller.dart';
import 'quickjs_ui_error_overlay.dart';

typedef QuickjsUiErrorBuilder =
    Widget Function(BuildContext context, Object error);

typedef QuickjsUiLoadingBuilder = Widget Function(BuildContext context);

typedef QuickjsUiEmptyBuilder = Widget Function(BuildContext context);

final class QuickjsUiView extends StatefulWidget {
  const QuickjsUiView({
    super.key,
    this.plugin,
    String? path,
    this.bundleRoot,
    this.initialProps = const <String, Object?>{},
    this.mounts = const <QuickjsHostMount>[],
    this.grantedPermissions = const <String>{},
    this.permissionPolicy,
    this.onConsole,
    this.controller,
    this.registry,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
  }) : _source = plugin != null
           ? _QuickjsUiViewSource.plugin
           : _QuickjsUiViewSource.asset,
       _path = path,
       networkUrl = null,
       networkBundleRoot = null,
       networkFetch = null,
       onNetworkLog = null,
       assert(plugin != null || path != null);

  factory QuickjsUiView.plugin(
    QuickjsPlugin plugin, {
    Key? key,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiComponentRegistry? registry,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
  }) {
    return QuickjsUiView._(
      key: key,
      plugin: plugin,
      source: _QuickjsUiViewSource.plugin,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      registry: registry,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
    );
  }

  factory QuickjsUiView.asset({
    Key? key,
    required String path,
    String? bundleRoot,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiComponentRegistry? registry,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
  }) {
    return QuickjsUiView._(
      key: key,
      path: path,
      bundleRoot: bundleRoot,
      source: _QuickjsUiViewSource.asset,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      registry: registry,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
    );
  }

  factory QuickjsUiView.file({
    Key? key,
    required String path,
    String? bundleRoot,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiComponentRegistry? registry,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
  }) {
    return QuickjsUiView._(
      key: key,
      path: path,
      bundleRoot: bundleRoot,
      source: _QuickjsUiViewSource.file,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      registry: registry,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
    );
  }

  factory QuickjsUiView.network({
    Key? key,
    required Uri url,
    Uri? bundleRoot,
    QuickjsUiNetworkFetch? fetch,
    QuickjsUiNetworkLogHandler? onNetworkLog,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiComponentRegistry? registry,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
  }) {
    return QuickjsUiView._(
      key: key,
      path: url.toString(),
      networkUrl: url,
      networkBundleRoot: bundleRoot,
      networkFetch: fetch,
      onNetworkLog: onNetworkLog,
      source: _QuickjsUiViewSource.network,
      initialProps: initialProps,
      mounts: mounts,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      registry: registry,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
    );
  }

  const QuickjsUiView._({
    super.key,
    this.plugin,
    this._path,
    this.bundleRoot,
    this.networkUrl,
    this.networkBundleRoot,
    this.networkFetch,
    this.onNetworkLog,
    required this._source,
    this.initialProps = const <String, Object?>{},
    this.mounts = const <QuickjsHostMount>[],
    this.grantedPermissions = const <String>{},
    this.permissionPolicy,
    this.onConsole,
    this.controller,
    this.registry,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
  });

  final QuickjsPlugin? plugin;
  final String? _path;
  final String? bundleRoot;
  final Uri? networkUrl;
  final Uri? networkBundleRoot;
  final QuickjsUiNetworkFetch? networkFetch;
  final QuickjsUiNetworkLogHandler? onNetworkLog;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;
  final Iterable<String> grantedPermissions;
  final QuickjsUiPermissionPolicy? permissionPolicy;
  final QuickjsConsoleSink? onConsole;
  final QuickjsUiController? controller;
  final QuickjsUiComponentRegistry? registry;
  final Widget? placeholder;
  final QuickjsUiLoadingBuilder? loadingBuilder;
  final QuickjsUiErrorBuilder? errorBuilder;
  final QuickjsUiEmptyBuilder? emptyBuilder;
  final VoidCallback? onFirstRender;
  final _QuickjsUiViewSource _source;

  @override
  State<QuickjsUiView> createState() => _QuickjsUiViewState();
}

final class _QuickjsUiViewState extends State<QuickjsUiView>
    with WidgetsBindingObserver {
  late QuickjsUiController _controller;
  late bool _ownsController;
  late QuickjsUiRenderer _renderer;
  QuickjsUiNetworkLoader? _networkLoader;
  bool _reportedFirstRender = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _controller =
        widget.controller ?? QuickjsUiController(onConsole: widget.onConsole);
    _ownsController = widget.controller == null;
    _controller.addListener(_handleControllerChanged);
    _renderer = QuickjsUiRenderer(
      registry: widget.registry,
      onEvent: _controller.dispatch,
    );
    _load();
  }

  @override
  void didUpdateWidget(covariant QuickjsUiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      _controller.removeListener(_handleControllerChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _controller =
          widget.controller ?? QuickjsUiController(onConsole: widget.onConsole);
      _ownsController = widget.controller == null;
      _controller.addListener(_handleControllerChanged);
      _renderer = QuickjsUiRenderer(
        registry: widget.registry,
        onEvent: _controller.dispatch,
      );
    } else if (oldWidget.registry != widget.registry) {
      _renderer = QuickjsUiRenderer(
        registry: widget.registry,
        onEvent: _controller.dispatch,
      );
    }
    if (oldWidget.plugin != widget.plugin ||
        oldWidget._path != widget._path ||
        oldWidget.bundleRoot != widget.bundleRoot ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.networkBundleRoot != widget.networkBundleRoot ||
        oldWidget.networkFetch != widget.networkFetch ||
        oldWidget.onNetworkLog != widget.onNetworkLog ||
        oldWidget._source != widget._source ||
        oldWidget.initialProps != widget.initialProps ||
        oldWidget.mounts != widget.mounts ||
        !_stringIterableSetEquals(
          oldWidget.grantedPermissions,
          widget.grantedPermissions,
        ) ||
        oldWidget.permissionPolicy != widget.permissionPolicy) {
      if (oldWidget.networkFetch != widget.networkFetch ||
          oldWidget.onNetworkLog != widget.onNetworkLog ||
          oldWidget.networkUrl != widget.networkUrl) {
        _networkLoader = null;
      }
      _reportedFirstRender = false;
      _load();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _controller.removeListener(_handleControllerChanged);
    if (_ownsController) {
      _controller.dispose();
    }
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    super.didChangeAppLifecycleState(state);
    if (_controller.plugin == null || _controller.isDisposed) {
      return;
    }
    switch (state) {
      case AppLifecycleState.resumed:
        unawaited(_controller.lifecycle('resume'));
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        unawaited(_controller.lifecycle('pause'));
      case AppLifecycleState.detached:
        unawaited(_controller.lifecycle('dispose', render: false));
    }
  }

  @override
  Widget build(BuildContext context) {
    final error = _controller.error;
    if (error != null) {
      final builder = widget.errorBuilder;
      if (builder != null) {
        return builder(context, error);
      }
      return QuickjsUiErrorOverlay(
        error: error,
        details: _errorDetails(schemaPath: 'root'),
      );
    }

    if (_controller.isLoading) {
      return widget.loadingBuilder?.call(context) ??
          widget.placeholder ??
          const SizedBox.shrink();
    }

    final node = _controller.node;
    if (node == null) {
      return widget.emptyBuilder?.call(context) ??
          widget.placeholder ??
          const SizedBox.shrink();
    }

    try {
      final rendered = _renderer.build(node, buildContext: context);
      _reportFirstRender();
      return rendered;
    } catch (error) {
      return _buildError(context, error, schemaPath: 'root');
    }
  }

  Widget _buildError(BuildContext context, Object error, {String? schemaPath}) {
    final builder = widget.errorBuilder;
    if (builder != null) {
      return builder(context, error);
    }
    return QuickjsUiErrorOverlay(
      error: error,
      details: _errorDetails(schemaPath: schemaPath),
    );
  }

  QuickjsUiErrorDetails _errorDetails({String? schemaPath}) {
    return QuickjsUiErrorDetails(
      source: widget._source.name,
      resourceKey: widget.networkUrl?.toString() ?? widget._path,
      schemaPath: schemaPath,
    );
  }

  void _reportFirstRender() {
    if (_reportedFirstRender) {
      return;
    }
    _reportedFirstRender = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!mounted) {
        return;
      }
      await _controller.lifecycle('mount');
      if (!mounted) {
        return;
      }
      widget.onFirstRender?.call();
    });
  }

  Future<void> _load() async {
    try {
      if (!mounted) {
        return;
      }
      await _controller.load(
        _loadPlugin,
        initialProps: widget.initialProps,
        mounts: widget.mounts,
        grantedPermissions: widget.grantedPermissions,
        permissionPolicy: widget.permissionPolicy,
      );
    } catch (error) {
      if (mounted) {
        _controller.reportError(error);
      }
    }
  }

  Future<QuickjsPlugin> _loadPlugin() async {
    final plugin = widget.plugin;
    if (plugin != null) {
      return plugin;
    }
    return switch (widget._source) {
      _QuickjsUiViewSource.plugin => throw StateError(
        'QuickjsUiView.plugin requires a plugin',
      ),
      _QuickjsUiViewSource.asset => _loadAssetPlugin(widget._path!),
      _QuickjsUiViewSource.file => _loadFilePlugin(widget._path!),
      _QuickjsUiViewSource.network => _loadNetworkPlugin(widget.networkUrl!),
    };
  }

  Future<QuickjsPlugin> _loadAssetPlugin(String path) async {
    final bundle = await QuickjsUiBundle.asset(
      path: path,
      bundleRoot: widget.bundleRoot,
    );
    return bundle.toPlugin();
  }

  Future<QuickjsPlugin> _loadNetworkPlugin(Uri url) async {
    final loader = _networkLoader ??= QuickjsUiNetworkLoader(
      fetch: widget.networkFetch,
      onLog: widget.onNetworkLog,
    );
    final bundle = await loader.load(
      url: url,
      bundleRoot: widget.networkBundleRoot,
    );
    return bundle.toPlugin();
  }

  Future<QuickjsPlugin> _loadFilePlugin(String path) async {
    final bundle = await QuickjsUiBundle.file(
      path: path,
      bundleRoot: widget.bundleRoot,
    );
    return bundle.toPlugin();
  }

  void _handleControllerChanged() {
    if (mounted) {
      setState(() {});
    }
  }
}

enum _QuickjsUiViewSource { plugin, asset, file, network }

bool _stringIterableSetEquals(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
