import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

import '../resource/quickjs_ui_resource_resolver.dart';
import '../renderer/quickjs_ui_component_registry.dart';
import '../runtime/quickjs_ui_controller.dart';
import '../view/quickjs_ui_view.dart';

typedef QuickjsUiNativeRouteBuilder =
    Widget Function(BuildContext context, Map<String, Object?> params);

typedef QuickjsUiJsRouteGuard =
    FutureOr<bool> Function(QuickjsUiJsRouteRequest request);

enum QuickjsUiRouteTransitionKind { material, none, fade, slide, scale }

final class QuickjsUiRouteTransition {
  const QuickjsUiRouteTransition({
    required this.kind,
    this.duration = const Duration(milliseconds: 300),
    this.reverseDuration,
    this.curve = Curves.easeInOut,
    this.beginOffset = const Offset(1, 0),
    this.beginScale = 0.92,
  });

  const QuickjsUiRouteTransition.material()
    : this(kind: QuickjsUiRouteTransitionKind.material);

  const QuickjsUiRouteTransition.none()
    : this(
        kind: QuickjsUiRouteTransitionKind.none,
        duration: Duration.zero,
        reverseDuration: Duration.zero,
        curve: Curves.linear,
      );

  const QuickjsUiRouteTransition.fade({
    Duration duration = const Duration(milliseconds: 220),
    Duration? reverseDuration,
    Curve curve = Curves.easeInOut,
  }) : this(
         kind: QuickjsUiRouteTransitionKind.fade,
         duration: duration,
         reverseDuration: reverseDuration,
         curve: curve,
       );

  const QuickjsUiRouteTransition.slide({
    Duration duration = const Duration(milliseconds: 260),
    Duration? reverseDuration,
    Curve curve = Curves.easeOutCubic,
    Offset beginOffset = const Offset(1, 0),
  }) : this(
         kind: QuickjsUiRouteTransitionKind.slide,
         duration: duration,
         reverseDuration: reverseDuration,
         curve: curve,
         beginOffset: beginOffset,
       );

  const QuickjsUiRouteTransition.scale({
    Duration duration = const Duration(milliseconds: 220),
    Duration? reverseDuration,
    Curve curve = Curves.easeOutCubic,
    double beginScale = 0.92,
  }) : this(
         kind: QuickjsUiRouteTransitionKind.scale,
         duration: duration,
         reverseDuration: reverseDuration,
         curve: curve,
         beginScale: beginScale,
       );

  final QuickjsUiRouteTransitionKind kind;
  final Duration duration;
  final Duration? reverseDuration;
  final Curve curve;
  final Offset beginOffset;
  final double beginScale;
}

final class QuickjsUiJsRouteRequest {
  const QuickjsUiJsRouteRequest({
    required this.route,
    required this.path,
    required this.resolvedPath,
    required this.from,
    required this.action,
    required this.params,
    required this.isRegistered,
  });

  final String route;
  final String? path;
  final String resolvedPath;
  final String from;
  final String action;
  final Map<String, Object?> params;
  final bool isRegistered;
}

final class QuickjsUiJsRoutePolicy {
  const QuickjsUiJsRoutePolicy({
    this.allowedRoutes = const <String>{},
    this.allowedPaths = const <String>{},
    this.onRequest,
  });

  final Set<String> allowedRoutes;
  final Set<String> allowedPaths;
  final QuickjsUiJsRouteGuard? onRequest;

  Future<bool> allows(QuickjsUiJsRouteRequest request) async {
    if (!_matchesStaticRules(request)) {
      return false;
    }
    final guard = onRequest;
    if (guard == null) {
      return true;
    }
    return guard(request);
  }

  bool _matchesStaticRules(QuickjsUiJsRouteRequest request) {
    if (allowedRoutes.isEmpty && allowedPaths.isEmpty) {
      return true;
    }
    return allowedRoutes.contains(request.route) ||
        allowedPaths.contains(request.resolvedPath) ||
        (request.path != null && allowedPaths.contains(request.path));
  }
}

final class QuickjsUiRouteRegistry {
  const QuickjsUiRouteRegistry({
    this.nativeRoutes = const <String, QuickjsUiNativeRouteBuilder>{},
    this.jsRoutes = const <String, QuickjsUiAssetRoute>{},
    this.jsRoutePolicy = const QuickjsUiJsRoutePolicy(),
  });

  final Map<String, QuickjsUiNativeRouteBuilder> nativeRoutes;
  final Map<String, QuickjsUiAssetRoute> jsRoutes;
  final QuickjsUiJsRoutePolicy jsRoutePolicy;

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
    this.transition,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final List<QuickjsHostMount> mounts;
  final QuickjsUiRouteTransition? transition;
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
    QuickjsUiRouteTransition? transition,
    QuickjsUiComponentRegistry? registry,
    QuickjsConsoleSink? onConsole,
    QuickjsUiRouteRegistry? routeRegistry,
  }) {
    return Navigator.of(context).push<Object?>(
      _quickjsUiRoute<Object?>(
        settings: RouteSettings(name: title ?? path, arguments: initialProps),
        transition: transition,
        builder: (context) => _QuickjsUiAssetRoutePage(
          title: title,
          path: path,
          bundleRoot: bundleRoot,
          initialProps: initialProps,
          mounts: mounts,
          transition: transition,
          registry: registry,
          onConsole: onConsole,
          routeRegistry: routeRegistry,
        ),
      ),
    );
  }

  static Future<Object?> pushIntent(
    BuildContext context, {
    required QuickjsUiRouteRegistry registry,
    required Map<String, Object?> intent,
    QuickjsUiComponentRegistry? rendererRegistry,
  }) {
    final route = _routeName(intent);
    final params = _params(intent['params']);
    final transition = _transitionFromIntent(intent['transition']);
    final nativeBuilder = registry.nativeRoutes[route];
    if (nativeBuilder != null) {
      return Navigator.of(context).push<Object?>(
        _quickjsUiRoute<Object?>(
          settings: RouteSettings(name: route, arguments: params),
          transition: transition,
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
        transition: transition ?? jsRoute.transition,
        registry: rendererRegistry,
        routeRegistry: registry,
      );
    }
    throw StateError('quickjs_ui route "$route" is not registered');
  }

  static Future<Object?> Function(Map<String, Object?> intent)
  navigationHandler(
    BuildContext context,
    QuickjsUiRouteRegistry registry, {
    QuickjsUiComponentRegistry? rendererRegistry,
  }) {
    return (intent) => pushIntent(
      context,
      registry: registry,
      intent: intent,
      rendererRegistry: rendererRegistry,
    );
  }
}

class _QuickjsUiAssetRoutePage extends StatelessWidget {
  const _QuickjsUiAssetRoutePage({
    required this.path,
    required this.initialProps,
    required this.mounts,
    this.bundleRoot,
    this.title,
    this.transition,
    this.registry,
    this.onConsole,
    this.routeRegistry,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;
  final QuickjsUiRouteTransition? transition;
  final QuickjsUiComponentRegistry? registry;
  final QuickjsConsoleSink? onConsole;
  final QuickjsUiRouteRegistry? routeRegistry;

  @override
  Widget build(BuildContext context) {
    final routeRegistry = this.routeRegistry;
    final content = routeRegistry == null
        ? QuickjsUiView.asset(
            path: path,
            bundleRoot: bundleRoot,
            initialProps: initialProps,
            mounts: mounts,
            registry: registry,
            onConsole: onConsole,
            loadingBuilder: (_) =>
                const Center(child: CircularProgressIndicator()),
          )
        : _QuickjsUiRouter(
            root: QuickjsUiAssetRoute(
              path: path,
              bundleRoot: bundleRoot,
              title: title,
              mounts: mounts,
              transition: transition,
            ),
            initialProps: initialProps,
            registry: routeRegistry,
            rendererRegistry: this.registry,
            onConsole: onConsole,
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
    this.rendererRegistry,
    this.onConsole,
  });

  final QuickjsUiAssetRoute root;
  final Map<String, Object?> initialProps;
  final QuickjsUiRouteRegistry registry;
  final QuickjsUiComponentRegistry? rendererRegistry;
  final QuickjsConsoleSink? onConsole;

  @override
  State<_QuickjsUiRouter> createState() => _QuickjsUiRouterState();
}

class _QuickjsUiRouterState extends State<_QuickjsUiRouter> {
  late final _QuickjsUiRouteStack _routes;

  @override
  void initState() {
    super.initState();
    _routes = _QuickjsUiRouteStack(
      root: widget.root,
      initialProps: widget.initialProps,
      onConsole: widget.onConsole,
    );
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root.path != widget.root.path ||
        oldWidget.root.bundleRoot != widget.root.bundleRoot ||
        oldWidget.initialProps != widget.initialProps) {
      _routes.reset(
        root: widget.root,
        initialProps: widget.initialProps,
        onConsole: widget.onConsole,
      );
    }
  }

  @override
  void dispose() {
    _routes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Keep compatibility with the package's older Flutter lower bound.
    // ignore: deprecated_member_use
    return WillPopScope(
      onWillPop: () async {
        if (_routes.length <= 1) {
          return true;
        }
        await _popJsRoute(null, waitForRouteLeave: true);
        return false;
      },
      child: IndexedStack(
        index: _routes.length - 1,
        children: <Widget>[
          for (final entry in _routes.entries)
            QuickjsUiView.asset(
              key: entry.key,
              path: entry.route.path,
              bundleRoot: entry.route.bundleRoot,
              initialProps: entry.params,
              mounts: _mountsFor(entry),
              controller: entry.controller,
              registry: widget.rendererRegistry,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
              onFirstRender: () => _routeEnter(entry),
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
    return entry.mounts = <QuickjsHostMount>[
      ...entry.route.mounts,
      _navigationMountFor(entry),
    ];
  }

  QuickjsHostMount _navigationMountFor(_QuickjsUiRouterEntry source) {
    return QuickjsHostMount(
      name: 'quickjs_ui:router:${source.id}',
      providers: <QuickjsHostProvider>[
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.push',
          debugName: 'quickjs_ui navigation push',
          callback: (args, _) {
            return _handleNavigationIntent(
              source: source,
              intent: _navigationIntent(
                args.isEmpty ? null : args[0],
                args.length > 1 ? args[1] : null,
              ),
            );
          },
        ),
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.replace',
          debugName: 'quickjs_ui navigation replace',
          callback: (args, _) {
            return _handleNavigationIntent(
              source: source,
              intent: _navigationIntent(
                args.isEmpty ? null : args[0],
                args.length > 1 ? args[1] : null,
              ),
              replace: true,
            );
          },
        ),
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.pop',
          debugName: 'quickjs_ui navigation pop',
          callback: (args, _) {
            _ensureNavigationSource(source, 'pop');
            return _popJsRoute(args.isEmpty ? null : args[0]);
          },
        ),
      ],
      environmentPatches: <QuickjsHostScript>[
        QuickjsHostScript.js(
          name: 'quickjs_ui:router:${source.id}:globals.js',
          globals: const <String>['quickjsUiNavigation'],
          source:
              '''
(() => {
  const providers = globalThis.__quickjsHostProviders;
  globalThis.quickjsUiNavigation = Object.freeze({
    push(target, params) {
      return providers['quickjs_ui.navigation.${source.id}.push'](target, params);
    },
    replace(target, params) {
      return providers['quickjs_ui.navigation.${source.id}.replace'](target, params);
    },
    pop(result) {
      return providers['quickjs_ui.navigation.${source.id}.pop'](result);
    }
  });
})();
''',
        ),
      ],
    );
  }

  Future<Object?> _handleNavigationIntent({
    required _QuickjsUiRouterEntry source,
    required Map<String, Object?> intent,
    bool replace = false,
  }) async {
    _lockNavigationSource(source, replace ? 'replace' : 'push');
    try {
      final routeName = _routeName(intent);
      final params = _params(intent['params']);
      final transition = _transitionFromIntent(intent['transition']);
      final nativeBuilder = widget.registry.nativeRoutes[routeName];
      if (nativeBuilder != null) {
        final route = _quickjsUiRoute<Object?>(
          settings: RouteSettings(name: routeName, arguments: params),
          transition: transition,
          builder: (context) => nativeBuilder(context, params),
        );
        if (replace) {
          unawaited(
            _sendRouteLeave(
              source,
              to: routeName,
              params: params,
              action: 'replace',
            ),
          );
          unawaited(
            Navigator.of(context).pushReplacement<Object?, Object?>(route),
          );
          return true;
        }
        unawaited(
          _sendRouteLeave(
            source,
            to: routeName,
            params: params,
            action: 'push',
          ),
        );
        final result = await Navigator.of(context).push<Object?>(route);
        source.navigationLocked = false;
        _scheduleRouteResultAndEnter(
          source,
          from: routeName,
          result: result,
          action: 'push',
        );
        return result;
      }

      final jsRoute = _jsRoute(source, intent, routeName);
      if (jsRoute != null) {
        await _ensureJsRouteAllowed(
          source: source,
          intent: intent,
          route: jsRoute,
          routeName: routeName,
          params: params,
          action: replace ? 'replace' : 'push',
        );
        if (replace) {
          unawaited(
            _sendRouteLeave(
              source,
              to: _routeIdentity(jsRoute),
              params: params,
              action: 'replace',
            ),
          );
          _replaceJsRoute(jsRoute, params);
          return true;
        }
        unawaited(
          _sendRouteLeave(
            source,
            to: _routeIdentity(jsRoute),
            params: params,
            action: 'push',
          ),
        );
        return _pushJsRoute(source, jsRoute, params);
      }
      throw StateError('quickjs_ui route "$routeName" is not registered');
    } catch (_) {
      source.navigationLocked = false;
      rethrow;
    }
  }

  Future<Object?> _pushJsRoute(
    _QuickjsUiRouterEntry source,
    QuickjsUiAssetRoute route,
    Map<String, Object?> params,
  ) {
    assert(source.navigationLocked);
    final result = _routes.push(
      route: route,
      params: params,
      onConsole: widget.onConsole,
    );
    setState(() {
      // The route stack is already mutated by _routes.push().
    });
    return result;
  }

  bool _replaceJsRoute(QuickjsUiAssetRoute route, Map<String, Object?> params) {
    _routes.replace(route: route, params: params, onConsole: widget.onConsole);
    setState(() {
      // The route stack is already mutated by _routes.replace().
    });
    return true;
  }

  Future<bool> _popJsRoute(
    Object? result, {
    bool waitForRouteLeave = false,
  }) async {
    if (_routes.length <= 1) {
      final root = _routes.top;
      final navigator = Navigator.of(context);
      final routeLeave = _sendRouteLeave(
        root,
        to: 'native',
        result: result,
        action: 'pop',
      );
      if (!waitForRouteLeave) {
        unawaited(
          routeLeave.whenComplete(() {
            if (mounted) {
              navigator.pop(result);
            }
          }),
        );
        return true;
      }
      await routeLeave;
      navigator.pop(result);
      return true;
    }
    final entry = _routes.top;
    final previous = _routes.previous;
    final from = _entryRouteIdentity(entry);
    final routeLeave = _sendRouteLeave(
      entry,
      to: _entryRouteIdentity(previous),
      result: result,
      action: 'pop',
    );
    if (!waitForRouteLeave) {
      unawaited(
        routeLeave.whenComplete(() {
          _finishJsRoutePop(
            entry: entry,
            previous: previous,
            from: from,
            result: result,
          );
        }),
      );
      return true;
    }
    await routeLeave;
    _finishJsRoutePop(
      entry: entry,
      previous: previous,
      from: from,
      result: result,
    );
    return true;
  }

  void _finishJsRoutePop({
    required _QuickjsUiRouterEntry entry,
    required _QuickjsUiRouterEntry previous,
    required String from,
    Object? result,
  }) {
    if (!mounted || _routes.isEmpty || !identical(_routes.top, entry)) {
      entry.dispose();
      return;
    }
    _routes.removeTop();
    previous.navigationLocked = false;
    entry.complete(result);
    entry.dispose();
    if (mounted) {
      setState(() {});
    }
    _scheduleRouteResultAndEnter(
      previous,
      from: from,
      result: result,
      action: 'pop',
    );
  }

  void _routeEnter(
    _QuickjsUiRouterEntry entry, {
    String? from,
    Object? result,
  }) {
    if (!mounted || entry.controller.isDisposed) {
      return;
    }
    final payload = <String, Object?>{
      'route': _entryRouteIdentity(entry),
      'params': entry.params,
    };
    if (from != null) {
      payload['from'] = from;
      payload['result'] = result;
    }
    unawaited(entry.controller.routeLifecycle('routeEnter', payload: payload));
  }

  Future<void> _sendRouteLeave(
    _QuickjsUiRouterEntry entry, {
    required String to,
    Map<String, Object?>? params,
    Object? result,
    required String action,
  }) {
    if (!mounted || entry.controller.isDisposed) {
      return Future<void>.value();
    }
    final payload = <String, Object?>{
      'from': _entryRouteIdentity(entry),
      'to': to,
      'action': action,
    };
    if (params != null) {
      payload['params'] = params;
    }
    if (action == 'pop') {
      payload['result'] = result;
    }
    return entry.controller.routeLifecycle('routeLeave', payload: payload);
  }

  void _scheduleRouteResultAndEnter(
    _QuickjsUiRouterEntry entry, {
    required String from,
    Object? result,
    required String action,
  }) {
    unawaited(() async {
      if (!mounted || entry.controller.isDisposed) {
        return;
      }
      await entry.controller.routeLifecycle(
        'routeResult',
        payload: <String, Object?>{
          'from': from,
          'route': _entryRouteIdentity(entry),
          'action': action,
          'result': result,
        },
      );
      _routeEnter(entry, from: from, result: result);
    }());
  }

  QuickjsUiAssetRoute? _jsRoute(
    _QuickjsUiRouterEntry source,
    Map<String, Object?> intent,
    String routeName,
  ) {
    final transition = _transitionFromIntent(intent['transition']);
    final registered = widget.registry.jsRoutes[routeName];
    if (registered != null) {
      if (transition == null) {
        return registered;
      }
      return QuickjsUiAssetRoute(
        path: registered.path,
        bundleRoot: registered.bundleRoot,
        title: registered.title,
        mounts: registered.mounts,
        transition: transition,
      );
    }
    final path = intent['path'];
    if (path is String && path.isNotEmpty) {
      final currentRoute = source.route;
      final bundleRoot = intent['bundleRoot'];
      final title = intent['title'];
      return QuickjsUiAssetRoute(
        path: _resolveJsRoutePath(path, from: currentRoute.path),
        bundleRoot: bundleRoot is String ? bundleRoot : currentRoute.bundleRoot,
        title: title is String ? title : null,
        mounts: currentRoute.mounts,
        transition: transition,
      );
    }
    return null;
  }

  Future<void> _ensureJsRouteAllowed({
    required _QuickjsUiRouterEntry source,
    required Map<String, Object?> intent,
    required QuickjsUiAssetRoute route,
    required String routeName,
    required Map<String, Object?> params,
    required String action,
  }) async {
    final path = intent['path'];
    final request = QuickjsUiJsRouteRequest(
      route: routeName,
      path: path is String ? path : null,
      resolvedPath: route.path,
      from: _entryRouteIdentity(source),
      action: action,
      params: params,
      isRegistered: widget.registry.jsRoutes.containsKey(routeName),
    );
    final allowed = await widget.registry.jsRoutePolicy.allows(request);
    if (!allowed) {
      throw StateError(
        'quickjs_ui JS route "$routeName" was rejected by host policy',
      );
    }
  }

  void _ensureNavigationSource(_QuickjsUiRouterEntry source, String action) {
    if (_routes.isEmpty || !identical(_routes.top, source)) {
      throw StateError(
        'quickjs_ui navigation.$action was ignored because the page is no longer current',
      );
    }
    if (source.navigationLocked) {
      throw StateError(
        'quickjs_ui navigation.$action was ignored because another navigation is pending',
      );
    }
  }

  void _lockNavigationSource(_QuickjsUiRouterEntry source, String action) {
    _ensureNavigationSource(source, action);
    source.navigationLocked = true;
  }
}

final class _QuickjsUiRouteStack {
  _QuickjsUiRouteStack({
    required QuickjsUiAssetRoute root,
    required Map<String, Object?> initialProps,
    QuickjsConsoleSink? onConsole,
  }) {
    reset(root: root, initialProps: initialProps, onConsole: onConsole);
  }

  final List<_QuickjsUiRouterEntry> _entries = <_QuickjsUiRouterEntry>[];

  List<_QuickjsUiRouterEntry> get entries {
    return List<_QuickjsUiRouterEntry>.unmodifiable(_entries);
  }

  int get length => _entries.length;
  bool get isEmpty => _entries.isEmpty;
  _QuickjsUiRouterEntry get top => _entries.last;
  _QuickjsUiRouterEntry get previous => _entries[_entries.length - 2];

  void reset({
    required QuickjsUiAssetRoute root,
    required Map<String, Object?> initialProps,
    QuickjsConsoleSink? onConsole,
  }) {
    dispose();
    _entries.add(
      _QuickjsUiRouterEntry(
        route: root,
        params: initialProps,
        onConsole: onConsole,
      ),
    );
  }

  Future<Object?> push({
    required QuickjsUiAssetRoute route,
    required Map<String, Object?> params,
    QuickjsConsoleSink? onConsole,
  }) {
    final result = Completer<Object?>();
    _entries.add(
      _QuickjsUiRouterEntry(
        route: route,
        params: params,
        result: result,
        onConsole: onConsole,
      ),
    );
    return result.future;
  }

  void replace({
    required QuickjsUiAssetRoute route,
    required Map<String, Object?> params,
    QuickjsConsoleSink? onConsole,
  }) {
    final current = _entries.removeLast();
    current.complete(null);
    _entries.add(
      _QuickjsUiRouterEntry(route: route, params: params, onConsole: onConsole),
    );
    current.dispose();
  }

  _QuickjsUiRouterEntry removeTop() {
    return _entries.removeLast();
  }

  void dispose() {
    for (final entry in _entries) {
      entry.complete(null);
      entry.dispose();
    }
    _entries.clear();
  }
}

final class _QuickjsUiRouterEntry {
  _QuickjsUiRouterEntry({
    required this.route,
    required this.params,
    QuickjsConsoleSink? onConsole,
    this.result,
  }) : id = _nextQuickjsUiRouterEntryId++,
       controller = QuickjsUiController(onConsole: onConsole);

  final int id;
  final QuickjsUiAssetRoute route;
  final Map<String, Object?> params;
  final Completer<Object?>? result;
  final QuickjsUiController controller;
  final GlobalKey key = GlobalKey();
  List<QuickjsHostMount>? mounts;
  bool navigationLocked = false;

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

int _nextQuickjsUiRouterEntryId = 0;

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

PageRoute<T> _quickjsUiRoute<T>({
  required RouteSettings settings,
  required WidgetBuilder builder,
  QuickjsUiRouteTransition? transition,
}) {
  if (transition == null ||
      transition.kind == QuickjsUiRouteTransitionKind.material) {
    return MaterialPageRoute<T>(settings: settings, builder: builder);
  }
  return PageRouteBuilder<T>(
    settings: settings,
    transitionDuration: transition.duration,
    reverseTransitionDuration:
        transition.reverseDuration ?? transition.duration,
    pageBuilder: (context, _, _) => builder(context),
    transitionsBuilder: (context, animation, _, child) {
      final curved = CurvedAnimation(
        parent: animation,
        curve: transition.curve,
        reverseCurve: transition.curve,
      );
      switch (transition.kind) {
        case QuickjsUiRouteTransitionKind.material:
          return child;
        case QuickjsUiRouteTransitionKind.none:
          return child;
        case QuickjsUiRouteTransitionKind.fade:
          return FadeTransition(opacity: curved, child: child);
        case QuickjsUiRouteTransitionKind.slide:
          return SlideTransition(
            position: Tween<Offset>(
              begin: transition.beginOffset,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
        case QuickjsUiRouteTransitionKind.scale:
          return ScaleTransition(
            scale: Tween<double>(
              begin: transition.beginScale,
              end: 1,
            ).animate(curved),
            child: FadeTransition(opacity: curved, child: child),
          );
      }
    },
  );
}

QuickjsUiRouteTransition? _transitionFromIntent(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is QuickjsUiRouteTransition) {
    return value;
  }
  if (value is String) {
    return _transitionFromMap(<String, Object?>{'type': value});
  }
  if (value is! Map) {
    throw ArgumentError('quickjs_ui navigation transition must be an object');
  }
  return _transitionFromMap(
    value.map((key, value) => MapEntry<String, Object?>('$key', value)),
  );
}

QuickjsUiRouteTransition _transitionFromMap(Map<String, Object?> value) {
  final type = value['type'] ?? value['kind'];
  if (type is! String || type.isEmpty) {
    throw ArgumentError('quickjs_ui navigation transition "type" is required');
  }
  final duration = _durationFromMs(value['durationMs'] ?? value['duration']);
  final reverseDuration = _durationFromMs(value['reverseDurationMs']);
  final curve = _curveFromName(value['curve']);
  switch (type) {
    case 'material':
      return const QuickjsUiRouteTransition.material();
    case 'none':
      return const QuickjsUiRouteTransition.none();
    case 'fade':
      return QuickjsUiRouteTransition.fade(
        duration: duration ?? const Duration(milliseconds: 220),
        reverseDuration: reverseDuration,
        curve: curve,
      );
    case 'slide':
      return QuickjsUiRouteTransition.slide(
        duration: duration ?? const Duration(milliseconds: 260),
        reverseDuration: reverseDuration,
        curve: curve,
        beginOffset: _transitionBeginOffset(value),
      );
    case 'scale':
      return QuickjsUiRouteTransition.scale(
        duration: duration ?? const Duration(milliseconds: 220),
        reverseDuration: reverseDuration,
        curve: curve,
        beginScale: _transitionBeginScale(value['beginScale']),
      );
  }
  throw ArgumentError('Unsupported quickjs_ui transition type "$type"');
}

Duration? _durationFromMs(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! num || value < 0) {
    throw ArgumentError('quickjs_ui transition duration must be >= 0');
  }
  return Duration(milliseconds: value.round());
}

Curve _curveFromName(Object? value) {
  if (value == null) {
    return Curves.easeInOut;
  }
  if (value is! String) {
    throw ArgumentError('quickjs_ui transition curve must be a string');
  }
  switch (value) {
    case 'linear':
      return Curves.linear;
    case 'easeIn':
      return Curves.easeIn;
    case 'easeOut':
      return Curves.easeOut;
    case 'easeInOut':
      return Curves.easeInOut;
    case 'fastOutSlowIn':
      return Curves.fastOutSlowIn;
    case 'easeOutCubic':
      return Curves.easeOutCubic;
  }
  throw ArgumentError('Unsupported quickjs_ui transition curve "$value"');
}

Offset _transitionBeginOffset(Map<String, Object?> value) {
  final offset = value['beginOffset'];
  if (offset is Map) {
    final dx = offset['dx'];
    final dy = offset['dy'];
    if (dx is num && dy is num) {
      return Offset(dx.toDouble(), dy.toDouble());
    }
    throw ArgumentError(
      'quickjs_ui transition beginOffset must include numeric dx and dy',
    );
  }
  final from = value['from'] ?? value['direction'];
  if (from == null) {
    return const Offset(1, 0);
  }
  if (from is! String) {
    throw ArgumentError('quickjs_ui transition from must be a string');
  }
  switch (from) {
    case 'right':
    case 'rightToLeft':
      return const Offset(1, 0);
    case 'left':
    case 'leftToRight':
      return const Offset(-1, 0);
    case 'top':
    case 'up':
    case 'topToBottom':
      return const Offset(0, -1);
    case 'bottom':
    case 'down':
    case 'bottomToTop':
      return const Offset(0, 1);
  }
  throw ArgumentError('Unsupported quickjs_ui transition from "$from"');
}

double _transitionBeginScale(Object? value) {
  if (value == null) {
    return 0.92;
  }
  if (value is! num || value <= 0) {
    throw ArgumentError('quickjs_ui transition beginScale must be > 0');
  }
  return value.toDouble();
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

String _entryRouteIdentity(_QuickjsUiRouterEntry entry) {
  return _routeIdentity(entry.route);
}

String _routeIdentity(QuickjsUiAssetRoute route) {
  return route.title ?? route.path;
}
