import 'package:flutter/widgets.dart';
import 'package:flutter/foundation.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'extension_session.dart';

/// 渲染统一扩展中某个已声明 JSUI 路由的组件。
final class JsExtensionView extends StatefulWidget {
  /// Creates a view for a declared extension [route].
  const JsExtensionView.route({
    super.key,
    required this.session,
    required this.route,
    this.initialProps = const <String, Object?>{},
    this.routeFeatures = const <JsFeatures>[],
    this.controller,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
  });

  /// Installed extension session that owns the route.
  final JsExtensionSession session;

  /// Route identifier declared by the extension manifest.
  final String route;

  /// Initial props passed to the route's root component.
  final Map<String, Object?> initialProps;

  /// Temporary host features available only to this route view.
  final List<JsFeatures> routeFeatures;

  /// Optional externally owned page controller.
  final JsUiController? controller;

  /// Widget displayed before the first page frame.
  final Widget? placeholder;

  /// Builds the loading state.
  final JsUiLoadingBuilder? loadingBuilder;

  /// Builds the error state.
  final JsUiErrorBuilder? errorBuilder;

  /// Builds the empty page state.
  final JsUiEmptyBuilder? emptyBuilder;

  /// Called after the first successful render.
  final VoidCallback? onFirstRender;

  @override
  State<JsExtensionView> createState() => _JsExtensionViewState();
}

class _JsExtensionViewState extends State<JsExtensionView> {
  late JsPlugin _plugin;
  late List<JsFeatures> _features;
  late JsUiController _controller;
  bool _ownsController = false;
  @override
  void initState() {
    super.initState();
    _attach();
    if (widget.session.uiEnabled.value) _prepare();
  }

  void _attach() {
    _controller = widget.controller ?? JsUiController();
    _ownsController = widget.controller == null;
    widget.session.uiEnabled.addListener(_availabilityChanged);
    widget.session.addUiRevoker(_revokePage);
  }

  Future<void> _revokePage() => _controller.unload();

  void _availabilityChanged() {
    if (!mounted) return;
    if (widget.session.uiEnabled.value) _prepare();
    setState(() {});
  }

  void _detach(JsExtensionView source) {
    source.session.uiEnabled.removeListener(_availabilityChanged);
    source.session.removeUiRevoker(_revokePage);
    if (_ownsController) {
      _controller.dispose();
    } else if (!_controller.isDisposed) {
      _controller.unload();
    }
  }

  @override
  void dispose() {
    _detach(widget);
    super.dispose();
  }

  @override
  void didUpdateWidget(covariant JsExtensionView oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.session != widget.session ||
        oldWidget.controller != widget.controller) {
      _detach(oldWidget);
      _attach();
    }
    if (oldWidget.session != widget.session ||
        oldWidget.route != widget.route ||
        !listEquals(oldWidget.routeFeatures, widget.routeFeatures)) {
      if (widget.session.uiEnabled.value) _prepare();
    }
  }

  void _prepare() {
    final ui = widget.session.extension.ui;
    if (ui == null) {
      throw StateError('Extension "${widget.session.id}" has no UI component');
    }
    final routeManifest = ui.routes[widget.route];
    if (routeManifest == null) {
      throw StateError(
        'Extension "${widget.session.id}" has no UI route "${widget.route}"',
      );
    }
    final bundle = ui.bundle;
    final entrySpecifier = JsUiResourceResolver.moduleSpecifier(
      bundle.id,
      routeManifest.entry,
    );
    final adapterSpecifier = '${bundle.id}/__extension_route__${widget.route}';
    _plugin = JsPlugin(
      manifest: JsPluginManifest(
        id: bundle.id,
        version: bundle.version,
        entry: adapterSpecifier,
        exports: jsUiPagePluginExports,
        permissions: <String>{
          ...bundle.permissions,
          ...routeManifest.permissions,
        }.toList(growable: false),
      ),
      modules: <JsPluginModule>[
        for (final module in bundle.modules.entries)
          JsPluginModule(
            name: JsUiResourceResolver.moduleSpecifier(bundle.id, module.key),
            source: module.value,
          ),
        JsPluginModule(
          name: adapterSpecifier,
          source: JsUiPagePlugin.adapterSource(entrySpecifier),
        ),
      ],
    );
    _features = widget.session.featuresForRoute(
      widget.route,
      routeFeatures: widget.routeFeatures,
    );
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.session.uiEnabled.value) {
      return widget.placeholder ?? const SizedBox.shrink();
    }
    return JsUiView.plugin(
      _plugin,
      initialProps: widget.initialProps,
      features: _features,
      uiPlugins: widget.session.extension.ui!.plugins,
      grantedPermissions: widget.session.grantedPermissions,
      controller: _controller,
      placeholder: widget.placeholder,
      loadingBuilder: widget.loadingBuilder,
      errorBuilder: widget.errorBuilder,
      emptyBuilder: widget.emptyBuilder,
      onFirstRender: widget.onFirstRender,
    );
  }
}
