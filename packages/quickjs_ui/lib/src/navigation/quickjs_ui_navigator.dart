import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

import '../host/quickjs_ui_host_capabilities.dart';
import '../resource/quickjs_ui_resource_resolver.dart';
import '../runtime/quickjs_ui_controller.dart';
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
    QuickjsUiRouteRegistry? routeRegistry,
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
          routeRegistry: routeRegistry,
        ),
      ),
    );
  }

  static Future<Object?> pushIntent(
    BuildContext context, {
    required QuickjsUiRouteRegistry registry,
    required Map<String, Object?> intent,
  }) {
    final route = _routeName(intent);
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
        routeRegistry: registry,
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
    this.routeRegistry,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;
  final QuickjsUiRouteRegistry? routeRegistry;

  @override
  Widget build(BuildContext context) {
    final registry = routeRegistry;
    final content = registry == null
        ? QuickjsUiView.asset(
            path: path,
            bundleRoot: bundleRoot,
            initialProps: initialProps,
            mounts: mounts,
            loadingBuilder: (_) =>
                const Center(child: CircularProgressIndicator()),
          )
        : _QuickjsUiRouter(
            root: QuickjsUiAssetRoute(
              path: path,
              bundleRoot: bundleRoot,
              title: title,
              mounts: mounts,
            ),
            initialProps: initialProps,
            registry: registry,
          );
    final routeTitle = title;
    if (routeTitle == null) {
      return content;
    }
    return Scaffold(
      appBar: AppBar(title: Text(routeTitle)),
      body: content,
    );
  }
}

class _QuickjsUiRouter extends StatefulWidget {
  const _QuickjsUiRouter({
    required this.root,
    required this.initialProps,
    required this.registry,
  });

  final QuickjsUiAssetRoute root;
  final Map<String, Object?> initialProps;
  final QuickjsUiRouteRegistry registry;

  @override
  State<_QuickjsUiRouter> createState() => _QuickjsUiRouterState();
}

class _QuickjsUiRouterState extends State<_QuickjsUiRouter> {
  final List<_QuickjsUiRouterEntry> _stack = <_QuickjsUiRouterEntry>[];

  @override
  void initState() {
    super.initState();
    _stack.add(
      _QuickjsUiRouterEntry(route: widget.root, params: widget.initialProps),
    );
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root.path != widget.root.path ||
        oldWidget.root.bundleRoot != widget.root.bundleRoot ||
        oldWidget.initialProps != widget.initialProps) {
      for (final entry in _stack) {
        entry.dispose();
      }
      _stack
        ..clear()
        ..add(
          _QuickjsUiRouterEntry(
            route: widget.root,
            params: widget.initialProps,
          ),
        );
    }
  }

  @override
  void dispose() {
    for (final entry in _stack) {
      entry.dispose();
    }
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep compatibility with the package's older Flutter lower bound.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_stack.length <= 1) {
          return true;
        }
        _popJsRoute(null);
        return false;
      },
      child: IndexedStack(
        index: _stack.length - 1,
        children: <Widget>[
          for (final entry in _stack)
            QuickjsUiView.asset(
              key: entry.key,
              path: entry.route.path,
              bundleRoot: entry.route.bundleRoot,
              initialProps: entry.params,
              mounts: _mountsFor(entry),
              controller: entry.controller,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
            ),
        ],
      ),
    );
  }

  List<QuickjsHostMount> _mountsFor(_QuickjsUiRouterEntry entry) {
    final cached = entry.mounts;
    if (cached != null) {
      return cached;
    }
    final capabilities = QuickjsUiHostCapabilities(
      conflictPolicy: QuickjsUiCapabilityConflictPolicy.replace,
      groups: <QuickjsUiCapabilityGroup>[
        QuickjsUiCapabilityGroup.system(
          options: const QuickjsUiHostCapabilityOptions(
            enabled: <QuickjsUiHostCapability>{
              QuickjsUiHostCapability.navigation,
            },
          ),
          handlers: QuickjsUiHostApiHandlers(
            onNavigationIntent: _handleNavigationIntent,
          ),
        ),
        QuickjsUiCapabilityGroup.functions(
          name: 'quickjs_ui:router',
          namespace: 'quickjs_ui.navigation',
          globalName: 'quickjsUiNavigation',
          functions: <String, Function>{
            'push': (Object? target, [Object? params]) {
              return _handleNavigationIntent(_navigationIntent(target, params));
            },
            'replace': (Object? target, [Object? params]) {
              return _handleNavigationIntent(
                _navigationIntent(target, params),
                replace: true,
              );
            },
            'pop': (Object? result) => _popJsRoute(result),
          },
        ),
      ],
    );
    return entry.mounts = <QuickjsHostMount>[
      ...entry.route.mounts,
      ...capabilities.mounts,
    ];
  }

  Future<Object?> _handleNavigationIntent(
    Map<String, Object?> intent, {
    bool replace = false,
  }) {
    final routeName = _routeName(intent);
    final params = _params(intent['params']);
    final nativeBuilder = widget.registry.nativeRoutes[routeName];
    if (nativeBuilder != null) {
      final route = MaterialPageRoute<Object?>(
        settings: RouteSettings(name: routeName, arguments: params),
        builder: (context) => nativeBuilder(context, params),
      );
      if (replace) {
        scheduleMicrotask(() {
          if (mounted) {
            unawaited(
              Navigator.of(context).pushReplacement<Object?, Object?>(route),
            );
          }
        });
        return Future<Object?>.value(true);
      }
      return Navigator.of(context).push<Object?>(route);
    }

    final jsRoute = _jsRoute(intent, routeName);
    if (jsRoute != null) {
      if (replace) {
        scheduleMicrotask(() {
          if (mounted) {
            _replaceJsRoute(jsRoute, params);
          }
        });
        return Future<Object?>.value(true);
      }
      return _pushJsRoute(jsRoute, params);
    }
    throw StateError('quickjs_ui route "$routeName" is not registered');
  }

  Future<Object?> _pushJsRoute(
    QuickjsUiAssetRoute route,
    Map<String, Object?> params,
  ) {
    final entry = _QuickjsUiRouterEntry(
      route: route,
      params: params,
      result: Completer<Object?>(),
    );
    setState(() {
      _stack.add(entry);
    });
    return entry.result!.future;
  }

  bool _replaceJsRoute(QuickjsUiAssetRoute route, Map<String, Object?> params) {
    final current = _stack.removeLast();
    final entry = _QuickjsUiRouterEntry(
      route: route,
      params: params,
      result: current.result,
    );
    setState(() {
      _stack.add(entry);
    });
    current.dispose();
    return true;
  }

  bool _popJsRoute(Object? result) {
    if (_stack.length <= 1) {
      Navigator.of(context).pop(result);
      return true;
    }
    final entry = _stack.removeLast();
    entry.complete(result);
    entry.dispose();
    if (mounted) {
      setState(() {});
    }
    return true;
  }

  QuickjsUiAssetRoute? _jsRoute(Map<String, Object?> intent, String routeName) {
    final registered = widget.registry.jsRoutes[routeName];
    if (registered != null) {
      return registered;
    }
    final path = intent['path'];
    if (path is String && path.isNotEmpty) {
      final currentRoute = _stack.last.route;
      final bundleRoot = intent['bundleRoot'];
      final title = intent['title'];
      return QuickjsUiAssetRoute(
        path: _resolveJsRoutePath(path, from: currentRoute.path),
        bundleRoot: bundleRoot is String ? bundleRoot : currentRoute.bundleRoot,
        title: title is String ? title : null,
        mounts: currentRoute.mounts,
      );
    }
    return null;
  }
}

final class _QuickjsUiRouterEntry {
  _QuickjsUiRouterEntry({
    required this.route,
    required this.params,
    this.result,
  });

  final QuickjsUiAssetRoute route;
  final Map<String, Object?> params;
  final Completer<Object?>? result;
  final QuickjsUiController controller = QuickjsUiController();
  final GlobalKey key = GlobalKey();
  List<QuickjsHostMount>? mounts;

  void complete(Object? value) {
    if (result == null || result!.isCompleted) {
      return;
    }
    result!.complete(value);
  }

  void dispose() {
    if (!controller.isDisposed) {
      controller.dispose();
    }
  }
}

String _routeName(Map<String, Object?> intent) {
  final route = intent['route'];
  if (route is String && route.isNotEmpty) {
    return route;
  }
  final path = intent['path'];
  if (path is String && path.isNotEmpty) {
    return path;
  }
  throw ArgumentError('quickjs_ui navigation target "route" must be a string');
}

Map<String, Object?> _navigationIntent(Object? target, Object? params) {
  if (target is String && target.isNotEmpty) {
    final intent = <String, Object?>{'route': target};
    if (params != null) {
      intent['params'] = params;
    }
    return intent;
  }
  if (target is Map) {
    final intent = target.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    if (params != null) {
      intent['params'] = params;
    }
    return intent;
  }
  throw ArgumentError(
    'quickjs_ui navigation push target must be a string or object',
  );
}

String _resolveJsRoutePath(String path, {required String from}) {
  if (!path.startsWith('./') && !path.startsWith('../')) {
    return path;
  }
  return QuickjsUiResourceResolver.normalizePath(path, from: from);
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
