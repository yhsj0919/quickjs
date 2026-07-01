import 'package:flutter/widgets.dart';

import '../schema/quickjs_ui_node.dart';

// Keep the public constructor parameter named `buildNode`.
// ignore_for_file: prefer_initializing_formals

typedef QuickjsUiEventHandler = void Function(Map<String, Object?> event);
typedef QuickjsUiNodeBuilder = Widget Function(QuickjsUiNode node);

final class QuickjsUiRenderContext {
  const QuickjsUiRenderContext({
    required QuickjsUiNodeBuilder buildNode,
    required this.onEvent,
  }) : _buildNode = buildNode;

  final QuickjsUiNodeBuilder _buildNode;
  final QuickjsUiEventHandler onEvent;

  Widget build(QuickjsUiNode node) {
    return _buildNode(node);
  }

  Widget? child(QuickjsUiNode node) {
    if (node.children.isEmpty) {
      return null;
    }
    if (node.children.length > 1) {
      throw FormatException('${node.type} expects a single child');
    }
    return build(node.children.single);
  }

  List<Widget> children(QuickjsUiNode node) {
    return <Widget>[for (final child in node.children) build(child)];
  }

  void dispatch(Map<String, Object?> event) {
    onEvent(event);
  }
}
