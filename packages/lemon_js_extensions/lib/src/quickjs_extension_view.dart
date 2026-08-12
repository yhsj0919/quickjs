import 'package:flutter/widgets.dart';
import 'package:lemon_js/lemon_js.dart';
import 'package:lemon_js_ui/lemon_js_ui.dart';

import 'quickjs_extension_session.dart';

/// 渲染统一扩展中某个已声明 JSUI 路由的组件。
final class QuickjsExtensionView extends StatelessWidget {
  const QuickjsExtensionView.route({
    super.key,
    required this.session,
    required this.route,
    this.initialProps = const <String, Object?>{},
    this.routeMounts = const <QuickjsHostMount>[],
    this.controller,
    this.placeholder,
    this.loadingBuilder,
    this.errorBuilder,
    this.emptyBuilder,
    this.onFirstRender,
  });

  final QuickjsExtensionSession session;
  final String route;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> routeMounts;
  final QuickjsUiController? controller;
  final Widget? placeholder;
  final QuickjsUiLoadingBuilder? loadingBuilder;
  final QuickjsUiErrorBuilder? errorBuilder;
  final QuickjsUiEmptyBuilder? emptyBuilder;
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
    final entrySpecifier = QuickjsUiResourceResolver.moduleSpecifier(
      bundle.id,
      routeManifest.entry,
    );
    final adapterSpecifier = '${bundle.id}/__quickjs_extension_route__$route';
    final plugin = QuickjsPlugin(
      manifest: QuickjsPluginManifest(
        id: bundle.id,
        version: bundle.version,
        entry: adapterSpecifier,
        exports: quickjsUiPagePluginExports,
        permissions: <String>{
          ...bundle.permissions,
          ...routeManifest.permissions,
        }.toList(growable: false),
      ),
      modules: <QuickjsPluginModule>[
        for (final module in bundle.modules.entries)
          QuickjsPluginModule(
            specifier: QuickjsUiResourceResolver.moduleSpecifier(
              bundle.id,
              module.key,
            ),
            source: module.value,
          ),
        QuickjsPluginModule(
          specifier: adapterSpecifier,
          source: QuickjsUiPagePlugin.adapterSource(entrySpecifier),
        ),
      ],
    );
    return QuickjsUiView.plugin(
      plugin,
      initialProps: initialProps,
      mounts: session.mountsForRoute(route, routeMounts: routeMounts),
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
