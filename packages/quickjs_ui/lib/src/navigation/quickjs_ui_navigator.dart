import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

import '../view/quickjs_ui_view.dart';

typedef QuickjsUiNativeRouteBuilder =
    Widget Function(BuildContext context, Map<String, Object?> params);

final class QuickjsUiRouteRegistry {
  const QuickjsUiRouteRegistry({
    this.nativeRoutes = const <String, QuickjsUiNativeRouteBuilder>{},
    this.jsRoutes = const <String, QuickjsUiAssetRoute>{},
  });

  final Map<String, QuickjsUiNativeRouteBuilder> nativeRoutes;
  final Map<String, QuickjsUiAssetRoute> jsRoutes;

  bool contains(String route) {
    return nativeRoutes.containsKey(route) || jsRoutes.containsKey(route);
  }
}

final class QuickjsUiAssetRoute {
  const QuickjsUiAssetRoute({
    required this.path,
    this.bundleRoot,
    this.title,
    this.mounts = const <QuickjsHostMount>[],
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final List<QuickjsHostMount> mounts;
}

final class QuickjsUiNavigator {
  const QuickjsUiNavigator._();

  static Future<Object?> pushAsset(
    BuildContext context, {
    required String path,
    String? bundleRoot,
    String? title,
    Map<String, Object?> initialProps = const <String, Object?>{},
    List<QuickjsHostMount> mounts = const <QuickjsHostMount>[],
  }) {
    return Navigator.of(context).push<Object?>(
      MaterialPageRoute<Object?>(
        settings: RouteSettings(name: title ?? path, arguments: initialProps),
        builder: (context) => _QuickjsUiAssetRoutePage(
          title: title,
          path: path,
          bundleRoot: bundleRoot,
          initialProps: initialProps,
          mounts: mounts,
        ),
      ),
    );
  }

  static Future<Object?> pushIntent(
    BuildContext context, {
    required QuickjsUiRouteRegistry registry,
    required Map<String, Object?> intent,
  }) {
    final route = intent['route'];
    if (route is! String || route.isEmpty) {
      throw ArgumentError(
        'quickjs_ui navigation intent route must be a string',
      );
    }
    final params = _params(intent['params']);
    final nativeBuilder = registry.nativeRoutes[route];
    if (nativeBuilder != null) {
      return Navigator.of(context).push<Object?>(
        MaterialPageRoute<Object?>(
          settings: RouteSettings(name: route, arguments: params),
          builder: (context) => nativeBuilder(context, params),
        ),
      );
    }
    final jsRoute = registry.jsRoutes[route];
    if (jsRoute != null) {
      return pushAsset(
        context,
        path: jsRoute.path,
        bundleRoot: jsRoute.bundleRoot,
        title: jsRoute.title ?? route,
        initialProps: params,
        mounts: jsRoute.mounts,
      );
    }
    throw StateError('quickjs_ui route "$route" is not registered');
  }

  static Future<Object?> Function(Map<String, Object?> intent)
  navigationHandler(BuildContext context, QuickjsUiRouteRegistry registry) {
    return (intent) => pushIntent(context, registry: registry, intent: intent);
  }
}

class _QuickjsUiAssetRoutePage extends StatelessWidget {
  const _QuickjsUiAssetRoutePage({
    required this.path,
    required this.initialProps,
    required this.mounts,
    this.bundleRoot,
    this.title,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;

  @override
  Widget build(BuildContext context) {
    final content = QuickjsUiView.asset(
      path: path,
      bundleRoot: bundleRoot,
      initialProps: initialProps,
      mounts: mounts,
      loadingBuilder: (_) => const Center(child: CircularProgressIndicator()),
    );
    final title = this.title;
    if (title == null) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: content,
    );
  }
}

Map<String, Object?> _params(Object? value) {
  if (value == null) {
    return const <String, Object?>{};
  }
  if (value is! Map) {
    throw ArgumentError('quickjs_ui navigation params must be an object');
  }
  return value.map((key, value) => MapEntry<String, Object?>('$key', value));
}
