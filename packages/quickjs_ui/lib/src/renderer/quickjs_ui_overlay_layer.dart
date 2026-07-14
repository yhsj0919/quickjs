import 'dart:convert';

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_render_context.dart';

sealed class QuickjsUiOverlayIntent {
  const QuickjsUiOverlayIntent({required this.signature});

  final String signature;
}

final class QuickjsUiSnackBarOverlayIntent extends QuickjsUiOverlayIntent {
  const QuickjsUiSnackBarOverlayIntent({
    required super.signature,
    required this.content,
    required this.duration,
    this.backgroundColor,
  });

  final Widget content;
  final Duration duration;
  final Color? backgroundColor;
}

final class QuickjsUiDialogOverlayIntent extends QuickjsUiOverlayIntent {
  const QuickjsUiDialogOverlayIntent({
    required super.signature,
    required this.dialog,
    required this.barrierDismissible,
    required this.onDismissed,
  });

  final Widget dialog;
  final bool barrierDismissible;
  final VoidCallback onDismissed;
}

final class QuickjsUiBottomSheetOverlayIntent extends QuickjsUiOverlayIntent {
  const QuickjsUiBottomSheetOverlayIntent({
    required super.signature,
    required this.child,
    required this.onClosing,
    this.backgroundColor,
  });

  final Widget child;
  final VoidCallback onClosing;
  final Color? backgroundColor;
}

List<QuickjsUiOverlayIntent> collectQuickjsUiOverlayIntents(
  QuickjsUiNode root,
  QuickjsUiRenderContext context,
) {
  final intents = <QuickjsUiOverlayIntent>[];
  for (final node in root.overlayNodes) {
    final intent = switch (node.type) {
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

bool isQuickjsUiOverlayNode(String type) {
  return type == 'SnackBar' || type == 'AlertDialog' || type == 'BottomSheet';
}

QuickjsUiOverlayIntent? _snackBarIntent(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  if (!_visible(node)) {
    return null;
  }
  final content =
      context.child(node) ??
      Text(
        QuickjsUiProps.string(node.props['content'] ?? node.props['text']) ??
            '',
      );
  return QuickjsUiSnackBarOverlayIntent(
    signature: jsonEncode(node.toMap()),
    content: content,
    backgroundColor: context.color(node.props['backgroundColor']),
    duration:
        QuickjsUiProps.duration(node.props['durationMs']) ??
        const Duration(seconds: 4),
  );
}

QuickjsUiOverlayIntent? _dialogIntent(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  if (!_visible(node)) {
    return null;
  }
  final title = quickjsUiNodeProp(node.props['title']);
  final content = quickjsUiNodeProp(node.props['content']);
  final onDismissed = QuickjsUiProps.event(
    node.props['onDismissed'] ?? node.props['onClosing'],
  );
  return QuickjsUiDialogOverlayIntent(
    signature: jsonEncode(node.toMap()),
    barrierDismissible:
        QuickjsUiProps.boolValue(node.props['barrierDismissible']) != false,
    onDismissed: () {
      if (onDismissed != null) {
        context.dispatchEvent(onDismissed);
      }
    },
    dialog: AlertDialog(
      title: title == null
          ? quickjsUiOptionalText(
              QuickjsUiProps.string(node.props['titleText']),
            )
          : context.build(title),
      content: content == null
          ? quickjsUiOptionalText(
              QuickjsUiProps.string(node.props['contentText']),
            )
          : context.build(content),
      actions: quickjsUiNodeListProp(context, node.props['actions']),
      backgroundColor: context.color(node.props['backgroundColor']),
    ),
  );
}

QuickjsUiOverlayIntent? _bottomSheetIntent(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  if (!_visible(node)) {
    return null;
  }
  final onClosing = QuickjsUiProps.event(node.props['onClosing']);
  return QuickjsUiBottomSheetOverlayIntent(
    signature: jsonEncode(node.toMap()),
    backgroundColor: context.color(node.props['backgroundColor']),
    onClosing: () {
      if (onClosing != null) {
        context.dispatchEvent(onClosing);
      }
    },
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

bool _visible(QuickjsUiNode node) {
  return QuickjsUiProps.boolValue(node.props['visible']) != false;
}

final class QuickjsUiOverlayLayer extends StatefulWidget {
  const QuickjsUiOverlayLayer({
    super.key,
    required this.overlayContext,
    required this.intents,
    required this.child,
  });

  final BuildContext overlayContext;
  final List<QuickjsUiOverlayIntent> intents;
  final Widget child;

  @override
  State<QuickjsUiOverlayLayer> createState() => _QuickjsUiOverlayLayerState();
}

final class _QuickjsUiOverlayLayerState extends State<QuickjsUiOverlayLayer> {
  final Set<String> _shownSnackBars = <String>{};
  final Map<_ModalKey, _ModalEntry> _modals = <_ModalKey, _ModalEntry>{};
  bool _syncScheduled = false;

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant QuickjsUiOverlayLayer oldWidget) {
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
      if (mounted) {
        _syncOverlays();
      }
    });
  }

  void _syncOverlays() {
    final snackBars = <QuickjsUiSnackBarOverlayIntent>[
      for (final intent in widget.intents)
        if (intent is QuickjsUiSnackBarOverlayIntent) intent,
    ];
    final modals = <QuickjsUiOverlayIntent>[
      for (final intent in widget.intents)
        if (intent is QuickjsUiDialogOverlayIntent ||
            intent is QuickjsUiBottomSheetOverlayIntent)
          intent,
    ];
    _syncSnackBars(snackBars);
    _syncModals(modals);
  }

  void _syncSnackBars(List<QuickjsUiSnackBarOverlayIntent> intents) {
    final active = <String>{for (final intent in intents) intent.signature};
    final removed = _shownSnackBars.where(
      (signature) => !active.contains(signature),
    );
    if (removed.isNotEmpty) {
      ScaffoldMessenger.maybeOf(widget.overlayContext)?.hideCurrentSnackBar();
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
  void _syncModals(List<QuickjsUiOverlayIntent> intents) {
    final active = <_ModalKey, QuickjsUiOverlayIntent>{
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

  void _openModal(_ModalKey key, QuickjsUiOverlayIntent intent) {
    late final _ModalEntry entry;
    entry = _ModalEntry(closeRoute: () => _closeModalRoute(intent));
    _modals[key] = entry;
    _showModalRoute(intent).whenComplete(() {
      final current = _modals[key];
      final userInitiated = identical(current, entry);
      if (userInitiated) {
        entry.phase = _ModalPhase.dismissed;
      }
      _notifyModalClosed(intent, userInitiated: userInitiated);
    });
  }

  Future<void> _showModalRoute(QuickjsUiOverlayIntent intent) {
    return switch (intent) {
      QuickjsUiDialogOverlayIntent() => showDialog<void>(
        context: widget.overlayContext,
        barrierDismissible: intent.barrierDismissible,
        builder: (_) => intent.dialog,
      ),
      QuickjsUiBottomSheetOverlayIntent() => showModalBottomSheet<void>(
        context: widget.overlayContext,
        backgroundColor: intent.backgroundColor,
        builder: (_) => intent.child,
      ),
      _ => throw StateError('Unsupported modal intent ${intent.runtimeType}'),
    };
  }

  void _closeModalRoute(QuickjsUiOverlayIntent intent) {
    switch (intent) {
      case QuickjsUiDialogOverlayIntent():
        Navigator.maybeOf(widget.overlayContext, rootNavigator: true)?.pop();
      case QuickjsUiBottomSheetOverlayIntent():
        Navigator.maybeOf(widget.overlayContext)?.pop();
      default:
        throw StateError('Unsupported modal intent ${intent.runtimeType}');
    }
  }

  void _notifyModalClosed(
    QuickjsUiOverlayIntent intent, {
    required bool userInitiated,
  }) {
    switch (intent) {
      case QuickjsUiDialogOverlayIntent():
        if (userInitiated) intent.onDismissed();
      case QuickjsUiBottomSheetOverlayIntent():
        // BottomSheet historically reports both user and schema-driven close.
        intent.onClosing();
      default:
        throw StateError('Unsupported modal intent ${intent.runtimeType}');
    }
  }

  void _showSnackBar(QuickjsUiSnackBarOverlayIntent intent) {
    if (_shownSnackBars.contains(intent.signature)) {
      return;
    }
    final messenger = ScaffoldMessenger.maybeOf(widget.overlayContext);
    if (messenger == null) {
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
  Widget build(BuildContext context) {
    return widget.child;
  }
}

enum _ModalKind { dialog, bottomSheet }

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
  _ModalEntry({required this.closeRoute});

  final VoidCallback closeRoute;
  _ModalPhase phase = _ModalPhase.open;
}

_ModalKey _modalKey(QuickjsUiOverlayIntent intent) {
  return switch (intent) {
    QuickjsUiDialogOverlayIntent() => _ModalKey(
      _ModalKind.dialog,
      intent.signature,
    ),
    QuickjsUiBottomSheetOverlayIntent() => _ModalKey(
      _ModalKind.bottomSheet,
      intent.signature,
    ),
    _ => throw StateError('Unsupported modal intent ${intent.runtimeType}'),
  };
}
