import 'dart:convert';

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
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
  });

  final Widget dialog;
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
  _visitNode(root, (node) {
    final intent = switch (node.type) {
      'SnackBar' => _snackBarIntent(context, node),
      'AlertDialog' => _dialogIntent(context, node),
      'BottomSheet' => _bottomSheetIntent(context, node),
      _ => null,
    };
    if (intent != null) {
      intents.add(intent);
    }
  });
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
  final title = _nodeProp(node.props['title']);
  final content = _nodeProp(node.props['content']);
  return QuickjsUiDialogOverlayIntent(
    signature: jsonEncode(node.toMap()),
    dialog: AlertDialog(
      title: title == null
          ? _optionalText(QuickjsUiProps.string(node.props['titleText']))
          : context.build(title),
      content: content == null
          ? _optionalText(QuickjsUiProps.string(node.props['contentText']))
          : context.build(content),
      actions: _nodeListProp(context, node.props['actions']),
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

QuickjsUiNode? _nodeProp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return QuickjsUiNode.fromMap(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw const FormatException('quickjs_ui node property must be an object');
}

List<Widget>? _nodeListProp(QuickjsUiRenderContext context, Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui node list property must be a list');
  }
  return <Widget>[
    for (final item in value)
      if (_nodeProp(item) case final node?) context.build(node),
  ];
}

Widget? _optionalText(String? value) {
  if (value == null) {
    return null;
  }
  return Text(value);
}

void _visitNode(QuickjsUiNode node, void Function(QuickjsUiNode node) visitor) {
  visitor(node);
  for (final child in node.children) {
    _visitNode(child, visitor);
  }
  for (final value in node.props.values) {
    _visitNodeValue(value, visitor);
  }
}

void _visitNodeValue(Object? value, void Function(QuickjsUiNode node) visitor) {
  if (value is Map) {
    final type = value['type'];
    if (type is String && type.isNotEmpty) {
      _visitNode(
        QuickjsUiNode.fromMap(
          value.map((key, value) => MapEntry<String, Object?>('$key', value)),
        ),
        visitor,
      );
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _visitNodeValue(item, visitor);
    }
  }
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
  final Set<String> _openDialogs = <String>{};
  final Set<String> _openSheets = <String>{};
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
    final active = <String>{
      for (final intent in widget.intents) intent.signature,
    };
    _dismissInactiveOverlays(active);
    for (final intent in widget.intents) {
      switch (intent) {
        case QuickjsUiSnackBarOverlayIntent():
          _showSnackBar(intent);
        case QuickjsUiDialogOverlayIntent():
          _showDialog(intent);
        case QuickjsUiBottomSheetOverlayIntent():
          _showBottomSheet(intent);
      }
    }
  }

  void _dismissInactiveOverlays(Set<String> active) {
    final removedSnackBars = _shownSnackBars.where(
      (signature) => !active.contains(signature),
    );
    if (removedSnackBars.isNotEmpty) {
      ScaffoldMessenger.maybeOf(widget.overlayContext)?.hideCurrentSnackBar();
      _shownSnackBars.removeAll(removedSnackBars.toList(growable: false));
    }

    for (final signature in _openDialogs.toList(growable: false)) {
      if (!active.contains(signature)) {
        Navigator.maybeOf(widget.overlayContext, rootNavigator: true)?.pop();
        _openDialogs.remove(signature);
      }
    }

    for (final signature in _openSheets.toList(growable: false)) {
      if (!active.contains(signature)) {
        Navigator.maybeOf(widget.overlayContext)?.pop();
        _openSheets.remove(signature);
      }
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

  void _showDialog(QuickjsUiDialogOverlayIntent intent) {
    if (_openDialogs.contains(intent.signature)) {
      return;
    }
    _openDialogs.add(intent.signature);
    showDialog<void>(
      context: widget.overlayContext,
      builder: (_) => intent.dialog,
    ).whenComplete(() => _openDialogs.remove(intent.signature));
  }

  void _showBottomSheet(QuickjsUiBottomSheetOverlayIntent intent) {
    if (_openSheets.contains(intent.signature)) {
      return;
    }
    _openSheets.add(intent.signature);
    showModalBottomSheet<void>(
      context: widget.overlayContext,
      backgroundColor: intent.backgroundColor,
      builder: (_) => intent.child,
    ).whenComplete(() {
      _openSheets.remove(intent.signature);
      intent.onClosing();
    });
  }

  @override
  Widget build(BuildContext context) {
    return widget.child;
  }
}
