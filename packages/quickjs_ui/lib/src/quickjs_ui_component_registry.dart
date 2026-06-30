import 'package:flutter/material.dart';

import 'quickjs_ui_node.dart';
import 'quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

typedef QuickjsUiComponentBuilder =
    Widget Function(QuickjsUiRenderContext context, QuickjsUiNode node);

final class QuickjsUiComponentRegistry {
  QuickjsUiComponentRegistry([Map<String, QuickjsUiComponentBuilder>? builders])
    : _builders = <String, QuickjsUiComponentBuilder>{...?builders};

  factory QuickjsUiComponentRegistry.defaults() {
    return QuickjsUiComponentRegistry(<String, QuickjsUiComponentBuilder>{
      'Text': _buildText,
      'ElevatedButton': _buildElevatedButton,
      'Row': _buildRow,
      'Column': _buildColumn,
      'Container': _buildContainer,
    });
  }

  final Map<String, QuickjsUiComponentBuilder> _builders;

  Iterable<String> get types => _builders.keys;

  bool contains(String type) {
    return _builders.containsKey(type);
  }

  void register(String type, QuickjsUiComponentBuilder builder) {
    _builders[type] = builder;
  }

  void unregister(String type) {
    _builders.remove(type);
  }

  Widget build(QuickjsUiRenderContext context, QuickjsUiNode node) {
    final builder = _builders[node.type];
    if (builder == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return builder(context, node);
  }
}

Widget _buildText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final data =
      QuickjsUiProps.string(node.props['data'] ?? node.props['text']) ?? '';
  return Text(
    data,
    textAlign: QuickjsUiProps.textAlign(node.props['textAlign']),
    style: QuickjsUiProps.textStyle(node.props['style']),
  );
}

Widget _buildElevatedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return ElevatedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildRow(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Row(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    children: context.children(node),
  );
}

Widget _buildColumn(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Column(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    children: context.children(node),
  );
}

Widget _buildContainer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final decoration = QuickjsUiProps.boxDecoration(node.props);
  final opacity = QuickjsUiProps.opacity(node.props['opacity']);
  final child = Container(
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    padding: QuickjsUiProps.edgeInsets(node.props['padding']),
    margin: QuickjsUiProps.edgeInsets(node.props['margin']),
    alignment: QuickjsUiProps.alignment(node.props['alignment']),
    decoration: decoration,
    color: decoration == null
        ? QuickjsUiProps.color(
            node.props['color'] ?? node.props['backgroundColor'],
          )
        : null,
    child: context.child(node),
  );
  if (opacity == 1) {
    return child;
  }
  return Opacity(opacity: opacity, child: child);
}
