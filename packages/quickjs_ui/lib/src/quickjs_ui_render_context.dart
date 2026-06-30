import 'package:flutter/widgets.dart';

import 'quickjs_ui_node.dart';

typedef QuickjsUiEventHandler = void Function(Map<String, Object?> event);
typedef QuickjsUiNodeBuilder = Widget Function(QuickjsUiNode node);

final class QuickjsUiRenderContext {
  const QuickjsUiRenderContext({
    required this._buildNode,
    required this.onEvent,
  });

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
