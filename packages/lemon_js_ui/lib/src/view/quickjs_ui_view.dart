import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:lemon_js/lemon_js.dart';

import '../diagnostics/quickjs_ui_dev_options.dart';
import '../diagnostics/quickjs_ui_error.dart';
import '../diagnostics/quickjs_ui_diag.dart';
import '../host/quickjs_ui_permission_policy.dart';
import '../performance/quickjs_ui_effect_quality.dart';
import '../renderer/quickjs_ui_component_registry.dart';
import '../renderer/quickjs_ui_event_ingress.dart';
import '../renderer/quickjs_ui_renderer.dart';
import '../resource/quickjs_ui_network_loader.dart';
import '../resource/quickjs_ui_resource_cache.dart';
import '../runtime/quickjs_ui_controller.dart';
import '../runtime/quickjs_ui_plugin.dart';
import '../runtime/quickjs_ui_runtime.dart';
import 'quickjs_ui_error_overlay.dart';

/// 页面加载或渲染失败时构建错误 UI 的回调。
///
/// [context] 为当前 BuildContext；[error] 为捕获到的异常对象。
typedef QuickjsUiErrorBuilder =
    Widget Function(BuildContext context, QuickjsUiError error);

/// 页面 JS bundle 尚未就绪时构建加载中 UI 的回调。
typedef QuickjsUiLoadingBuilder = Widget Function(BuildContext context);

/// 页面渲染结果为空时构建占位 UI 的回调。
typedef QuickjsUiEmptyBuilder = Widget Function(BuildContext context);

/// QuickJS UI 页面容器 Widget。
///
/// 负责创建并持有 [QuickjsUiController]、加载 JS 页面、将 schema 树渲染为
/// Flutter Widget，并在页面销毁时释放 runtime。
///
/// 能力注入分为两类：
/// - [mounts]：业务 JS 能力（网络、宿主 API、polyfill 等）。
/// - [uiPlugins]：第三方原生 UI 组件插件（同时包含 JS 模块与 Flutter 渲染注册）。
final class QuickjsUiView extends StatefulWidget {
  /// 通用构造：通过 [plugin] 或 [path] 二选一指定页面来源。
  ///
  /// 更推荐使用具名工厂 [QuickjsUiView.plugin]、[QuickjsUiView.asset] 等。
  const QuickjsUiView({
    super.key,
    this.plugin,
    String? path,
    this.bundleRoot,
    this.initialProps = const <String, Object?>{},
    this.mounts = const <QuickjsHostMount>[],
    this.uiPlugins = const <QuickjsUiPlugin>[],
    this.grantedPermissions = const <String>{},
    this.permissionPolicy,
    this.onConsole,
    this.runtime,
    this.controller,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
    this.resourceCache,
    this.performanceController,
  }) : _source = plugin != null
           ? _QuickjsUiViewSource.plugin
           : _QuickjsUiViewSource.asset,
       _path = path,
       networkUrl = null,
       networkBundleRoot = null,
       networkFetch = null,
       onNetworkLog = null,
       assert(plugin != null || path != null),
       assert(runtime == null || controller == null);

  /// 从已注册的 [QuickjsPlugin] 加载页面。
  ///
  /// - [plugin]：QuickJS 插件描述对象，通常包含入口脚本与模块图。
  /// - [initialProps]：传给 JS 页面根组件的初始 props。
  /// - [mounts]：业务侧 JS runtime 能力 mount。
  /// - [uiPlugins]：需要额外原生 UI 控件时传入的 UI 插件列表。
  /// - [grantedPermissions]：页面已授权的能力名称集合。
  /// - [permissionPolicy]：权限拦截策略；为 `null` 时使用默认策略。
  /// - [controller]：外部持有的控制器；为 `null` 时由本 Widget 内部创建。
  /// - [onConsole]：接收 JS `console.*` 输出的回调。
  /// - [placeholder]：首帧渲染前的占位 Widget。
  /// - [loadingBuilder]：加载中状态 UI 构建器。
  /// - [errorBuilder]：错误状态 UI 构建器。
  /// - [emptyBuilder]：空内容状态 UI 构建器。
  /// - [onFirstRender]：首次成功渲染后的回调。
  factory QuickjsUiView.plugin(
    QuickjsPlugin plugin, {
    Key? key,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
    QuickjsUiResourceCache? resourceCache,
    QuickjsUiPerformanceController? performanceController,
  }) {
    return QuickjsUiView._(
      key: key,
      plugin: plugin,
      source: _QuickjsUiViewSource.plugin,
      initialProps: initialProps,
      mounts: mounts,
      uiPlugins: uiPlugins,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      runtime: runtime,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
      resourceCache: resourceCache,
      performanceController: performanceController,
    );
  }

  /// 从 Flutter asset 加载单文件或多文件 quickjs_ui 页面。
  ///
  /// - [path]：入口 `.mjs` 或其它脚本的 asset 路径（必填）。
  /// - [bundleRoot]：多文件 bundle 的根目录；为 `null` 时根据 [path] 自动推断。
  /// 其余参数含义同 [QuickjsUiView.plugin]。
  factory QuickjsUiView.asset({
    Key? key,
    required String path,
    String? bundleRoot,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
    QuickjsUiResourceCache? resourceCache,
    QuickjsUiPerformanceController? performanceController,
  }) {
    return QuickjsUiView._(
      key: key,
      path: path,
      bundleRoot: bundleRoot,
      source: _QuickjsUiViewSource.asset,
      initialProps: initialProps,
      mounts: mounts,
      uiPlugins: uiPlugins,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      runtime: runtime,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
      resourceCache: resourceCache,
      performanceController: performanceController,
    );
  }

  /// 从设备本地文件系统加载 quickjs_ui 页面（主要用于开发调试）。
  ///
  /// - [path]：本地入口脚本绝对路径（必填）。
  /// - [bundleRoot]：本地 bundle 根目录。
  /// 其余参数含义同 [QuickjsUiView.asset]。
  factory QuickjsUiView.file({
    Key? key,
    required String path,
    String? bundleRoot,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
    QuickjsUiResourceCache? resourceCache,
    QuickjsUiPerformanceController? performanceController,
  }) {
    return QuickjsUiView._(
      key: key,
      path: path,
      bundleRoot: bundleRoot,
      source: _QuickjsUiViewSource.file,
      initialProps: initialProps,
      mounts: mounts,
      uiPlugins: uiPlugins,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      runtime: runtime,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
      resourceCache: resourceCache,
      performanceController: performanceController,
    );
  }

  /// 通过网络 URL 加载 quickjs_ui 页面。
  ///
  /// - [url]：远程入口脚本 URL（必填）。
  /// - [bundleRoot]：远程 bundle 根 URL；为 `null` 时根据 [url] 自动推断。
  /// - [fetch]：自定义网络请求实现；为 `null` 时使用默认实现。
  /// - [onNetworkLog]：网络加载诊断日志回调。
  /// 其余参数含义同 [QuickjsUiView.asset]。
  factory QuickjsUiView.network({
    Key? key,
    required Uri url,
    Uri? bundleRoot,
    QuickjsUiNetworkFetch? fetch,
    QuickjsUiNetworkLogHandler? onNetworkLog,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
    Iterable<String> grantedPermissions = const <String>[],
    QuickjsUiPermissionPolicy? permissionPolicy,
    QuickjsUiController? controller,
    QuickjsUiRuntime? runtime,
    QuickjsConsoleSink? onConsole,
    Widget? placeholder,
    QuickjsUiLoadingBuilder? loadingBuilder,
    QuickjsUiErrorBuilder? errorBuilder,
    QuickjsUiEmptyBuilder? emptyBuilder,
    VoidCallback? onFirstRender,
    QuickjsUiResourceCache? resourceCache,
    QuickjsUiPerformanceController? performanceController,
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
      uiPlugins: uiPlugins,
      grantedPermissions: grantedPermissions,
      permissionPolicy: permissionPolicy,
      onConsole: onConsole,
      controller: controller,
      runtime: runtime,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
      resourceCache: resourceCache,
      performanceController: performanceController,
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
    this.uiPlugins = const <QuickjsUiPlugin>[],
    this.grantedPermissions = const <String>{},
    this.permissionPolicy,
    this.onConsole,
    this.runtime,
    this.controller,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
    this.resourceCache,
    this.performanceController,
  }) : assert(runtime == null || controller == null);

  final QuickjsPlugin? plugin;
  final String? _path;

  /// 多文件 bundle 根路径（asset / 本地文件 / 网络 URL 语义由加载源决定）。
  final String? bundleRoot;

  /// 网络加载模式下的入口 URL。
  final Uri? networkUrl;

  /// 网络加载模式下的 bundle 根 URL。
  final Uri? networkBundleRoot;

  /// 网络加载使用的自定义 fetch 实现。
  final QuickjsUiNetworkFetch? networkFetch;

  /// 网络加载过程日志回调。
  final QuickjsUiNetworkLogHandler? onNetworkLog;

  /// 传给 JS 页面根组件的初始 props。
  final Map<String, Object?> initialProps;

  /// 页面业务 JavaScript runtime 所需的宿主能力 mount。
  ///
  /// 例如 [QuickjsAxiosMount]、[QuickjsFetchMount]、自定义 provider mount 等。
  final List<QuickjsHostMount> mounts;

  /// 第三方原生 UI 组件插件列表。
  ///
  /// 每个插件同时提供 JS 模块 mount 与 Flutter 组件注册，避免只配一半。
  final List<QuickjsUiPlugin> uiPlugins;

  /// 页面已声明并授权的能力名称。
  final Iterable<String> grantedPermissions;

  /// 页面权限策略；控制未授权能力调用时的拦截行为。
  final QuickjsUiPermissionPolicy? permissionPolicy;

  /// JS `console.*` 输出接收器。
  final QuickjsConsoleSink? onConsole;

  /// Shared owner of pre-initialized engines. Page [mounts] remain scoped to
  /// the leased engine configuration and are never merged into other pages.
  final QuickjsUiRuntime? runtime;

  /// 外部传入的 UI 控制器，用于热重载、快照、导航等高级操作。
  final QuickjsUiController? controller;

  /// 首帧渲染完成前的占位 Widget。
  final Widget? placeholder;

  /// 加载中 UI 构建器。
  final QuickjsUiLoadingBuilder? loadingBuilder;

  /// 错误 UI 构建器。
  final QuickjsUiErrorBuilder? errorBuilder;

  /// 空内容 UI 构建器。
  final QuickjsUiEmptyBuilder? emptyBuilder;

  /// 首次成功渲染 schema 后的回调。
  final VoidCallback? onFirstRender;

  /// Bounded cache for parsed UI resources. Resource constructors use the
  /// process-wide [QuickjsUiResourceCache.shared] by default. Pass a dedicated
  /// cache for isolation, or one with `maxAge: Duration.zero` to disable it.
  final QuickjsUiResourceCache? resourceCache;
  final QuickjsUiPerformanceController? performanceController;
  final _QuickjsUiViewSource _source;

  @override
  State<QuickjsUiView> createState() => _QuickjsUiViewState();
}

final class _QuickjsUiViewState extends State<QuickjsUiView>
    with WidgetsBindingObserver {
  late QuickjsUiController _controller;
  late bool _ownsController;
  late QuickjsUiRenderer _renderer;
  late QuickjsUiEventIngress _eventIngress;
  late QuickjsUiPerformanceController _performanceController;
  late bool _ownsPerformanceController;
  late final _QuickjsUiLoadCoordinator _loadCoordinator;
  bool _reportedFirstRender = false;
  bool _reportedShow = false;
  late int _observedPageRevision;
  int _generation = 0;
  _QuickjsUiAppLifecycleSignal? _lastAppLifecycleSignal;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _loadCoordinator = _QuickjsUiLoadCoordinator();
    _controller =
        widget.controller ??
        QuickjsUiController(
          runtime: widget.runtime,
          onConsole: widget.onConsole,
        );
    _ownsController = widget.controller == null;
    _performanceController =
        widget.performanceController ??
        QuickjsUiPerformanceController(mode: QuickjsUiPerformanceMode.auto);
    _ownsPerformanceController = widget.performanceController == null;
    _performanceController.addListener(_recordPerformance);
    _controller.addListener(_handleControllerChanged);
    _observedPageRevision = _controller.pageRevision;
    _eventIngress = QuickjsUiEventIngress(_controller.dispatch);
    _renderer = _createRenderer();
    _scheduleLoad(immediate: true);
  }

  QuickjsUiRenderer _createRenderer() {
    final devOptions = _controller.devOptions;
    return QuickjsUiRenderer(
      registry: _effectiveRegistry(),
      onEvent: _eventIngress.submit,
      onUiEvent: _eventIngress.submitEnvelope,
      onDiffStats: devOptions.logDiff ? _controller.inspector.recordDiff : null,
      canvasSceneRegistry: _controller.canvasSceneRegistry,
      performanceController: _performanceController,
      networkResourceBaseUri: _networkResourceBaseUri(),
    );
  }

  Uri? _networkResourceBaseUri() {
    if (widget._source != _QuickjsUiViewSource.network) return null;
    final root = widget.networkBundleRoot;
    if (root == null) return widget.networkUrl!.resolve('.');
    final value = root.toString();
    return value.endsWith('/') ? root : Uri.parse('$value/');
  }

  QuickjsUiComponentRegistry? _effectiveRegistry() {
    if (widget.uiPlugins.isEmpty) {
      return null;
    }
    final registry = QuickjsUiComponentRegistry.defaults();
    for (final plugin in widget.uiPlugins) {
      plugin.configure(registry);
    }
    return registry;
  }

  List<QuickjsHostMount> _effectiveMounts() {
    if (widget.uiPlugins.isEmpty) {
      return widget.mounts;
    }
    return <QuickjsHostMount>[
      ...widget.mounts,
      for (final plugin in widget.uiPlugins) ...plugin.mounts,
    ];
  }

  QuickjsUiDevOptions get _devOptions => _controller.devOptions;

  void _recordPerformance() {
    _controller.inspector.recordPerformance(_performanceController.snapshot);
  }

  @override
  void didUpdateWidget(covariant QuickjsUiView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.performanceController != widget.performanceController) {
      _performanceController.removeListener(_recordPerformance);
      if (_ownsPerformanceController) _performanceController.dispose();
      _performanceController =
          widget.performanceController ??
          QuickjsUiPerformanceController(mode: QuickjsUiPerformanceMode.auto);
      _ownsPerformanceController = widget.performanceController == null;
      _performanceController.addListener(_recordPerformance);
      _renderer.dispose();
      _renderer = _createRenderer();
    }
    if (oldWidget.controller != widget.controller ||
        oldWidget.runtime != widget.runtime) {
      _controller.removeListener(_handleControllerChanged);
      if (_ownsController) {
        _controller.dispose();
      }
      _controller =
          widget.controller ??
          QuickjsUiController(
            runtime: widget.runtime,
            onConsole: widget.onConsole,
          );
      _ownsController = widget.controller == null;
      _controller.addListener(_handleControllerChanged);
      _observedPageRevision = _controller.pageRevision;
      _eventIngress.dispose();
      _eventIngress = QuickjsUiEventIngress(_controller.dispatch);
      _renderer.dispose();
      _renderer = _createRenderer();
      _advanceGeneration();
    } else if (oldWidget.uiPlugins != widget.uiPlugins) {
      _renderer.dispose();
      _renderer = _createRenderer();
      _advanceGeneration();
    }
    if (oldWidget.plugin != widget.plugin ||
        oldWidget.runtime != widget.runtime ||
        oldWidget._path != widget._path ||
        oldWidget.bundleRoot != widget.bundleRoot ||
        oldWidget.networkUrl != widget.networkUrl ||
        oldWidget.networkBundleRoot != widget.networkBundleRoot ||
        oldWidget.networkFetch != widget.networkFetch ||
        oldWidget.onNetworkLog != widget.onNetworkLog ||
        oldWidget.resourceCache != widget.resourceCache ||
        oldWidget._source != widget._source ||
        oldWidget.initialProps != widget.initialProps ||
        oldWidget.mounts != widget.mounts ||
        oldWidget.uiPlugins != widget.uiPlugins ||
        !_stringIterableSetEquals(
          oldWidget.grantedPermissions,
          widget.grantedPermissions,
        ) ||
        oldWidget.permissionPolicy != widget.permissionPolicy) {
      _scheduleLoad();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _renderer.dispose();
    _eventIngress.dispose();
    _loadCoordinator.dispose();
    _advanceGeneration();
    _controller.removeListener(_handleControllerChanged);
    _performanceController.removeListener(_recordPerformance);
    if (_ownsPerformanceController) _performanceController.dispose();
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
        _sendAppLifecycleSignal(_QuickjsUiAppLifecycleSignal.resumed);
      case AppLifecycleState.inactive:
      case AppLifecycleState.hidden:
      case AppLifecycleState.paused:
        _sendAppLifecycleSignal(_QuickjsUiAppLifecycleSignal.paused);
      case AppLifecycleState.detached:
        _sendAppLifecycleSignal(_QuickjsUiAppLifecycleSignal.detached);
    }
  }

  void _sendAppLifecycleSignal(_QuickjsUiAppLifecycleSignal signal) {
    if (_lastAppLifecycleSignal == signal) {
      return;
    }
    _lastAppLifecycleSignal = signal;
    switch (signal) {
      case _QuickjsUiAppLifecycleSignal.resumed:
        _controller.recordAppLifecycle('resume');
        _renderer.resume();
        unawaited(_controller.lifecycle('resume'));
      case _QuickjsUiAppLifecycleSignal.paused:
        _controller.recordAppLifecycle('pause');
        _renderer.pause();
        unawaited(_controller.lifecycle('pause'));
      case _QuickjsUiAppLifecycleSignal.detached:
        _controller.recordAppLifecycle('detach');
        _renderer.dispose();
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
      if (!_devOptions.showErrorOverlay) {
        return widget.placeholder ?? const SizedBox.shrink();
      }
      return QuickjsUiErrorOverlay(error: error);
    }

    if ((_loadCoordinator.isPending || _controller.isLoading) &&
        _controller.node == null) {
      final loadingBuilder = widget.loadingBuilder;
      if (loadingBuilder != null) {
        return loadingBuilder(context);
      }
      return widget.emptyBuilder?.call(context) ??
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
      _performanceController.updateDisplayRefreshRate(
        View.of(context).display.refreshRate,
      );
      _performanceController.updateDisplayMetrics(
        logicalSize: MediaQuery.sizeOf(context),
        devicePixelRatio: MediaQuery.devicePixelRatioOf(context),
      );
      _performanceController.updateReduceMotion(
        MediaQuery.maybeOf(context)?.disableAnimations ?? false,
      );
      final rendered = _renderer.build(node, buildContext: context);
      _controller.inspector.recordPerformance(_performanceController.snapshot);
      if (_devOptions.logSchema) {
        QuickjsUiDiag.log('schema', node.toMap().toString());
      }
      _reportFirstRender();
      return rendered;
    } catch (error, stackTrace) {
      return _buildError(
        context,
        error,
        stackTrace: stackTrace,
        schemaPath: 'root',
      );
    }
  }

  Widget _buildError(
    BuildContext context,
    Object error, {
    StackTrace? stackTrace,
    String? schemaPath,
  }) {
    final unified = QuickjsUiError.wrap(
      error,
      kind: QuickjsUiErrorKind.render,
      stackTrace: stackTrace,
      context: _errorContext(schemaPath: schemaPath, operation: 'render'),
    );
    _controller.inspector.recordError(unified);
    final builder = widget.errorBuilder;
    if (builder != null) {
      return builder(context, unified);
    }
    if (!_devOptions.showErrorOverlay) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return QuickjsUiErrorOverlay(error: unified);
  }

  QuickjsUiErrorContext _errorContext({String? schemaPath, String? operation}) {
    return QuickjsUiErrorContext(
      operation: operation,
      source: widget._source.name,
      resource: widget.networkUrl?.toString() ?? widget._path,
      schemaPath: schemaPath,
    );
  }

  void _reportFirstRender() {
    if (_reportedFirstRender) {
      return;
    }
    final generation = _generation;
    _reportedFirstRender = true;
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      await _controller.lifecycle('mount');
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      await _showAfterFirstRender(generation);
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      widget.onFirstRender?.call();
    });
  }

  Future<void> _showAfterFirstRender(int generation) async {
    if (!_isCurrentGeneration(generation) ||
        _reportedShow ||
        _controller.plugin == null ||
        _controller.isDisposed) {
      return;
    }
    _reportedShow = true;
    await _controller.routeLifecycle('show');
    if (!_isCurrentGeneration(generation)) {
      return;
    }
    _renderer.show();
  }

  Future<void> _load() async {
    final generation = _advanceGeneration();
    try {
      if (!_isCurrentGeneration(generation)) {
        return;
      }
      final plugin = widget.plugin;
      if (plugin != null) {
        await _controller.loadPlugin(
          plugin,
          initialProps: widget.initialProps,
          mounts: _effectiveMounts(),
          grantedPermissions: widget.grantedPermissions,
          permissionPolicy: widget.permissionPolicy,
          errorContext: _errorContext(operation: 'load', schemaPath: 'root'),
          notifyLoading: false,
        );
        if (!_isCurrentGeneration(generation)) {
          return;
        }
        return;
      }
      await _controller.load(
        _loadPlugin,
        initialProps: widget.initialProps,
        mounts: _effectiveMounts(),
        grantedPermissions: widget.grantedPermissions,
        permissionPolicy: widget.permissionPolicy,
        errorContext: _errorContext(operation: 'load', schemaPath: 'root'),
        notifyLoading: false,
      );
    } catch (error, stackTrace) {
      if (_isCurrentGeneration(generation)) {
        _controller.reportError(
          QuickjsUiError.wrap(
            error,
            kind: QuickjsUiErrorKind.load,
            stackTrace: stackTrace,
            context: _errorContext(operation: 'load', schemaPath: 'root'),
          ),
        );
      }
    }
  }

  void _scheduleLoad({bool immediate = false}) {
    _loadCoordinator.schedule(_load, immediate: immediate);
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
    return (widget.resourceCache ?? QuickjsUiResourceCache.shared).loadAsset(
      path: path,
      bundleRoot: widget.bundleRoot,
    );
  }

  Future<QuickjsPlugin> _loadNetworkPlugin(Uri url) async {
    return (widget.resourceCache ?? QuickjsUiResourceCache.shared).loadNetwork(
      url: url,
      bundleRoot: widget.networkBundleRoot,
      fetch: widget.networkFetch,
      onLog: _handleNetworkLog,
    );
  }

  Future<QuickjsPlugin> _loadFilePlugin(String path) async {
    return (widget.resourceCache ?? QuickjsUiResourceCache.shared).loadFile(
      path: path,
      bundleRoot: widget.bundleRoot,
    );
  }

  void _handleNetworkLog(QuickjsUiNetworkLogEvent event) {
    widget.onNetworkLog?.call(event);
    _controller.recordNetworkLog(event);
  }

  void _handleControllerChanged() {
    if (mounted) {
      if (_observedPageRevision != _controller.pageRevision) {
        _observedPageRevision = _controller.pageRevision;
        _advanceGeneration();
      }
      setState(() {});
    }
  }

  int _advanceGeneration() {
    _generation += 1;
    _reportedFirstRender = false;
    _reportedShow = false;
    return _generation;
  }

  bool _isCurrentGeneration(int generation) {
    return mounted && generation == _generation && !_controller.isDisposed;
  }
}

enum _QuickjsUiViewSource { plugin, asset, file, network }

enum _QuickjsUiAppLifecycleSignal { resumed, paused, detached }

final class _QuickjsUiLoadCoordinator {
  int _requestId = 0;
  bool _disposed = false;
  bool _pending = false;

  bool get isPending => _pending;

  void schedule(Future<void> Function() load, {bool immediate = false}) {
    if (_disposed) return;
    _pending = true;
    final requestId = ++_requestId;
    void start() {
      if (_disposed || requestId != _requestId) return;
      _pending = false;
      unawaited(load());
    }

    if (immediate) {
      start();
    } else {
      scheduleMicrotask(start);
    }
  }

  void dispose() {
    _disposed = true;
    _pending = false;
    _requestId += 1;
  }
}

bool _stringIterableSetEquals(Iterable<String> left, Iterable<String> right) {
  final leftSet = left.toSet();
  final rightSet = right.toSet();
  return leftSet.length == rightSet.length && leftSet.containsAll(rightSet);
}
