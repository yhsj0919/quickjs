import 'dart:convert';

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiFeedbackComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'SnackBar': _buildSnackBar,
      'AlertDialog': _buildAlertDialog,
      'BottomSheet': _buildBottomSheet,
    };

Widget _buildSnackBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final content =
      context.child(node) ??
      Text(
        QuickjsUiProps.string(node.props['content'] ?? node.props['text']) ??
            '',
      );
  return _QuickjsUiSnackBarHost(
    signature: jsonEncode(node.toMap()),
    content: content,
    backgroundColor: context.color(node.props['backgroundColor']),
    duration:
        QuickjsUiProps.duration(node.props['durationMs']) ??
        const Duration(seconds: 4),
  );
}

Widget _buildAlertDialog(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final title = quickjsUiNodeProp(node.props['title']);
  final content = quickjsUiNodeProp(node.props['content']);
  return AlertDialog(
    title: title == null
        ? quickjsUiOptionalText(QuickjsUiProps.string(node.props['titleText']))
        : context.build(title),
    content: content == null
        ? quickjsUiOptionalText(
            QuickjsUiProps.string(node.props['contentText']),
          )
        : context.build(content),
    actions: quickjsUiNodeListProp(context, node.props['actions']),
    backgroundColor: context.color(node.props['backgroundColor']),
  );
}

Widget _buildBottomSheet(QuickjsUiRenderContext context, QuickjsUiNode node) {
  if (QuickjsUiProps.boolValue(node.props['visible']) == false) {
    return const SizedBox.shrink();
  }
  final onClosing = QuickjsUiProps.event(node.props['onClosing']);
  return _QuickjsUiBottomSheetHost(
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

final class _QuickjsUiSnackBarHost extends StatefulWidget {
  const _QuickjsUiSnackBarHost({
    required this.signature,
    required this.content,
    required this.duration,
    this.backgroundColor,
  });

  final String signature;
  final Widget content;
  final Color? backgroundColor;
  final Duration duration;

  @override
  State<_QuickjsUiSnackBarHost> createState() => _QuickjsUiSnackBarHostState();
}

final class _QuickjsUiSnackBarHostState extends State<_QuickjsUiSnackBarHost> {
  String? _shownSignature;

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiSnackBarHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownSignature == widget.signature) {
        return;
      }
      final messenger = ScaffoldMessenger.maybeOf(context);
      if (messenger == null) {
        return;
      }
      _shownSignature = widget.signature;
      messenger.showSnackBar(
        SnackBar(
          content: widget.content,
          backgroundColor: widget.backgroundColor,
          duration: widget.duration,
        ),
      );
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}

final class _QuickjsUiBottomSheetHost extends StatefulWidget {
  const _QuickjsUiBottomSheetHost({
    required this.signature,
    required this.child,
    required this.onClosing,
    this.backgroundColor,
  });

  final String signature;
  final Widget child;
  final Color? backgroundColor;
  final VoidCallback onClosing;

  @override
  State<_QuickjsUiBottomSheetHost> createState() =>
      _QuickjsUiBottomSheetHostState();
}

final class _QuickjsUiBottomSheetHostState
    extends State<_QuickjsUiBottomSheetHost> {
  String? _shownSignature;

  @override
  void initState() {
    super.initState();
    _scheduleShow();
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiBottomSheetHost oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.signature != widget.signature) {
      _scheduleShow();
    }
  }

  void _scheduleShow() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _shownSignature == widget.signature) {
        return;
      }
      if (Navigator.maybeOf(context) == null) {
        return;
      }
      _shownSignature = widget.signature;
      showModalBottomSheet<void>(
        context: context,
        backgroundColor: widget.backgroundColor,
        builder: (_) => widget.child,
      ).whenComplete(widget.onClosing);
    });
  }

  @override
  Widget build(BuildContext context) {
    return const SizedBox.shrink();
  }
}
