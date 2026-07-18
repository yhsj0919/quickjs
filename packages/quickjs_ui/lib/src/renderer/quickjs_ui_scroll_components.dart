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
      'ListViewBuilder': _buildListViewBuilder,
      'SingleChildScrollView': _buildSingleChildScrollView,
      'GridView': _buildGridView,
      'PageView': _buildPageView,
      'RefreshIndicator': _buildRefreshIndicator,
    };

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final rawKeys = quickjsUiChildKeys(node);
  final gap = quickjsUiGap(context, node);
  final animateItems =
      QuickjsUiProps.boolValue(node.props['animateItems']) ?? false;
  if (animateItems && rawKeys.any((key) => key == null || key.isEmpty)) {
    throw const FormatException(
      'quickjs_ui ListView animateItems requires stable string keys on children',
    );
  }
  final listView = QuickjsUiScrollableList(
    axis: axis,
    shrinkWrap: QuickjsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
    padding: context.edgeInsets(node.props['padding']),
    childCount: node.children.length,
    childKeys: rawKeys,
    childBuilder: (index) => context.childAt(node, index),
    gap: gap,
    itemExtent: context.spacing(node.props['itemExtent'], name: 'itemExtent'),
    cacheExtent: context.spacing(
      node.props['cacheExtent'],
      name: 'cacheExtent',
    ),
    addAutomaticKeepAlives:
        QuickjsUiProps.boolValue(node.props['addAutomaticKeepAlives']) ?? true,
    addRepaintBoundaries:
        QuickjsUiProps.boolValue(node.props['addRepaintBoundaries']) ?? true,
    scroll: QuickjsUiScrollCommand.fromNode(node),
    animateItems: animateItems,
    itemDuration: quickjsUiItemTransitionDuration(node),
    itemCurve: quickjsUiItemTransitionCurve(node),
  );
  final withGestures = withQuickjsUiGestures(context, node, listView);
  return quickjsUiWrapScrollNotifications(
    context: context,
    node: node,
    child: withGestures,
  );
}

Widget _buildListViewBuilder(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final listKey = QuickjsUiProps.string(node.props['key']);
  if (listKey == null || listKey.isEmpty) {
    throw const FormatException(
      'quickjs_ui ListView.builder requires a stable string key',
    );
  }
  final onLoadMore = QuickjsUiProps.event(node.props['onLoadMore']);
  final listView = QuickjsUiBuilderList(
    listKey: listKey,
    itemCount: QuickjsUiProps.intValue(node.props['itemCount']) ?? 0,
    batchStart: QuickjsUiProps.intValue(node.props['batchStart']) ?? 0,
    batchEnd: QuickjsUiProps.intValue(node.props['batchEnd']) ?? 0,
    prefetchItemCount:
        QuickjsUiProps.intValue(node.props['prefetchItemCount']) ?? 20,
    resetToken: node.props['resetToken'],
    hasMore:
        onLoadMore != null &&
        (QuickjsUiProps.boolValue(node.props['hasMore']) ?? false),
    loading: QuickjsUiProps.boolValue(node.props['loading']) ?? false,
    loadMoreThreshold:
        QuickjsUiProps.intValue(node.props['loadMoreThreshold']) ?? 5,
    loadingText: QuickjsUiProps.string(node.props['loadingText']),
    axis: QuickjsUiProps.axis(node.props['scrollDirection']),
    shrinkWrap: QuickjsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
    padding: context.edgeInsets(node.props['padding']),
    itemExtent: context.spacing(node.props['itemExtent'], name: 'itemExtent'),
    estimatedItemExtent: context.spacing(
      node.props['estimatedItemExtent'],
      name: 'estimatedItemExtent',
    ),
    cacheExtent: context.spacing(
      node.props['cacheExtent'],
      name: 'cacheExtent',
    ),
    scroll: QuickjsUiScrollCommand.fromNode(node),
    batchChildren: <Widget>[
      for (var index = 0; index < node.children.length; index++)
        context.childAt(node, index),
    ],
    requestRange: (start, end) => context.dispatch(<String, Object?>{
      'method': '__quickjsUiListBuilderRange',
      'listKey': listKey,
      'start': start,
      'end': end,
    }),
    loadMore: onLoadMore == null
        ? null
        : () {
            context.dispatchEvent(
              onLoadMore,
              defaultCoalesceKey: quickjsUiEventKey(node, 'onLoadMore'),
            );
          },
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
