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
        allowedPaths.contains(request.resolvedPath);
  }
}

final class QuickjsUiRouteRegistry {
  const QuickjsUiRouteRegistry({
    this.nativeRoutes = const <String, QuickjsUiNativeRouteBuilder>{},
    this.jsRoutes = const <String, QuickjsUiAssetRoute>{},
    this.jsRoutePolicy = const QuickjsUiJsRoutePolicy(),
    this.options = const QuickjsUiNavigationOptions(),
  });

  final Map<String, QuickjsUiNativeRouteBuilder> nativeRoutes;
  final Map<String, QuickjsUiAssetRoute> jsRoutes;
  final QuickjsUiJsRoutePolicy jsRoutePolicy;
  final QuickjsUiNavigationOptions options;

  bool contains(String route) {
    return nativeRoutes.containsKey(route) || jsRoutes.containsKey(route);
  }
}

/// Reliability limits for JSUI-internal navigation.
final class QuickjsUiNavigationOptions {
  const QuickjsUiNavigationOptions({
    this.preparedNavigationTimeout = const Duration(seconds: 10),
    this.lifecycleTimeout = const Duration(seconds: 3),
    this.maxJsRouteDepth = 32,
  });

  /// Maximum time between host policy acceptance and route commit.
  ///
  /// During this window the source route is locked while its JS
  /// `routeLeave`/`hide` hooks run. Expiry removes the token and unlocks the
  /// source; a late commit is rejected instead of reviving stale navigation.
  final Duration preparedNavigationTimeout;

  /// Maximum time navigation waits for `routeLeave` and `hide` together.
  /// Timeout continues the already-approved route commit.
  final Duration lifecycleTimeout;

  /// Maximum number of retained entries in one JSUI-internal route stack.
  /// Native Flutter routes do not consume this budget.
  final int maxJsRouteDepth;
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
  final Map<int, _QuickjsUiPreparedNavigationSlot> _preparedNavigations =
      <int, _QuickjsUiPreparedNavigationSlot>{};
  _QuickjsUiRouteOperation? _activeOperation;

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
        oldWidget.root.mounts != widget.root.mounts ||
        oldWidget.onConsole != widget.onConsole ||
        oldWidget.initialProps != widget.initialProps) {
      _clearRouteOperation();
      _clearPreparedNavigations();
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
    _clearRouteOperation();
    _clearPreparedNavigations();
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
          final root = _routes.top;
          if (root.navigationLocked) {
            return false;
          }
          root.navigationLocked = true;
          await _leaveAndHideForNavigation(root, to: 'native', action: 'pop');
          return true;
        }
        await _popJsRoute(null);
        return false;
      },
      child: Stack(
        fit: StackFit.expand,
        children: <Widget>[
          for (final entry in _routes.entries)
            _buildRouteEntry(entry, visible: _isRouteEntryVisible(entry)),
          if (_activeOperation?.overlayEntry case final overlay?)
            _buildRouteEntry(overlay, visible: true, overlay: true),
        ],
      ),
    );
  }

  bool _isRouteEntryVisible(_QuickjsUiRouterEntry entry) {
    return identical(entry, _routes.top) ||
        identical(entry, _activeOperation?.backgroundEntry);
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
        child: QuickjsUiView.asset(
          key: entry.key,
          path: entry.route.path,
          bundleRoot: entry.route.bundleRoot,
          initialProps: entry.params,
          mounts: _mountsFor(entry),
          uiPlugins: entry.uiPlugins,
          controller: entry.controller,
          loadingBuilder: (_) =>
              const Center(child: CircularProgressIndicator()),
          // Route lifecycle belongs to the entry itself. Visual transitions
          // are applied once by _buildJsRouteTransition below; coupling this
          // callback to a second reveal animation caused fade routes to animate
          // again after their first rendered frame.
          onFirstRender: overlay ? null : () => _routeEnter(entry),
        ),
      ),
    );
    final transition = _activeOperation;
    if (transition != null && identical(transition.animatedEntry, entry)) {
      child = AnimatedBuilder(
        animation: _transitionController,
        child: child,
        builder: (context, child) {
          return _buildJsRouteTransition(
            transition: transition.transition,
            animation: _transitionController,
            reverse: transition.isPop,
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
    return entry.mounts = List<QuickjsHostMount>.unmodifiable(
      <QuickjsHostMount>[...entry.route.mounts, _navigationMountFor(entry)],
    );
  }

  QuickjsHostMount _navigationMountFor(_QuickjsUiRouterEntry source) {
    return QuickjsHostMount(
      name: 'quickjs_ui:router:${source.id}',
      providers: <QuickjsHostProvider>[
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.prepare',
          debugName: 'quickjs_ui navigation prepare',
          callback: (args, _) {
            final action = args.isEmpty ? null : args[0];
            if (action is! String) {
              throw ArgumentError('quickjs_ui navigation action is required');
            }
            return _prepareNavigation(
              source: source,
              action: action,
              intent: _navigationIntent(
                args.length > 1 ? args[1] : null,
                args.length > 2 ? args[2] : null,
              ),
            );
          },
        ),
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.lifecycleDeadline',
          debugName: 'quickjs_ui navigation lifecycle deadline',
          callback: (args, _) {
            final token = args.isEmpty ? null : args[0];
            if (token is! num) {
              throw ArgumentError('quickjs_ui navigation token is required');
            }
            return _waitForLifecycleDeadline(source, token.toInt());
          },
        ),
        QuickjsHostProvider.dart(
          name: 'quickjs_ui.navigation.${source.id}.commit',
          debugName: 'quickjs_ui navigation commit',
          callback: (args, _) {
            final token = args.isEmpty ? null : args[0];
            if (token is! num) {
              throw ArgumentError('quickjs_ui navigation token is required');
            }
            return _commitPreparedNavigation(
              source,
              token.toInt(),
              lifecycleTimedOut: args.length > 1 && args[1] == true,
            );
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
  const prepare = providers['quickjs_ui.navigation.${source.id}.prepare'];
  const lifecycleDeadline = providers['quickjs_ui.navigation.${source.id}.lifecycleDeadline'];
  const commit = providers['quickjs_ui.navigation.${source.id}.commit'];

  async function navigate(action, target, params) {
    const prepared = await prepare(action, target, params);
    const lifecycle = globalThis.__quickjsUiPageLifecycle;
    const departure = prepared?.departure;
    let lifecycleTimedOut = false;
    if (typeof lifecycle === 'function' && departure != null) {
      const cancellation = { cancelled: false };
      const runDeparture = async () => {
        try {
          await lifecycle(
            { type: 'routeLeave', payload: departure.leave },
            cancellation
          );
          if (!cancellation.cancelled) {
            await lifecycle(
              { type: 'hide', payload: departure.hide },
              cancellation
            );
          }
        } catch (_) {
          // Lifecycle hooks observe navigation. They cannot veto a route after
          // host policy has accepted and locked the prepared operation.
        }
        return false;
      };
      lifecycleTimedOut = await Promise.race([
        runDeparture(),
        lifecycleDeadline(prepared.token)
      ]);
      cancellation.cancelled = lifecycleTimedOut;
    }
    return commit(prepared.token, lifecycleTimedOut);
  }

  globalThis.quickjsUiNavigation = Object.freeze({
    push(target, params) {
      return navigate('push', target, params);
    },
    replace(target, params) {
      return navigate('replace', target, params);
    },
    pop(result) {
      return navigate('pop', { result });
    }
  });
})();
''',
        ),
      ],
    );
  }

  Future<Map<String, Object?>> _prepareNavigation({
    required _QuickjsUiRouterEntry source,
    required String action,
    required Map<String, Object?> intent,
  }) async {
    if (action != 'push' && action != 'replace' && action != 'pop') {
      throw ArgumentError('Unsupported quickjs_ui navigation action "$action"');
    }
    _lockNavigationSource(source, action);
    try {
      if (action == 'pop') {
        final result = intent['result'];
        final to = _routes.length <= 1
            ? 'native'
            : _entryRouteIdentity(_routes.previous);
        return _storePreparedNavigation(
          _QuickjsUiPreparedNavigation.pop(
            source: source,
            result: result,
            to: to,
          ),
        );
      }

      final routeName = _routeName(intent);
      final params = _params(intent['params']);
      final transition = _transitionFromIntent(intent['transition']);
      final nativeBuilder = widget.registry.nativeRoutes[routeName];
      if (nativeBuilder != null) {
        return _storePreparedNavigation(
          _QuickjsUiPreparedNavigation.native(
            source: source,
            action: action,
            routeName: routeName,
            params: params,
            transition: transition,
            builder: nativeBuilder,
          ),
        );
      }

      final jsRoute = _jsRoute(source, intent, routeName);
      if (jsRoute == null) {
        throw StateError('quickjs_ui route "$routeName" is not registered');
      }
      final maxDepth = widget.registry.options.maxJsRouteDepth;
      if (maxDepth <= 0) {
        throw ArgumentError.value(
          maxDepth,
          'maxJsRouteDepth',
          'must be greater than zero',
        );
      }
      if (action == 'push' && _routes.length >= maxDepth) {
        throw StateError('quickjs_ui JS route stack limit reached ($maxDepth)');
      }
      await _ensureJsRouteAllowed(
        source: source,
        intent: intent,
        route: jsRoute,
        routeName: routeName,
        params: params,
        action: action,
      );
      return _storePreparedNavigation(
        _QuickjsUiPreparedNavigation.js(
          source: source,
          action: action,
          routeName: routeName,
          params: params,
          route: jsRoute,
        ),
      );
    } catch (_) {
      source.navigationLocked = false;
      rethrow;
    }
  }

  Map<String, Object?> _storePreparedNavigation(
    _QuickjsUiPreparedNavigation prepared,
  ) {
    final token = _nextQuickjsUiPreparedNavigationId++;
    final timeoutDuration = widget.registry.options.preparedNavigationTimeout;
    final lifecycleTimeout = widget.registry.options.lifecycleTimeout;
    if (timeoutDuration <= Duration.zero) {
      throw ArgumentError.value(
        timeoutDuration,
        'preparedNavigationTimeout',
        'must be greater than zero',
      );
    }
    if (lifecycleTimeout <= Duration.zero) {
      throw ArgumentError.value(
        lifecycleTimeout,
        'lifecycleTimeout',
        'must be greater than zero',
      );
    }
    final lifecycleDeadline = Completer<bool>();
    late final _QuickjsUiPreparedNavigationSlot slot;
    slot = _QuickjsUiPreparedNavigationSlot(
      prepared: prepared,
      lifecycleDeadline: lifecycleDeadline,
      lifecycleTimeout: Timer(lifecycleTimeout, () {
        if (!lifecycleDeadline.isCompleted) {
          lifecycleDeadline.complete(true);
        }
      }),
      timeout: Timer(timeoutDuration, () {
        final current = _preparedNavigations[token];
        if (!identical(current, slot)) {
          return;
        }
        _preparedNavigations.remove(token);
        slot.finish(lifecycleTimedOut: true);
        prepared.source.navigationLocked = false;
        debugPrint(
          '[quickjs_ui navigation] prepared ${prepared.action} expired '
          'after ${timeoutDuration.inMilliseconds}ms',
        );
      }),
    );
    _preparedNavigations[token] = slot;
    return <String, Object?>{'token': token, 'departure': prepared.departure};
  }

  Future<Object?> _commitPreparedNavigation(
    _QuickjsUiRouterEntry source,
    int token, {
    required bool lifecycleTimedOut,
  }) async {
    final slot = _preparedNavigations[token];
    if (slot == null || !identical(slot.prepared.source, source)) {
      throw StateError('quickjs_ui navigation preparation expired');
    }
    _preparedNavigations.remove(token);
    slot.finish(lifecycleTimedOut: lifecycleTimedOut);
    if (lifecycleTimedOut) {
      debugPrint(
        '[quickjs_ui navigation] ${slot.prepared.action} lifecycle timed out',
      );
    }
    final prepared = slot.prepared;
    try {
      _ensureCurrentNavigationSource(source, prepared.action);
      if (prepared.action == 'pop') {
        return _commitPreparedPop(prepared);
      }

      final nativeBuilder = prepared.nativeBuilder;
      if (nativeBuilder != null) {
        final route = _quickjsUiRoute<Object?>(
          settings: RouteSettings(
            name: prepared.routeName,
            arguments: prepared.params,
          ),
          transition: prepared.transition,
          builder: (context) => nativeBuilder(context, prepared.params),
        );
        if (prepared.action == 'replace') {
          unawaited(
            Navigator.of(context).pushReplacement<Object?, Object?>(route),
          );
          return true;
        }
        final result = await Navigator.of(context).push<Object?>(route);
        source.navigationLocked = false;
        _scheduleRouteResultShowAndEnter(
          source,
          from: prepared.routeName!,
          result: result,
          action: 'push',
        );
        return result;
      }

      final jsRoute = prepared.jsRoute!;
      if (prepared.action == 'replace') {
        _replaceJsRoute(
          source: source,
          route: jsRoute,
          params: prepared.params,
        );
        return true;
      }
      return _pushJsRoute(source, jsRoute, prepared.params);
    } catch (_) {
      source.navigationLocked = false;
      rethrow;
    }
  }

  Future<bool> _waitForLifecycleDeadline(
    _QuickjsUiRouterEntry source,
    int token,
  ) {
    final slot = _preparedNavigations[token];
    if (slot == null || !identical(slot.prepared.source, source)) {
      return Future<bool>.value(true);
    }
    return slot.lifecycleDeadline.future;
  }

  void _clearPreparedNavigations() {
    for (final slot in _preparedNavigations.values) {
      slot.finish(lifecycleTimedOut: true);
      slot.prepared.source.navigationLocked = false;
    }
    _preparedNavigations.clear();
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
    _startRouteOperation(
      _QuickjsUiRouteOperation.push(
        entering: _routes.top,
        background: _routes.length > 1 ? _routes.previous : null,
        transition: route.transition,
      ),
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
  }) {
    final replaced = _routes.replace(
      route: route,
      params: params,
      uiPlugins: widget.uiPlugins,
      onConsole: widget.onConsole,
    );
    _startRouteOperation(
      _QuickjsUiRouteOperation.replace(
        entering: _routes.top,
        departing: replaced,
        transition: route.transition,
      ),
    );
    setState(() {
      // The route stack is already mutated by _routes.replace().
    });
    return true;
  }

  Future<bool> _popJsRoute(Object? result) async {
    final entry = _routes.top;
    _lockNavigationSource(entry, 'pop');
    final to = _routes.length <= 1
        ? 'native'
        : _entryRouteIdentity(_routes.previous);
    await _leaveAndHideForNavigation(
      entry,
      to: to,
      result: result,
      action: 'pop',
    );
    return _commitPreparedPop(
      _QuickjsUiPreparedNavigation.pop(source: entry, result: result, to: to),
    );
  }

  bool _commitPreparedPop(_QuickjsUiPreparedNavigation prepared) {
    final entry = prepared.source;
    final result = prepared.result;
    if (_routes.length <= 1) {
      final navigator = Navigator.of(context);
      scheduleMicrotask(() {
        if (mounted) {
          navigator.pop(result);
        }
      });
      return true;
    }
    final previous = _routes.previous;
    _finishJsRoutePop(
      entry: entry,
      previous: previous,
      from: _entryRouteIdentity(entry),
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
    _startRouteOperation(
      _QuickjsUiRouteOperation.pop(
        departing: entry,
        revealed: previous,
        transition: entry.route.transition,
      ),
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

  /// Completes the departure phase before the route stack is mutated.
  ///
  /// Lifecycle hooks are page notifications, not navigation guards. A broken
  /// hook must not leave the router permanently locked or half-transitioned;
  /// policy rejection is handled separately before this phase.
  Future<void> _leaveAndHideForNavigation(
    _QuickjsUiRouterEntry entry, {
    required String to,
    Map<String, Object?>? params,
    Object? result,
    required String action,
  }) async {
    try {
      await _sendRouteLeave(
        entry,
        to: to,
        params: params,
        result: result,
        action: action,
      );
      await _sendRouteHide(entry);
    } catch (error) {
      debugPrint(
        '[quickjs_ui navigation] ignored route departure error: $error',
      );
    }
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

  void _startRouteOperation(_QuickjsUiRouteOperation operation) {
    _clearRouteOperation();
    final effective = operation.transition;
    if (effective.kind == QuickjsUiRouteTransitionKind.material ||
        effective.kind == QuickjsUiRouteTransitionKind.none ||
        effective.duration == Duration.zero) {
      operation.disposeDepartingEntry();
      return;
    }
    _activeOperation = operation;
    _transitionController
      ..duration = effective.duration
      ..reverseDuration = effective.reverseDuration ?? effective.duration
      ..value = 0;
    unawaited(
      _transitionController.forward().whenComplete(() {
        // A newer push/replace/pop may have reused the same animation
        // controller. The older TickerFuture must never clear that operation.
        if (!identical(_activeOperation, operation)) {
          return;
        }
        if (!mounted) {
          _clearRouteOperation();
          return;
        }
        setState(() {
          _clearRouteOperation();
        });
      }),
    );
  }

  void _clearRouteOperation() {
    _transitionController.stop();
    final transition = _activeOperation;
    _activeOperation = null;
    transition?.disposeDepartingEntry();
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
        uiPlugins: registered.uiPlugins,
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
        uiPlugins: currentRoute.uiPlugins,
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
    _ensureCurrentNavigationSource(source, action);
    if (source.navigationLocked) {
      throw StateError(
        'quickjs_ui navigation.$action was ignored because another navigation is pending',
      );
    }
  }

  void _ensureCurrentNavigationSource(
    _QuickjsUiRouterEntry source,
    String action,
  ) {
    if (!mounted || _routes.isEmpty || !identical(_routes.top, source)) {
      throw StateError(
        'quickjs_ui navigation.$action was ignored because the page is no longer current',
      );
    }
  }

  void _lockNavigationSource(_QuickjsUiRouterEntry source, String action) {
    _ensureNavigationSource(source, action);
    source.navigationLocked = true;
  }
}

final class _QuickjsUiPreparedNavigationSlot {
  const _QuickjsUiPreparedNavigationSlot({
    required this.prepared,
    required this.timeout,
    required this.lifecycleTimeout,
    required this.lifecycleDeadline,
  });

  final _QuickjsUiPreparedNavigation prepared;
  final Timer timeout;
  final Timer lifecycleTimeout;
  final Completer<bool> lifecycleDeadline;

  void finish({required bool lifecycleTimedOut}) {
    timeout.cancel();
    lifecycleTimeout.cancel();
    if (!lifecycleDeadline.isCompleted) {
      lifecycleDeadline.complete(lifecycleTimedOut);
    }
  }
}

final class _QuickjsUiPreparedNavigation {
  _QuickjsUiPreparedNavigation._({
    required this.source,
    required this.action,
    required this.to,
    required Map<String, Object?> params,
    this.routeName,
    this.transition,
    this.nativeBuilder,
    this.jsRoute,
    this.result,
  }) : params = Map<String, Object?>.unmodifiable(params);

  factory _QuickjsUiPreparedNavigation.native({
    required _QuickjsUiRouterEntry source,
    required String action,
    required String routeName,
    required Map<String, Object?> params,
    required QuickjsUiRouteTransition? transition,
    required QuickjsUiNativeRouteBuilder builder,
  }) {
    return _QuickjsUiPreparedNavigation._(
      source: source,
      action: action,
      to: routeName,
      routeName: routeName,
      params: params,
      transition: transition,
      nativeBuilder: builder,
    );
  }

  factory _QuickjsUiPreparedNavigation.js({
    required _QuickjsUiRouterEntry source,
    required String action,
    required String routeName,
    required Map<String, Object?> params,
    required QuickjsUiAssetRoute route,
  }) {
    return _QuickjsUiPreparedNavigation._(
      source: source,
      action: action,
      to: _routeIdentity(route),
      routeName: routeName,
      params: params,
      jsRoute: route,
    );
  }

  factory _QuickjsUiPreparedNavigation.pop({
    required _QuickjsUiRouterEntry source,
    required Object? result,
    required String to,
  }) {
    return _QuickjsUiPreparedNavigation._(
      source: source,
      action: 'pop',
      to: to,
      params: const <String, Object?>{},
      result: result,
    );
  }

  final _QuickjsUiRouterEntry source;
  final String action;
  final String to;
  final String? routeName;
  final Map<String, Object?> params;
  final QuickjsUiRouteTransition? transition;
  final QuickjsUiNativeRouteBuilder? nativeBuilder;
  final QuickjsUiAssetRoute? jsRoute;
  final Object? result;

  Map<String, Object?> get departure {
    final leave = <String, Object?>{
      'from': _entryRouteIdentity(source),
      'to': to,
      'action': action,
    };
    if (action == 'pop') {
      leave['result'] = result;
    } else {
      leave['params'] = params;
    }
    return <String, Object?>{
      'leave': leave,
      'hide': <String, Object?>{'route': _entryRouteIdentity(source)},
    };
  }
}

int _nextQuickjsUiPreparedNavigationId = 0;

enum _QuickjsUiRouteOperationKind { push, replace, pop }

/// Complete visual state for one JSUI route-stack mutation.
///
/// Each factory describes one legal operation. This keeps ownership of a
/// departing entry beside the transition that displays it and prevents callers
/// from constructing invalid combinations such as a disposable push overlay or
/// a reverse replace animation.
final class _QuickjsUiRouteOperation {
  _QuickjsUiRouteOperation._({
    required this.kind,
    required this.animatedEntry,
    required this.transition,
    this.backgroundEntry,
    this.overlayEntry,
    this.ownsOverlayEntry = false,
  });

  factory _QuickjsUiRouteOperation.push({
    required _QuickjsUiRouterEntry entering,
    required _QuickjsUiRouterEntry? background,
    required QuickjsUiRouteTransition? transition,
  }) {
    return _QuickjsUiRouteOperation._(
      kind: _QuickjsUiRouteOperationKind.push,
      animatedEntry: entering,
      backgroundEntry: background,
      transition: transition ?? const QuickjsUiRouteTransition.none(),
    );
  }

  factory _QuickjsUiRouteOperation.replace({
    required _QuickjsUiRouterEntry entering,
    required _QuickjsUiRouterEntry departing,
    required QuickjsUiRouteTransition? transition,
  }) {
    return _QuickjsUiRouteOperation._(
      kind: _QuickjsUiRouteOperationKind.replace,
      animatedEntry: entering,
      overlayEntry: departing,
      ownsOverlayEntry: true,
      transition: transition ?? const QuickjsUiRouteTransition.none(),
    );
  }

  factory _QuickjsUiRouteOperation.pop({
    required _QuickjsUiRouterEntry departing,
    required _QuickjsUiRouterEntry revealed,
    required QuickjsUiRouteTransition? transition,
  }) {
    return _QuickjsUiRouteOperation._(
      kind: _QuickjsUiRouteOperationKind.pop,
      animatedEntry: departing,
      backgroundEntry: revealed,
      overlayEntry: departing,
      ownsOverlayEntry: true,
      transition: transition ?? const QuickjsUiRouteTransition.none(),
    );
  }

  final _QuickjsUiRouteOperationKind kind;
  final _QuickjsUiRouterEntry animatedEntry;
  final _QuickjsUiRouterEntry? backgroundEntry;
  final _QuickjsUiRouterEntry? overlayEntry;
  final bool ownsOverlayEntry;
  final QuickjsUiRouteTransition transition;
  bool _overlayDisposed = false;

  bool get isPop => kind == _QuickjsUiRouteOperationKind.pop;

  void disposeDepartingEntry() {
    if (!ownsOverlayEntry || _overlayDisposed) {
      return;
    }
    _overlayDisposed = true;
    overlayEntry?.dispose();
  }
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
    required Map<String, Object?> params,
    required List<QuickjsUiPlugin> uiPlugins,
    QuickjsConsoleSink? onConsole,
    this.result,
  }) : id = _nextQuickjsUiRouterEntryId++,
       params = Map<String, Object?>.unmodifiable(params),
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
