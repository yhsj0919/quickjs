import 'package:flutter/widgets.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'extension_session.dart';

/// 渲染统一扩展中某个已声明 JSUI 路由的组件。
final class JsExtensionView extends StatelessWidget {
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
  Widget build(BuildContext context) {
    final ui = session.extension.ui;
    if (ui == null) {
      throw StateError('Extension "${session.id}" has no UI component');
    }
    final routeManifest = ui.routes[route];
    if (routeManifest == null) {
      throw StateError('Extension "${session.id}" has no UI route "$route"');
    }
    final bundle = ui.bundle;
    final entrySpecifier = JsUiResourceResolver.moduleSpecifier(
      bundle.id,
      routeManifest.entry,
    );
    final adapterSpecifier = '${bundle.id}/__extension_route__$route';
    final plugin = JsPlugin(
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
    return JsUiView.plugin(
      plugin,
      initialProps: initialProps,
      features: session.featuresForRoute(route, routeFeatures: routeFeatures),
      uiPlugins: ui.plugins,
      grantedPermissions: session.grantedPermissions,
      controller: controller,
      placeholder: placeholder,
      loadingBuilder: loadingBuilder,
      errorBuilder: errorBuilder,
      emptyBuilder: emptyBuilder,
      onFirstRender: onFirstRender,
    );
  }
}
