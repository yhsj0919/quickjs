// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:async';

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
  final autoPlayInterval =
      JsUiProps.duration(node.props['autoPlayIntervalMs']) ??
      const Duration(seconds: 3);
  if (autoPlayInterval <= Duration.zero) {
    throw const FormatException('PageView autoPlayIntervalMs must be positive');
  }
  final pageView = _JsUiPageView(
    page: JsUiProps.intValue(node.props['page']),
    initialPage: JsUiProps.intValue(node.props['initialPage']) ?? 0,
    loop: JsUiProps.boolValue(node.props['loop']) ?? false,
    autoPlay: JsUiProps.boolValue(node.props['autoPlay']) ?? false,
    autoPlayInterval: autoPlayInterval,
    duration:
        JsUiProps.duration(node.props['scrollDurationMs']) ??
        const Duration(milliseconds: 300),
    curve: JsUiProps.curve(node.props['scrollCurve'] ?? 'easeOut'),
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

final class _JsUiPageView extends StatefulWidget {
  const _JsUiPageView({
    required this.page,
    required this.initialPage,
    required this.loop,
    required this.autoPlay,
    required this.autoPlayInterval,
    required this.duration,
    required this.curve,
    required this.scrollDirection,
    required this.pageSnapping,
    required this.physics,
    required this.onPageChanged,
    required this.children,
  });

  final int? page;
  final int initialPage;
  final bool loop;
  final bool autoPlay;
  final Duration autoPlayInterval;
  final Duration duration;
  final Curve curve;
  final Axis scrollDirection;
  final bool pageSnapping;
  final ScrollPhysics? physics;
  final ValueChanged<int>? onPageChanged;
  final List<Widget> children;

  @override
  State<_JsUiPageView> createState() => _JsUiPageViewState();
}

final class _JsUiPageViewState extends State<_JsUiPageView>
    with WidgetsBindingObserver {
  late PageController _controller;
  late int _logicalPage;
  late int _reportedPage;
  int? _programmaticTarget;
  Timer? _autoPlayTimer;
  bool _foreground = true;

  void _scheduleAutoPlay() {
    _autoPlayTimer?.cancel();
    if (!mounted ||
        !widget.autoPlay ||
        !_foreground ||
        widget.children.length < 2 ||
        !_controller.hasClients ||
        _controller.position.isScrollingNotifier.value) {
      return;
    }
    if (!_loops && _logicalPage == widget.children.length - 1) return;
    _autoPlayTimer = Timer(widget.autoPlayInterval, () {
      if (!mounted || !_controller.hasClients) return;
      final target =
          (_controller.page ?? _controller.initialPage.toDouble()).round() + 1;
      _moveTo(target);
    });
  }

  void _moveTo(int target) {
    if (_controller.page == target) return;
    _autoPlayTimer?.cancel();
    _programmaticTarget = widget.children.isEmpty
        ? 0
        : target % widget.children.length;
    if (widget.duration <= Duration.zero || widget.children.isEmpty) {
      _controller.jumpToPage(target);
    } else {
      _controller.animateToPage(
        target,
        duration: widget.duration,
        curve: widget.curve,
      );
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _scheduleAutoPlay();
  }

  void _reportPage() {
    if (_reportedPage == _logicalPage) return;
    _reportedPage = _logicalPage;
    widget.onPageChanged?.call(_logicalPage);
  }

  bool get _loops => widget.loop && widget.children.length > 1;

  int _initialVirtualPage(int page) => _loops
      ? (1000000 ~/ widget.children.length) * widget.children.length + page
      : page;

  int _nearestVirtualPage(int page) {
    if (!_loops) return page;
    final current = (_controller.page ?? _controller.initialPage.toDouble())
        .round();
    final count = widget.children.length;
    final forward = (page - current % count) % count;
    final delta = forward > count / 2 ? forward - count : forward;
    return current + delta;
  }

  int _boundedPage(int page) =>
      widget.children.isEmpty ? 0 : page.clamp(0, widget.children.length - 1);

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _foreground =
        WidgetsBinding.instance.lifecycleState == null ||
        WidgetsBinding.instance.lifecycleState == AppLifecycleState.resumed;
    _logicalPage = _boundedPage(widget.page ?? widget.initialPage);
    _reportedPage = _logicalPage;
    _controller = PageController(
      initialPage: _initialVirtualPage(_logicalPage),
      keepPage: false,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoPlay());
  }

  @override
  void didUpdateWidget(covariant _JsUiPageView oldWidget) {
    super.didUpdateWidget(oldWidget);
    final structureChanged =
        widget.loop != oldWidget.loop ||
        widget.children.length != oldWidget.children.length;
    if (structureChanged) {
      final previous = _controller;
      _logicalPage = _boundedPage(widget.page ?? _logicalPage);
      _reportedPage = _logicalPage;
      _programmaticTarget = null;
      _controller = PageController(
        initialPage: _initialVirtualPage(_logicalPage),
        keepPage: false,
      );
      WidgetsBinding.instance.addPostFrameCallback((_) => previous.dispose());
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoPlay());
      return;
    }
    if (widget.page != null && widget.page != oldWidget.page) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted || !_controller.hasClients || widget.page == null) return;
        final target = _nearestVirtualPage(_boundedPage(widget.page!));
        _moveTo(target);
      });
    }
    if (widget.autoPlay != oldWidget.autoPlay ||
        widget.autoPlayInterval != oldWidget.autoPlayInterval) {
      _autoPlayTimer?.cancel();
      WidgetsBinding.instance.addPostFrameCallback((_) => _scheduleAutoPlay());
    }
  }

  @override
  void dispose() {
    _autoPlayTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      NotificationListener<ScrollNotification>(
        onNotification: (notification) {
          if (notification.depth != 0) return false;
          if (notification is ScrollStartNotification) _autoPlayTimer?.cancel();
          if (notification is ScrollStartNotification &&
              notification.dragDetails != null) {
            _programmaticTarget = null;
          }
          if (notification is ScrollEndNotification) {
            _programmaticTarget = null;
            _reportPage();
            scheduleMicrotask(_scheduleAutoPlay);
          }
          return false;
        },
        child: PageView.builder(
          key: ObjectKey(_controller),
          controller: _controller,
          scrollDirection: widget.scrollDirection,
          pageSnapping: widget.pageSnapping,
          physics: widget.physics,
          onPageChanged: (index) {
            if (widget.children.isEmpty) return;
            final logical = index % widget.children.length;
            _logicalPage = logical;
            if (_programmaticTarget == null || logical == _programmaticTarget) {
              _reportPage();
            }
          },
          itemCount: _loops ? null : widget.children.length,
          itemBuilder: (context, index) => KeyedSubtree(
            key: ValueKey(index),
            child: widget.children[index % widget.children.length],
          ),
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
