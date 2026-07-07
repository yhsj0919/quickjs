import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_scrollable.dart';

final QuickjsUiComponentBuilderMap quickjsUiScrollComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'ListView': _buildListView,
      'SingleChildScrollView': _buildSingleChildScrollView,
      'GridView': _buildGridView,
      'PageView': _buildPageView,
      'RefreshIndicator': _buildRefreshIndicator,
    };

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final rawChildren = context.children(node);
  final rawKeys = quickjsUiChildKeys(node);
  final gap = quickjsUiGap(context, node);
  final children = <Widget>[];
  final childKeys = <String?>[];
  for (var index = 0; index < rawChildren.length; index++) {
    if (index > 0 && gap > 0) {
      children.add(
        axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap),
      );
      childKeys.add(null);
    }
    children.add(rawChildren[index]);
    childKeys.add(rawKeys[index]);
  }
  final animateItems =
      QuickjsUiProps.boolValue(node.props['animateItems']) ?? false;
  if (animateItems && childKeys.any((key) => key == null || key.isEmpty)) {
    throw const FormatException(
      'quickjs_ui ListView animateItems requires stable string keys on children',
    );
  }
  final listView = QuickjsUiScrollableList(
    axis: axis,
    shrinkWrap:
        QuickjsUiProps.boolValue(node.props['shrinkWrap']) ??
        (node.props['shrinkWrap'] == null),
    padding: context.edgeInsets(node.props['padding']),
    childKeys: childKeys,
    scroll: QuickjsUiScrollCommand.fromNode(node),
    animateItems: animateItems,
    itemDuration: quickjsUiItemTransitionDuration(node),
    itemCurve: quickjsUiItemTransitionCurve(node),
    children: children,
  );
  final withGestures = withQuickjsUiGestures(context, node, listView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildSingleChildScrollView(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final scrollView = QuickjsUiScrollableColumn(
    padding: context.edgeInsets(node.props['padding']),
    scroll: QuickjsUiScrollCommand.fromNode(node),
    children: _childrenWithGap(context, node, Axis.vertical),
  );
  final withGestures = withQuickjsUiGestures(context, node, scrollView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildGridView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final gridView = GridView.count(
    scrollDirection: axis,
    crossAxisCount: QuickjsUiProps.intValue(node.props['crossAxisCount']) ?? 2,
    childAspectRatio:
        QuickjsUiProps.doubleValue(node.props['childAspectRatio']) ?? 1,
    crossAxisSpacing:
        context.spacing(
          node.props['crossAxisSpacing'],
          name: 'GridView crossAxisSpacing',
        ) ??
        0,
    mainAxisSpacing:
        context.spacing(
          node.props['mainAxisSpacing'],
          name: 'GridView mainAxisSpacing',
        ) ??
        0,
    padding: context.edgeInsets(node.props['padding']),
    shrinkWrap: QuickjsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
    children: context.children(node),
  );
  final withGestures = withQuickjsUiGestures(context, node, gridView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildPageView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onPageChanged = QuickjsUiProps.event(node.props['onPageChanged']);
  final pageView = PageView(
    scrollDirection: QuickjsUiProps.axis(node.props['scrollDirection']),
    pageSnapping: QuickjsUiProps.boolValue(node.props['pageSnapping']) ?? true,
    onPageChanged: onPageChanged == null
        ? null
        : (index) => context.dispatchEvent(
            onPageChanged,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onPageChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    children: context.children(node),
  );
  final withGestures = withQuickjsUiGestures(context, node, pageView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildRefreshIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onRefresh = QuickjsUiProps.event(node.props['onRefresh']);
  return RefreshIndicator(
    onRefresh: () async {
      if (onRefresh != null) {
        context.dispatchEvent(onRefresh);
      }
    },
    child: context.child(node) ?? ListView(children: const <Widget>[]),
  );
}

List<Widget> _childrenWithGap(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Axis axis,
) {
  final children = context.children(node);
  final gap = quickjsUiGap(context, node);
  if (children.length < 2 || gap <= 0) {
    return children;
  }
  return <Widget>[
    for (var index = 0; index < children.length; index++) ...<Widget>[
      if (index > 0)
        axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap),
      children[index],
    ],
  ];
}
