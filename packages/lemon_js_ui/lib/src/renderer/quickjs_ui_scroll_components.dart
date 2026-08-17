// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_scrollable.dart';

final JsUiComponentBuilderMap jsUiScrollComponentBuilders =
    <String, JsUiComponentBuilder>{
      'ListView': _buildListView,
      'ListViewBuilder': _buildListViewBuilder,
      'SingleChildScrollView': _buildSingleChildScrollView,
      'GridView': _buildGridView,
      'PageView': _buildPageView,
      'RefreshIndicator': _buildRefreshIndicator,
    };

Widget _buildListView(JsUiRenderContext context, JsUiNode node) {
  final axis = JsUiProps.axis(node.props['scrollDirection']);
  final rawKeys = jsUiChildKeys(node);
  final gap = jsUiGap(context, node);
  final animateItems = JsUiProps.boolValue(node.props['animateItems']) ?? false;
  if (animateItems && rawKeys.any((key) => key == null || key.isEmpty)) {
    throw const FormatException(
      'quickjs_ui ListView animateItems requires stable string keys on children',
    );
  }
  final listView = JsUiScrollableList(
    axis: axis,
    shrinkWrap: JsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
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
        JsUiProps.boolValue(node.props['addAutomaticKeepAlives']) ?? true,
    addRepaintBoundaries:
        JsUiProps.boolValue(node.props['addRepaintBoundaries']) ?? true,
    scroll: JsUiScrollCommand.fromNode(node),
    animateItems: animateItems,
    itemDuration: jsUiItemTransitionDuration(node),
    itemCurve: jsUiItemTransitionCurve(node),
    physics: _scrollPhysics(node.props['physics']),
  );
  final withGestures = withJsUiGestures(context, node, listView);
  return _withScrollConfiguration(
    node,
    jsUiWrapScrollNotifications(
      context: context,
      node: node,
      child: withGestures,
    ),
  );
}

Widget _buildListViewBuilder(JsUiRenderContext context, JsUiNode node) {
  final listKey = JsUiProps.string(node.props['key']);
  if (listKey == null || listKey.isEmpty) {
    throw const FormatException(
      'quickjs_ui ListView.builder requires a stable string key',
    );
  }
  final onLoadMore = JsUiProps.event(node.props['onLoadMore']);
  final listView = JsUiBuilderList(
    listKey: listKey,
    itemCount: JsUiProps.intValue(node.props['itemCount']) ?? 0,
    batchStart: JsUiProps.intValue(node.props['batchStart']) ?? 0,
    batchEnd: JsUiProps.intValue(node.props['batchEnd']) ?? 0,
    prefetchItemCount:
        JsUiProps.intValue(node.props['prefetchItemCount']) ?? 20,
    resetToken: node.props['resetToken'],
    hasMore:
        onLoadMore != null &&
        (JsUiProps.boolValue(node.props['hasMore']) ?? false),
    loading: JsUiProps.boolValue(node.props['loading']) ?? false,
    loadMoreThreshold: JsUiProps.intValue(node.props['loadMoreThreshold']) ?? 5,
    loadingText: JsUiProps.string(node.props['loadingText']),
    axis: JsUiProps.axis(node.props['scrollDirection']),
    shrinkWrap: JsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
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
    scroll: JsUiScrollCommand.fromNode(node),
    batchChildren: <Widget>[
      for (var index = 0; index < node.children.length; index++)
        context.childAt(node, index),
    ],
    requestRange: (start, end) => context.dispatch(<String, Object?>{
      'method': '__jsUiListBuilderRange',
      'listKey': listKey,
      'start': start,
      'end': end,
    }),
    loadMore: onLoadMore == null
        ? null
        : () {
            context.dispatch(
              onLoadMore,
              defaultCoalesceKey: jsUiEventKey(node, 'onLoadMore'),
            );
          },
    physics: _scrollPhysics(node.props['physics']),
  );
  final withGestures = withJsUiGestures(context, node, listView);
  return _withScrollConfiguration(
    node,
    jsUiWrapScrollNotifications(
      context: context,
      node: node,
      child: withGestures,
    ),
  );
}

Widget _buildSingleChildScrollView(JsUiRenderContext context, JsUiNode node) {
  final scrollView = JsUiScrollableColumn(
    padding: context.edgeInsets(node.props['padding']),
    scroll: JsUiScrollCommand.fromNode(node),
    physics: _scrollPhysics(node.props['physics']),
    children: _childrenWithGap(context, node, Axis.vertical),
  );
  final withGestures = withJsUiGestures(context, node, scrollView);
  return _withScrollConfiguration(
    node,
    jsUiWrapScrollNotifications(
      context: context,
      node: node,
      child: withGestures,
    ),
  );
}

Widget _buildGridView(JsUiRenderContext context, JsUiNode node) {
  final axis = JsUiProps.axis(node.props['scrollDirection']);
  final gridView = GridView.count(
    scrollDirection: axis,
    crossAxisCount: JsUiProps.intValue(node.props['crossAxisCount']) ?? 2,
    childAspectRatio:
        JsUiProps.doubleValue(node.props['childAspectRatio']) ?? 1,
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
    shrinkWrap: JsUiProps.boolValue(node.props['shrinkWrap']) ?? false,
    physics: _scrollPhysics(node.props['physics']),
    children: context.children(node),
  );
  final withGestures = withJsUiGestures(context, node, gridView);
  return _withScrollConfiguration(
    node,
    jsUiWrapScrollNotifications(
      context: context,
      node: node,
      child: withGestures,
    ),
  );
}

Widget _buildPageView(JsUiRenderContext context, JsUiNode node) {
  final onPageChanged = JsUiProps.event(node.props['onPageChanged']);
  final pageView = PageView(
    scrollDirection: node.props['scrollDirection'] == null
        ? Axis.horizontal
        : JsUiProps.axis(node.props['scrollDirection']),
    pageSnapping: JsUiProps.boolValue(node.props['pageSnapping']) ?? true,
    physics: _scrollPhysics(node.props['physics']),
    onPageChanged: onPageChanged == null
        ? null
        : (index) => context.dispatch(
            onPageChanged,
            defaultCoalesceKey: jsUiEventKey(node, 'onPageChanged'),
            kind: JsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    children: context.children(node),
  );
  final withGestures = withJsUiGestures(context, node, pageView);
  return _withScrollConfiguration(
    node,
    jsUiWrapScrollNotifications(
      context: context,
      node: node,
      child: withGestures,
    ),
  );
}

ScrollPhysics? _scrollPhysics(Object? value) => switch (value) {
  null || 'platform' => null,
  'always' || 'alwaysScrollable' => const AlwaysScrollableScrollPhysics(),
  'bouncing' => const BouncingScrollPhysics(),
  'clamping' => const ClampingScrollPhysics(),
  'never' || 'neverScrollable' => const NeverScrollableScrollPhysics(),
  _ => throw const FormatException('Unknown quickjs_ui scroll physics'),
};

Widget _withScrollConfiguration(JsUiNode node, Widget child) {
  final scrollbars = JsUiProps.boolValue(node.props['scrollbar']);
  if (scrollbars == null) return child;
  return _JsUiScrollConfiguration(scrollbars: scrollbars, child: child);
}

final class _JsUiScrollConfiguration extends StatelessWidget {
  const _JsUiScrollConfiguration({
    required this.scrollbars,
    required this.child,
  });

  final bool scrollbars;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return ScrollConfiguration(
      behavior: ScrollConfiguration.of(
        context,
      ).copyWith(scrollbars: scrollbars),
      child: child,
    );
  }
}

Widget _buildRefreshIndicator(JsUiRenderContext context, JsUiNode node) {
  final onRefresh = JsUiProps.event(node.props['onRefresh']);
  return RefreshIndicator(
    onRefresh: () async {
      if (onRefresh != null) {
        context.dispatch(onRefresh);
      }
    },
    child: context.child(node) ?? ListView(children: const <Widget>[]),
  );
}

List<Widget> _childrenWithGap(
  JsUiRenderContext context,
  JsUiNode node,
  Axis axis,
) {
  final children = context.children(node);
  final gap = jsUiGap(context, node);
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
