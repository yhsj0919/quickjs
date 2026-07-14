import 'dart:async';

import 'package:flutter/material.dart';
import 'package:quickjs/quickjs.dart';

import '../resource/quickjs_ui_resource_resolver.dart';
import '../runtime/quickjs_ui_controller.dart';
import '../runtime/quickjs_ui_plugin.dart';
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
    this.fade = false,
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
    bool fade = false,
  }) : this(
         kind: QuickjsUiRouteTransitionKind.slide,
         duration: duration,
         reverseDuration: reverseDuration,
         curve: curve,
         beginOffset: beginOffset,
         fade: fade,
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
  final bool fade;
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
    this.uiPlugins = const <QuickjsUiPlugin>[],
    this.transition,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final List<QuickjsHostMount> mounts;
  final List<QuickjsUiPlugin> uiPlugins;
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
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
    QuickjsUiRouteTransition? transition,
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
          uiPlugins: uiPlugins,
          transition: transition,
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
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
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
        uiPlugins: <QuickjsUiPlugin>[...uiPlugins, ...jsRoute.uiPlugins],
        transition: transition ?? jsRoute.transition,
        routeRegistry: registry,
      );
    }
    throw StateError('quickjs_ui route "$route" is not registered');
  }

  static Future<Object?> Function(Map<String, Object?> intent)
  navigationHandler(
    BuildContext context,
    QuickjsUiRouteRegistry registry, {
    List<QuickjsUiPlugin> uiPlugins = const <QuickjsUiPlugin>[],
  }) {
    return (intent) => pushIntent(
      context,
      registry: registry,
      intent: intent,
      uiPlugins: uiPlugins,
    );
  }
}

class _QuickjsUiAssetRoutePage extends StatelessWidget {
  const _QuickjsUiAssetRoutePage({
    required this.path,
    required this.initialProps,
    required this.mounts,
    required this.uiPlugins,
    this.bundleRoot,
    this.title,
    this.transition,
    this.onConsole,
    this.routeRegistry,
  });

  final String path;
  final String? bundleRoot;
  final String? title;
  final Map<String, Object?> initialProps;
  final List<QuickjsHostMount> mounts;
  final List<QuickjsUiPlugin> uiPlugins;
  final QuickjsUiRouteTransition? transition;
  final QuickjsConsoleSink? onConsole;
  final QuickjsUiRouteRegistry? routeRegistry;

  @override
  Widget build(BuildContext context) {
    final routeRegistryValue = routeRegistry;
    final content = routeRegistryValue == null
        ? QuickjsUiView.asset(
            path: path,
            bundleRoot: bundleRoot,
            initialProps: initialProps,
            mounts: mounts,
            uiPlugins: uiPlugins,
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
              uiPlugins: uiPlugins,
              transition: transition,
            ),
            initialProps: initialProps,
            registry: routeRegistryValue,
            uiPlugins: uiPlugins,
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
    this.uiPlugins = const <QuickjsUiPlugin>[],
    this.onConsole,
  });

  final QuickjsUiAssetRoute root;
  final Map<String, Object?> initialProps;
  final QuickjsUiRouteRegistry registry;
  final List<QuickjsUiPlugin> uiPlugins;
  final QuickjsConsoleSink? onConsole;

  @override
  State<_QuickjsUiRouter> createState() => _QuickjsUiRouterState();
}

class _QuickjsUiRouterState extends State<_QuickjsUiRouter>
    with SingleTickerProviderStateMixin {
  late final _QuickjsUiRouteStack _routes;
  late final AnimationController _transitionController;
  _QuickjsUiRouterTransition? _activeTransition;

  @override
  void initState() {
    super.initState();
    _transitionController = AnimationController(vsync: this);
    _routes = _QuickjsUiRouteStack(
      root: widget.root,
      initialProps: widget.initialProps,
      uiPlugins: widget.uiPlugins,
      onConsole: widget.onConsole,
    );
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiRouter oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.root.path != widget.root.path ||
        oldWidget.root.bundleRoot != widget.root.bundleRoot ||
        oldWidget.initialProps != widget.initialProps) {
      _clearTransition(disposeOverlay: true);
      _routes.reset(
        root: widget.root,
        initialProps: widget.initialProps,
        uiPlugins: widget.uiPlugins,
        onConsole: widget.onConsole,
      );
    } else if (oldWidget.uiPlugins != widget.uiPlugins) {
      _routes.updateUiPlugins(widget.uiPlugins);
    }
  }

  @override
  void dispose() {
    _clearTransition(disposeOverlay: true);
    _transitionController.dispose();
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
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final entry in _routes.entries)
            _buildRouteEntry(entry, visible: _isRouteEntryVisible(entry)),
          if (_activeTransition?.overlayEntry case final overlay?)
            _buildRouteEntry(overlay, visible: true, overlay: true),
        ],
      ),
    );
  }

  bool _isRouteEntryVisible(_QuickjsUiRouterEntry entry) {
    return identical(entry, _routes.top) ||
        _activeTransition?.backgroundEntryId == entry.id;
  }

  Widget _buildRouteEntry(
    _QuickjsUiRouterEntry entry, {
    required bool visible,
    bool overlay = false,
  }) {
    Widget child = Offstage(
      offstage: !visible,
      child: TickerMode(
        enabled: visible,
        child: _QuickjsUiRouteContentReveal(
          enabled: !overlay && entry.route.transition?.fade == true,
          onFirstRender: overlay ? null : () => _routeEnter(entry),
          builder: (context, onFirstRender) => QuickjsUiView.asset(
            key: entry.key,
            path: entry.route.path,
            bundleRoot: entry.route.bundleRoot,
            initialProps: entry.params,
            mounts: _mountsFor(entry),
            uiPlugins: entry.uiPlugins,
            controller: entry.controller,
            loadingBuilder: (_) =>
                const Center(child: CircularProgressIndicator()),
            onFirstRender: onFirstRender,
          ),
        ),
      ),
    );
    final transition = _activeTransition;
    if (transition != null && transition.entryId == entry.id) {
      child = AnimatedBuilder(
        animation: _transitionController,
        child: child,
        builder: (context, child) {
          return _buildJsRouteTransition(
            transition: transition.transition,
            animation: _transitionController,
            reverse: transition.reverse,
            child: child ?? const SizedBox.shrink(),
          );
        },
      );
    }
    return Positioned.fill(child: child);
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
            final result = args.isEmpty ? null : args[0];
            if (_routes.length <= 1) {
              unawaited(_popJsRoute(result));
              return null;
            }
            return _popJsRoute(result);
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
            _sendRouteLeaveAndHide(
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
          _sendRouteLeaveAndHide(
            source,
            to: routeName,
            params: params,
            action: 'push',
          ),
        );
        final result = await Navigator.of(context).push<Object?>(route);
        source.navigationLocked = false;
        _scheduleRouteResultShowAndEnter(
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
          _replaceJsRoute(
            source: source,
            route: jsRoute,
            params: params,
            to: _routeIdentity(jsRoute),
          );
          return true;
        }
        unawaited(
          _sendRouteLeaveAndHide(
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
      uiPlugins: widget.uiPlugins,
      onConsole: widget.onConsole,
    );
    _startTransition(
      entry: _routes.top,
      transition: route.transition,
      reverse: false,
      backgroundEntryId: _routes.length > 1 ? _routes.previous.id : null,
    );
    setState(() {
      // The route stack is already mutated by _routes.push().
    });
    return result;
  }

  bool _replaceJsRoute({
    required _QuickjsUiRouterEntry source,
    required QuickjsUiAssetRoute route,
    required Map<String, Object?> params,
    required String to,
  }) {
    final replaced = _routes.replace(
      route: route,
      params: params,
      uiPlugins: widget.uiPlugins,
      onConsole: widget.onConsole,
    );
    _startTransition(
      entry: _routes.top,
      transition: route.transition,
      reverse: false,
      overlayEntry: replaced,
      disposeOverlay: true,
    );
    setState(() {
      // The route stack is already mutated by _routes.replace().
    });
    unawaited(
      _sendRouteLeaveAndHide(source, to: to, params: params, action: 'replace'),
    );
    return true;
  }

  Future<bool> _popJsRoute(
    Object? result, {
    bool waitForRouteLeave = false,
  }) async {
    if (_routes.length <= 1) {
      final root = _routes.top;
      final navigator = Navigator.of(context);
      final routeLeave = _sendRouteLeaveAndHide(
        root,
        to: 'native',
        result: result,
        action: 'pop',
      );
      if (!waitForRouteLeave) {
        scheduleMicrotask(() {
          if (mounted) {
            navigator.pop(result);
          }
        });
        unawaited(
          routeLeave.catchError((Object _) {
            // The route is already leaving the native Navigator. Lifecycle
            // errors must not repaint the departing JS page.
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
    final routeLeave = _sendRouteLeaveAndHide(
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
    _startTransition(
      entry: entry,
      transition: entry.route.transition,
      reverse: true,
      overlayEntry: entry,
      disposeOverlay: true,
    );
    if (mounted) {
      setState(() {});
    }
    _scheduleRouteResultShowAndEnter(
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

  Future<void> _sendRouteLeaveAndHide(
    _QuickjsUiRouterEntry entry, {
    required String to,
    Map<String, Object?>? params,
    Object? result,
    required String action,
  }) async {
    await _sendRouteLeave(
      entry,
      to: to,
      params: params,
      result: result,
      action: action,
    );
    await _sendRouteHide(entry);
  }

  Future<void> _sendRouteHide(_QuickjsUiRouterEntry entry) {
    if (!mounted || entry.controller.isDisposed) {
      return Future<void>.value();
    }
    return entry.controller.routeLifecycle(
      'hide',
      payload: <String, Object?>{'route': _entryRouteIdentity(entry)},
    );
  }

  Future<void> _sendRouteShow(
    _QuickjsUiRouterEntry entry, {
    String? from,
    Object? result,
  }) {
    if (!mounted || entry.controller.isDisposed) {
      return Future<void>.value();
    }
    final payload = <String, Object?>{'route': _entryRouteIdentity(entry)};
    if (from != null) {
      payload['from'] = from;
      payload['result'] = result;
    }
    return entry.controller.routeLifecycle('show', payload: payload);
  }

  void _scheduleRouteResultShowAndEnter(
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
      await _sendRouteShow(entry, from: from, result: result);
      _routeEnter(entry, from: from, result: result);
    }());
  }

  void _startTransition({
    required _QuickjsUiRouterEntry entry,
    required QuickjsUiRouteTransition? transition,
    required bool reverse,
    _QuickjsUiRouterEntry? overlayEntry,
    int? backgroundEntryId,
    bool disposeOverlay = false,
  }) {
    _clearTransition(disposeOverlay: true);
    final effective = transition ?? const QuickjsUiRouteTransition.none();
    if (effective.kind == QuickjsUiRouteTransitionKind.material ||
        effective.kind == QuickjsUiRouteTransitionKind.none ||
        effective.duration == Duration.zero) {
      if (disposeOverlay) {
        overlayEntry?.dispose();
      }
      return;
    }
    _activeTransition = _QuickjsUiRouterTransition(
      entryId: entry.id,
      transition: effective,
      reverse: reverse,
      overlayEntry: overlayEntry,
      backgroundEntryId: backgroundEntryId,
      disposeOverlay: disposeOverlay,
    );
    _transitionController
      ..duration = effective.duration
      ..reverseDuration = effective.reverseDuration ?? effective.duration
      ..value = 0;
    unawaited(
      _transitionController.forward().whenComplete(() {
        if (!mounted) {
          _clearTransition(disposeOverlay: true);
          return;
        }
        setState(() {
          _clearTransition(disposeOverlay: true);
        });
      }),
    );
  }

  void _clearTransition({required bool disposeOverlay}) {
    _transitionController.stop();
    final transition = _activeTransition;
    _activeTransition = null;
    if (disposeOverlay && transition?.disposeOverlay == true) {
      transition?.overlayEntry?.dispose();
    }
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

typedef _QuickjsUiRouteContentBuilder =
    Widget Function(BuildContext context, VoidCallback? onFirstRender);

class _QuickjsUiRouteContentReveal extends StatefulWidget {
  const _QuickjsUiRouteContentReveal({
    required this.builder,
    required this.enabled,
    this.onFirstRender,
  });

  final _QuickjsUiRouteContentBuilder builder;
  final bool enabled;
  final VoidCallback? onFirstRender;

  @override
  State<_QuickjsUiRouteContentReveal> createState() =>
      _QuickjsUiRouteContentRevealState();
}

class _QuickjsUiRouteContentRevealState
    extends State<_QuickjsUiRouteContentReveal>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _opacity;
  late final Animation<Offset> _offset;
  bool _revealed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 140),
      value: 1,
    );
    final curved = CurvedAnimation(parent: _controller, curve: Curves.easeOut);
    _opacity = curved;
    _offset = Tween<Offset>(
      begin: const Offset(0.02, 0),
      end: Offset.zero,
    ).animate(curved);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final child = widget.builder(context, _handleFirstRender);
    if (!widget.enabled || !_revealed) {
      return child;
    }
    return FadeTransition(
      opacity: _opacity,
      child: SlideTransition(position: _offset, child: child),
    );
  }

  void _handleFirstRender() {
    widget.onFirstRender?.call();
    if (!widget.enabled || _revealed || !mounted) {
      return;
    }
    setState(() {
      _revealed = true;
      _controller.value = 0;
    });
    _controller.forward();
  }
}

final class _QuickjsUiRouterTransition {
  const _QuickjsUiRouterTransition({
    required this.entryId,
    required this.transition,
    required this.reverse,
    this.overlayEntry,
    this.backgroundEntryId,
    this.disposeOverlay = false,
  });

  final int entryId;
  final QuickjsUiRouteTransition transition;
  final bool reverse;
  final _QuickjsUiRouterEntry? overlayEntry;
  final int? backgroundEntryId;
  final bool disposeOverlay;
}

final class _QuickjsUiRouteStack {
  _QuickjsUiRouteStack({
    required QuickjsUiAssetRoute root,
    required Map<String, Object?> initialProps,
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
  }) {
    reset(
      root: root,
      initialProps: initialProps,
      uiPlugins: uiPlugins,
      onConsole: onConsole,
    );
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
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
  }) {
    dispose();
    _entries.add(
      _QuickjsUiRouterEntry(
        route: root,
        params: initialProps,
        uiPlugins: uiPlugins,
        onConsole: onConsole,
      ),
    );
  }

  Future<Object?> push({
    required QuickjsUiAssetRoute route,
    required Map<String, Object?> params,
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
  }) {
    final result = Completer<Object?>();
    _entries.add(
      _QuickjsUiRouterEntry(
        route: route,
        params: params,
        uiPlugins: uiPlugins,
        result: result,
        onConsole: onConsole,
      ),
    );
    return result.future;
  }

  _QuickjsUiRouterEntry replace({
    required QuickjsUiAssetRoute route,
    required Map<String, Object?> params,
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
  }) {
    final current = _entries.removeLast();
    _entries.add(
      _QuickjsUiRouterEntry(
        route: route,
        params: params,
        uiPlugins: uiPlugins,
        result: current.result,
        onConsole: onConsole,
      ),
    );
    return current;
  }

  _QuickjsUiRouterEntry removeTop() {
    return _entries.removeLast();
  }

  void updateUiPlugins(List<QuickjsUiPlugin> uiPlugins) {
    for (final entry in _entries) {
      entry.updateUiPlugins(uiPlugins);
    }
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
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
    this.result,
  }) : id = _nextQuickjsUiRouterEntryId++,
       controller = QuickjsUiController(onConsole: onConsole),
       _uiPlugins = List<QuickjsUiPlugin>.unmodifiable(<QuickjsUiPlugin>[
         ...uiPlugins,
         ...route.uiPlugins,
       ]);

  final int id;
  final QuickjsUiAssetRoute route;
  final Map<String, Object?> params;
  final Completer<Object?>? result;
  final QuickjsUiController controller;
  final GlobalKey key = GlobalKey();
  List<QuickjsHostMount>? mounts;
  List<QuickjsUiPlugin> _uiPlugins;
  bool navigationLocked = false;

  List<QuickjsUiPlugin> get uiPlugins => _uiPlugins;

  /// Replaces the effective plugin configuration only when the router itself
  /// was reconfigured. Ordinary route rebuilds keep the same list identity so
  /// [QuickjsUiView] does not mistake navigation animation for a page reload.
  void updateUiPlugins(List<QuickjsUiPlugin> uiPlugins) {
    _uiPlugins = List<QuickjsUiPlugin>.unmodifiable(<QuickjsUiPlugin>[
      ...uiPlugins,
      ...route.uiPlugins,
    ]);
  }

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
          final slide = SlideTransition(
            position: Tween<Offset>(
              begin: transition.beginOffset,
              end: Offset.zero,
            ).animate(curved),
            child: child,
          );
          if (!transition.fade) {
            return slide;
          }
          return FadeTransition(opacity: curved, child: slide);
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

Widget _buildJsRouteTransition({
  required QuickjsUiRouteTransition transition,
  required Animation<double> animation,
  required bool reverse,
  required Widget child,
}) {
  final curved = CurvedAnimation(
    parent: reverse ? ReverseAnimation(animation) : animation,
    curve: transition.curve,
    reverseCurve: transition.curve,
  );
  switch (transition.kind) {
    case QuickjsUiRouteTransitionKind.material:
    case QuickjsUiRouteTransitionKind.none:
      return child;
    case QuickjsUiRouteTransitionKind.fade:
      return FadeTransition(opacity: curved, child: child);
    case QuickjsUiRouteTransitionKind.slide:
      final slide = SlideTransition(
        position: Tween<Offset>(
          begin: transition.beginOffset,
          end: Offset.zero,
        ).animate(curved),
        child: child,
      );
      if (!transition.fade) {
        return slide;
      }
      return FadeTransition(opacity: curved, child: slide);
    case QuickjsUiRouteTransitionKind.scale:
      return ScaleTransition(
        scale: Tween<double>(
          begin: transition.beginScale,
          end: 1,
        ).animate(curved),
        child: FadeTransition(opacity: curved, child: child),
      );
  }
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
        fade: _boolFromTransition(value['fade']),
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

bool _boolFromTransition(Object? value) {
  if (value == null) {
    return false;
  }
  if (value is bool) {
    return value;
  }
  throw ArgumentError('quickjs_ui transition fade must be a boolean');
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
