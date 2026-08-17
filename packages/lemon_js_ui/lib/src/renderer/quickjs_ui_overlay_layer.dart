// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_render_context.dart';

sealed class JsUiOverlayIntent {
  const JsUiOverlayIntent({required this.signature});

  final String signature;
}

final class JsUiSnackBarOverlayIntent extends JsUiOverlayIntent {
  const JsUiSnackBarOverlayIntent({
    required super.signature,
    required this.content,
    required this.duration,
    this.backgroundColor,
  });

  final Widget content;
  final Duration duration;
  final Color? backgroundColor;
}

final class JsUiDialogOverlayIntent extends JsUiOverlayIntent {
  const JsUiDialogOverlayIntent({
    required super.signature,
    required this.dialog,
    required this.barrierDismissible,
    required this.onDismissed,
  });

  final Widget dialog;
  final bool barrierDismissible;
  final VoidCallback onDismissed;
}

final class JsUiBottomSheetOverlayIntent extends JsUiOverlayIntent {
  const JsUiBottomSheetOverlayIntent({
    required super.signature,
    required this.child,
    required this.onClosing,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback onClosing;
  final Color? backgroundColor;
}

final class JsUiCustomOverlayIntent extends JsUiOverlayIntent {
  const JsUiCustomOverlayIntent({
    required super.signature,
    required this.child,
    required this.alignment,
    required this.padding,
    required this.barrierDismissible,
    required this.barrierColor,
    required this.duration,
    required this.curve,
    required this.transition,
    required this.onDismissed,
  });

  final Widget child;
  final AlignmentGeometry alignment;
  final EdgeInsetsGeometry padding;
  final bool barrierDismissible;
  final Color barrierColor;
  final Duration duration;
  final Curve curve;
  final String transition;
  final VoidCallback onDismissed;
}

List<JsUiOverlayIntent> collectJsUiOverlayIntents(
  JsUiNode root,
  JsUiRenderContext context,
) {
  final intents = <JsUiOverlayIntent>[];
  for (final node in root.overlayNodes) {
    final intent = switch (node.type) {
      'Overlay' => _customOverlayIntent(context, node),
      'SnackBar' => _snackBarIntent(context, node),
      'AlertDialog' => _dialogIntent(context, node),
      'BottomSheet' => _bottomSheetIntent(context, node),
      _ => null,
    };
    if (intent != null) {
      intents.add(intent);
    }
  }
  return intents;
}

JsUiOverlayIntent? _customOverlayIntent(
  JsUiRenderContext context,
  JsUiNode node,
) {
  if (!_visible(node)) {
    return null;
  }
  final onDismissed = JsUiProps.event(
    node.props['onDismissed'] ?? node.props['onClosing'],
  );
  final transition = JsUiProps.string(node.props['transition']) ?? 'fadeScale';
  if (!const <String>{
    'fade',
    'scale',
    'fadeScale',
    'slideDown',
    'slideUp',
    'none',
  }.contains(transition)) {
    throw FormatException(
      'Unknown quickjs_ui Overlay transition "$transition"',
    );
  }
  return JsUiCustomOverlayIntent(
    signature: node.structuralSignature,
    child: context.child(node) ?? const SizedBox.shrink(),
    alignment: JsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
    padding:
        context.edgeInsets(node.props['padding']) ?? const EdgeInsets.all(24),
    barrierDismissible:
        JsUiProps.boolValue(node.props['barrierDismissible']) ?? true,
    barrierColor:
        context.color(node.props['barrierColor']) ?? const Color(0x8A000000),
    duration:
        JsUiProps.duration(node.props['durationMs']) ??
        const Duration(milliseconds: 180),
    curve: JsUiProps.curve(node.props['curve'] ?? 'easeOutCubic'),
    transition: transition,
    onDismissed: () {
      if (onDismissed != null) context.dispatch(onDismissed);
    },
  );
}

JsUiOverlayIntent? _snackBarIntent(JsUiRenderContext context, JsUiNode node) {
  if (!_visible(node)) {
    return null;
  }
  final content =
      context.child(node) ??
      Text(JsUiProps.string(node.props['content'] ?? node.props['text']) ?? '');
  return JsUiSnackBarOverlayIntent(
    signature: node.structuralSignature,
    content: content,
    backgroundColor: context.color(node.props['backgroundColor']),
    duration:
        JsUiProps.duration(node.props['durationMs']) ??
        const Duration(seconds: 4),
  );
}

JsUiOverlayIntent? _dialogIntent(JsUiRenderContext context, JsUiNode node) {
  if (!_visible(node)) {
    return null;
  }
  final title = jsUiNodeProp(node.props['title']);
  final content = jsUiNodeProp(node.props['content']);
  final onDismissed = JsUiProps.event(
    node.props['onDismissed'] ?? node.props['onClosing'],
  );
  return JsUiDialogOverlayIntent(
    signature: node.structuralSignature,
    barrierDismissible:
        JsUiProps.boolValue(node.props['barrierDismissible']) != false,
    onDismissed: () {
      if (onDismissed != null) {
        context.dispatch(onDismissed);
      }
    },
    dialog: AlertDialog(
      title: title == null
          ? jsUiOptionalText(JsUiProps.string(node.props['titleText']))
          : context.build(title),
      content: content == null
          ? jsUiOptionalText(JsUiProps.string(node.props['contentText']))
          : context.build(content),
      actions: jsUiNodeListProp(context, node.props['actions']),
      backgroundColor: context.color(node.props['backgroundColor']),
    ),
  );
}

JsUiOverlayIntent? _bottomSheetIntent(
  JsUiRenderContext context,
  JsUiNode node,
) {
  if (!_visible(node)) {
    return null;
  }
  final onClosing = JsUiProps.event(node.props['onClosing']);
  return JsUiBottomSheetOverlayIntent(
    signature: node.structuralSignature,
    backgroundColor: context.color(node.props['backgroundColor']),
    onClosing: () {
      if (onClosing != null) {
        context.dispatch(onClosing);
      }
    },
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

bool _visible(JsUiNode node) {
  return JsUiProps.boolValue(node.props['visible']) != false;
}

final class JsUiOverlayLayer extends StatefulWidget {
  const JsUiOverlayLayer({
    super.key,
    required this.overlayContext,
    required this.intents,
    required this.child,
  });

  final BuildContext overlayContext;
  final List<JsUiOverlayIntent> intents;
  final Widget child;

  @override
  State<JsUiOverlayLayer> createState() => _JsUiOverlayLayerState();
}

final class _JsUiOverlayLayerState extends State<JsUiOverlayLayer> {
  final Set<String> _shownSnackBars = <String>{};
  final Map<_ModalKey, _ModalEntry> _modals = <_ModalKey, _ModalEntry>{};
  ScaffoldMessengerState? _messenger;
  bool _syncScheduled = false;
  bool _disposed = false;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    // Resolve inherited state while this element is active. Overlay syncing is
    // deferred until the end of the frame, when overlayContext may already be
    // deactivated during route teardown.
    _messenger = ScaffoldMessenger.maybeOf(context);
  }

  @override
  void didUpdateWidget(covariant JsUiOverlayLayer oldWidget) {
    super.didUpdateWidget(oldWidget);
    _scheduleSync();
  }

  void _scheduleSync() {
    if (_syncScheduled) {
      return;
    }
    _syncScheduled = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _syncScheduled = false;
      if (!_disposed && mounted) {
        _syncOverlays();
      }
    });
  }

  void _syncOverlays() {
    final snackBars = <JsUiSnackBarOverlayIntent>[
      for (final intent in widget.intents)
        if (intent is JsUiSnackBarOverlayIntent) intent,
    ];
    final modals = <JsUiOverlayIntent>[
      for (final intent in widget.intents)
        if (intent is JsUiDialogOverlayIntent ||
            intent is JsUiBottomSheetOverlayIntent ||
            intent is JsUiCustomOverlayIntent)
          intent,
    ];
    _syncSnackBars(snackBars);
    _syncModals(modals);
  }

  void _syncSnackBars(List<JsUiSnackBarOverlayIntent> intents) {
    final active = <String>{for (final intent in intents) intent.signature};
    final removed = _shownSnackBars.where(
      (signature) => !active.contains(signature),
    );
    if (removed.isNotEmpty) {
      final messenger = _messenger;
      if (messenger?.mounted ?? false) {
        messenger!.hideCurrentSnackBar();
      }
      _shownSnackBars.removeAll(removed.toList(growable: false));
    }
    for (final intent in intents) {
      _showSnackBar(intent);
    }
  }

  /// Reconciles declarative modal intents with imperative Navigator routes.
  ///
  /// A dismissed modal remains acknowledged while the same `visible: true`
  /// declaration is active. The page must observe onClosing/onDismissed and
  /// render it inactive before a later false -> true transition can reopen it.
  /// This is the same controlled-component contract for Dialog and BottomSheet.
  void _syncModals(List<JsUiOverlayIntent> intents) {
    final active = <_ModalKey, JsUiOverlayIntent>{
      for (final intent in intents) _modalKey(intent): intent,
    };
    for (final key in _modals.keys.toList(growable: false)) {
      if (active.containsKey(key)) {
        continue;
      }
      final entry = _modals.remove(key);
      if (entry?.phase == _ModalPhase.open) {
        entry!.closeRoute();
      }
    }
    for (final entry in active.entries) {
      if (_modals.containsKey(entry.key)) {
        continue;
      }
      _openModal(entry.key, entry.value);
    }
  }

  void _openModal(_ModalKey key, JsUiOverlayIntent intent) {
    final routeBinding = _createModalRoute(intent);
    final entry = _ModalEntry(
      navigator: routeBinding.navigator,
      route: routeBinding.route,
    );
    _modals[key] = entry;
    routeBinding.navigator.push<void>(routeBinding.route).whenComplete(() {
      if (_disposed) {
        return;
      }
      final current = _modals[key];
      final userInitiated = identical(current, entry);
      if (userInitiated) {
        entry.phase = _ModalPhase.dismissed;
      }
      _notifyModalClosed(intent, userInitiated: userInitiated);
    });
  }

  ({NavigatorState navigator, Route<void> route}) _createModalRoute(
    JsUiOverlayIntent intent,
  ) {
    final context = widget.overlayContext;
    return switch (intent) {
      JsUiDialogOverlayIntent() => () {
        final navigator = Navigator.of(context, rootNavigator: true);
        return (
          navigator: navigator,
          route: DialogRoute<void>(
            context: context,
            builder: (_) => intent.dialog,
            barrierDismissible: intent.barrierDismissible,
            themes: InheritedTheme.capture(
              from: context,
              to: navigator.context,
            ),
          ),
        );
      }(),
      JsUiBottomSheetOverlayIntent() => () {
        final navigator = Navigator.of(context);
        final localizations = MaterialLocalizations.of(context);
        return (
          navigator: navigator,
          route: ModalBottomSheetRoute<void>(
            builder: (_) => intent.child,
            capturedThemes: InheritedTheme.capture(
              from: context,
              to: navigator.context,
            ),
            isScrollControlled: false,
            barrierLabel: localizations.scrimLabel,
            barrierOnTapHint: localizations.scrimOnTapHint(
              localizations.bottomSheetLabel,
            ),
            backgroundColor: intent.backgroundColor,
            modalBarrierColor: Theme.of(
              context,
            ).bottomSheetTheme.modalBarrierColor,
          ),
        );
      }(),
      JsUiCustomOverlayIntent() => () {
        final navigator = Navigator.of(context, rootNavigator: true);
        return (
          navigator: navigator,
          route: RawDialogRoute<void>(
            barrierDismissible: intent.barrierDismissible,
            barrierLabel: MaterialLocalizations.of(
              context,
            ).modalBarrierDismissLabel,
            barrierColor: intent.barrierColor,
            transitionDuration: intent.duration,
            pageBuilder: (context, _, _) => SafeArea(
              child: Align(
                alignment: intent.alignment,
                child: Padding(
                  padding: intent.padding,
                  child: Material(
                    type: MaterialType.transparency,
                    child: intent.child,
                  ),
                ),
              ),
            ),
            transitionBuilder: (context, animation, _, child) =>
                _buildCustomTransition(intent, animation, child),
          ),
        );
      }(),
      _ => throw StateError('Unsupported modal intent ${intent.runtimeType}'),
    };
  }

  void _notifyModalClosed(
    JsUiOverlayIntent intent, {
    required bool userInitiated,
  }) {
    switch (intent) {
      case JsUiDialogOverlayIntent():
        if (userInitiated) intent.onDismissed();
      case JsUiBottomSheetOverlayIntent():
        // BottomSheet historically reports both user and schema-driven close.
        intent.onClosing();
      case JsUiCustomOverlayIntent():
        if (userInitiated) intent.onDismissed();
      default:
        throw StateError('Unsupported modal intent ${intent.runtimeType}');
    }
  }

  void _showSnackBar(JsUiSnackBarOverlayIntent intent) {
    if (_shownSnackBars.contains(intent.signature)) {
      return;
    }
    final messenger = _messenger;
    if (messenger == null || !messenger.mounted) {
      return;
    }
    _shownSnackBars.add(intent.signature);
    messenger.showSnackBar(
      SnackBar(
        content: intent.content,
        backgroundColor: intent.backgroundColor,
        duration: intent.duration,
      ),
    );
  }

  @override
  void dispose() {
    _disposed = true;
    final entries = _modals.values.toList(growable: false);
    _modals.clear();
    for (final entry in entries) {
      entry.closeRoute(immediate: true);
    }
    // ScaffoldMessenger owns SnackBar teardown. Driving its animation while
    // this subtree is being unmounted can make it inspect inactive Scaffolds.
    _shownSnackBars.clear();
    _messenger = null;
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}

enum _ModalKind { dialog, bottomSheet, custom }

enum _ModalPhase { open, dismissed }

final class _ModalKey {
  const _ModalKey(this.kind, this.signature);

  final _ModalKind kind;
  final String signature;

  @override
  bool operator ==(Object other) {
    return other is _ModalKey &&
        other.kind == kind &&
        other.signature == signature;
  }

  @override
  int get hashCode => Object.hash(kind, signature);
}

final class _ModalEntry {
  _ModalEntry({required this.navigator, required this.route});

  final NavigatorState navigator;
  final Route<void> route;
  _ModalPhase phase = _ModalPhase.open;

  void closeRoute({bool immediate = false}) {
    if (route.isActive && navigator.mounted) {
      if (!immediate && route.isCurrent) {
        navigator.pop<void>();
      } else {
        navigator.removeRoute<void>(route);
      }
    }
  }
}

_ModalKey _modalKey(JsUiOverlayIntent intent) {
  return switch (intent) {
    JsUiDialogOverlayIntent() => _ModalKey(_ModalKind.dialog, intent.signature),
    JsUiBottomSheetOverlayIntent() => _ModalKey(
      _ModalKind.bottomSheet,
      intent.signature,
    ),
    JsUiCustomOverlayIntent() => _ModalKey(_ModalKind.custom, intent.signature),
    _ => throw StateError('Unsupported modal intent ${intent.runtimeType}'),
  };
}

Widget _buildCustomTransition(
  JsUiCustomOverlayIntent intent,
  Animation<double> animation,
  Widget child,
) {
  if (intent.transition == 'none' || intent.duration == Duration.zero) {
    return child;
  }
  final curved = CurvedAnimation(parent: animation, curve: intent.curve);
  return switch (intent.transition) {
    'fade' => FadeTransition(opacity: curved, child: child),
    'scale' => ScaleTransition(
      scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
      child: child,
    ),
    'slideUp' => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, 0.08),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    ),
    'slideDown' => SlideTransition(
      position: Tween<Offset>(
        begin: const Offset(0, -0.08),
        end: Offset.zero,
      ).animate(curved),
      child: FadeTransition(opacity: curved, child: child),
    ),
    _ => FadeTransition(
      opacity: curved,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.94, end: 1).animate(curved),
        child: child,
      ),
    ),
  };
}
