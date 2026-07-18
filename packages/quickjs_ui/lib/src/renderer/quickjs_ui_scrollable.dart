import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final class QuickjsUiScrollCommand {
  const QuickjsUiScrollCommand({
    this.initialScrollOffset = 0,
    this.scrollToOffset,
    this.scrollToKey,
    this.scrollToken = 0,
    this.scrollDuration,
    this.scrollCurve = Curves.easeOut,
  });

  final double initialScrollOffset;
  final double? scrollToOffset;
  final String? scrollToKey;
  final int scrollToken;
  final Duration? scrollDuration;
  final Curve scrollCurve;

  static QuickjsUiScrollCommand fromNode(QuickjsUiNode node) {
    return QuickjsUiScrollCommand(
      initialScrollOffset:
          QuickjsUiProps.number(
            node.props['initialScrollOffset'],
            name: 'initialScrollOffset',
          ) ??
          0,
      scrollToOffset: QuickjsUiProps.number(
        node.props['scrollToOffset'],
        name: 'scrollToOffset',
      ),
      scrollToKey: QuickjsUiProps.string(node.props['scrollToKey']),
      scrollToken:
          QuickjsUiProps.intValue(node.props['scrollToken']) ??
          QuickjsUiProps.intValue(node.props['scrollToToken']) ??
          0,
      scrollDuration: QuickjsUiProps.duration(
        node.props['scrollDurationMs'],
        name: 'scroll duration',
      ),
      scrollCurve: QuickjsUiProps.curve(node.props['scrollCurve']),
    );
  }
}

List<String?> quickjsUiChildKeys(QuickjsUiNode node) {
  return <String?>[
    for (final child in node.children)
      QuickjsUiProps.string(child.props['key'], name: 'child key'),
  ];
}

Duration quickjsUiItemTransitionDuration(QuickjsUiNode node) {
  return QuickjsUiProps.duration(
        node.props['itemTransitionDurationMs'] ??
            node.props['animationDurationMs'] ??
            node.props['durationMs'],
        name: 'item transition duration',
      ) ??
      const Duration(milliseconds: 250);
}

Curve quickjsUiItemTransitionCurve(QuickjsUiNode node) {
  return QuickjsUiProps.curve(
    node.props['itemTransitionCurve'] ?? node.props['curve'],
  );
}

Widget quickjsUiWrapScrollNotifications({
  required QuickjsUiRenderContext context,
  required QuickjsUiNode node,
  required Widget child,
}) {
  final onScroll = QuickjsUiProps.event(node.props['onScroll']);
  if (onScroll == null) {
    return child;
  }
  return NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      final metrics = notification.metrics;
      context.dispatchEvent(
        onScroll,
        defaultCoalesceKey: quickjsUiEventKey(node, 'onScroll'),
        kind: QuickjsUiEventKind.sample,
        payload: <String, Object?>{
          'pixels': metrics.pixels,
          'minScrollExtent': metrics.minScrollExtent,
          'maxScrollExtent': metrics.maxScrollExtent,
          'viewportDimension': metrics.viewportDimension,
          'axis': metrics.axis.name,
        },
      );
      return false;
    },
    child: child,
  );
}

final class QuickjsUiScrollableList extends StatefulWidget {
  const QuickjsUiScrollableList({
    super.key,
    required this.axis,
    required this.shrinkWrap,
    required this.padding,
    required this.childCount,
    required this.childBuilder,
    required this.childKeys,
    required this.gap,
    required this.itemExtent,
    required this.cacheExtent,
    required this.addAutomaticKeepAlives,
    required this.addRepaintBoundaries,
    required this.scroll,
    required this.animateItems,
    required this.itemDuration,
    required this.itemCurve,
  });

  final Axis axis;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final int childCount;
  final Widget Function(int index) childBuilder;
  final List<String?> childKeys;
  final double gap;
  final double? itemExtent;
  final double? cacheExtent;
  final bool addAutomaticKeepAlives;
  final bool addRepaintBoundaries;
  final QuickjsUiScrollCommand scroll;
  final bool animateItems;
  final Duration itemDuration;
  final Curve itemCurve;

  @override
  State<QuickjsUiScrollableList> createState() =>
      _QuickjsUiScrollableListState();
}

final class QuickjsUiBuilderList extends StatefulWidget {
  const QuickjsUiBuilderList({
    super.key,
    required this.listKey,
    required this.itemCount,
    required this.batchStart,
    required this.batchEnd,
    required this.prefetchItemCount,
    required this.resetToken,
    required this.hasMore,
    required this.loading,
    required this.loadMoreThreshold,
    required this.loadingText,
    required this.axis,
    required this.shrinkWrap,
    required this.padding,
    required this.itemExtent,
    required this.estimatedItemExtent,
    required this.cacheExtent,
    required this.scroll,
    required this.batchChildren,
    required this.requestRange,
    required this.loadMore,
  });

  final String listKey;
  final int itemCount;
  final int batchStart;
  final int batchEnd;
  final int prefetchItemCount;
  final Object? resetToken;
  final bool hasMore;
  final bool loading;
  final int loadMoreThreshold;
  final String? loadingText;
  final Axis axis;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final double? itemExtent;
  final double? estimatedItemExtent;
  final double? cacheExtent;
  final QuickjsUiScrollCommand scroll;
  final List<Widget> batchChildren;
  final void Function(int start, int end) requestRange;
  final VoidCallback? loadMore;

  @override
  State<QuickjsUiBuilderList> createState() => _QuickjsUiBuilderListState();
}

final class _QuickjsUiBuilderListState extends State<QuickjsUiBuilderList> {
  late final ScrollController _controller;
  final Map<int, Widget> _items = <int, Widget>{};
  int _loadedEnd = 0;
  int _lastScrollToken = 0;
  bool _requestPending = false;
  bool _loadMoreRequested = false;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.scroll.initialScrollOffset,
    );
    _lastScrollToken = widget.scroll.scrollToken;
    _mergeBatch();
  }

  @override
  void didUpdateWidget(covariant QuickjsUiBuilderList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.listKey != widget.listKey ||
        oldWidget.resetToken != widget.resetToken) {
      _items.clear();
      _loadedEnd = 0;
    }
    _mergeBatch();
    _requestPending = false;
    if (widget.itemCount > oldWidget.itemCount ||
        (oldWidget.loading && !widget.loading) ||
        !widget.hasMore) {
      _loadMoreRequested = false;
    }
    if (widget.scroll.scrollToken != _lastScrollToken) {
      _lastScrollToken = widget.scroll.scrollToken;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollCommand(),
      );
    }
  }

  void _mergeBatch() {
    for (var offset = 0; offset < widget.batchChildren.length; offset++) {
      _items[widget.batchStart + offset] = widget.batchChildren[offset];
    }
    if (widget.batchStart <= _loadedEnd) {
      _loadedEnd = math.max(_loadedEnd, widget.batchEnd);
    }
  }

  void _requestMore() {
    if (_requestPending || _loadedEnd >= widget.itemCount) {
      return;
    }
    _requestPending = true;
    final start = _loadedEnd;
    final end = math.min<int>(
      widget.itemCount,
      start + math.max<int>(1, widget.prefetchItemCount),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.requestRange(start, end);
      }
    });
  }

  void _requestLoadMore() {
    if (_loadMoreRequested ||
        widget.loading ||
        !widget.hasMore ||
        widget.loadMore == null) {
      return;
    }
    _loadMoreRequested = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        widget.loadMore?.call();
      }
    });
  }

  void _applyScrollCommand() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final offset = widget.scroll.scrollToOffset;
    if (offset == null) {
      return;
    }
    final position = _controller.position;
    _controller.animateTo(
      offset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration:
          widget.scroll.scrollDuration ?? const Duration(milliseconds: 250),
      curve: widget.scroll.scrollCurve,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final hasUnbuiltItems = _loadedEnd < widget.itemCount;
    final showFooter = hasUnbuiltItems || widget.hasMore || widget.loading;
    final visibleCount = _loadedEnd + (showFooter ? 1 : 0);
    return ListView.builder(
      controller: _controller,
      scrollDirection: widget.axis,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      scrollCacheExtent: widget.cacheExtent == null
          ? null
          : ScrollCacheExtent.pixels(widget.cacheExtent!),
      itemCount: visibleCount,
      itemBuilder: (context, index) {
        if (index >= _loadedEnd) {
          final loadingExtent = widget.estimatedItemExtent ?? 48;
          if (hasUnbuiltItems) {
            _requestMore();
            return SizedBox(
              width: widget.axis == Axis.horizontal ? loadingExtent : null,
              height: widget.axis == Axis.vertical ? loadingExtent : null,
            );
          }
          _requestLoadMore();
          return SizedBox(
            width: widget.axis == Axis.horizontal ? loadingExtent : null,
            height: widget.axis == Axis.vertical ? loadingExtent : null,
            child: Center(child: _buildLoadingIndicator()),
          );
        }
        if (index >= _loadedEnd - widget.prefetchItemCount) {
          _requestMore();
        }
        if (index >= _loadedEnd - math.max<int>(1, widget.loadMoreThreshold)) {
          if (!hasUnbuiltItems) {
            _requestLoadMore();
          }
        }
        return _items[index] ?? const SizedBox.shrink();
      },
    );
  }

  Widget _buildLoadingIndicator() {
    final text = widget.loadingText;
    if (text == null || text.isEmpty) {
      return const SizedBox.square(
        dimension: 24,
        child: CircularProgressIndicator(strokeWidth: 2),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: <Widget>[
        const SizedBox.square(
          dimension: 20,
          child: CircularProgressIndicator(strokeWidth: 2),
        ),
        const SizedBox(width: 10),
        Text(text),
      ],
    );
  }
}

final class _QuickjsUiScrollableListState
    extends State<QuickjsUiScrollableList> {
  late final ScrollController _controller;
  final Map<String, GlobalKey> _itemKeys = <String, GlobalKey>{};
  int _lastScrollToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.scroll.initialScrollOffset,
    );
    _lastScrollToken = widget.scroll.scrollToken;
    if (widget.scroll.scrollToken > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollCommand(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant QuickjsUiScrollableList oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scroll.scrollToken != _lastScrollToken) {
      _lastScrollToken = widget.scroll.scrollToken;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollCommand(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyScrollCommand() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final scroll = widget.scroll;
    final duration = scroll.scrollDuration ?? const Duration(milliseconds: 250);
    final scrollToKey = scroll.scrollToKey;
    if (scrollToKey != null && scrollToKey.isNotEmpty) {
      final targetContext = _itemKeys[scrollToKey]?.currentContext;
      if (targetContext != null) {
        Scrollable.ensureVisible(
          targetContext,
          duration: duration,
          curve: scroll.scrollCurve,
          alignment: 0,
        );
        return;
      }
      final index = widget.childKeys.indexOf(scrollToKey);
      if (index != -1 && widget.childKeys.length > 1) {
        final position = _controller.position;
        final targetOffset =
            position.maxScrollExtent * index / (widget.childKeys.length - 1);
        _controller.animateTo(
          targetOffset.clamp(
            position.minScrollExtent,
            position.maxScrollExtent,
          ),
          duration: duration,
          curve: scroll.scrollCurve,
        );
      }
      return;
    }

    final scrollToOffset = scroll.scrollToOffset;
    if (scrollToOffset == null) {
      return;
    }
    final position = _controller.position;
    _controller.animateTo(
      scrollToOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration: duration,
      curve: scroll.scrollCurve,
    );
  }

  Widget _wrapItem(String? key, Widget child) {
    if (key == null || key.isEmpty) {
      return child;
    }
    final globalKey = _itemKeys.putIfAbsent(key, GlobalKey.new);
    return KeyedSubtree(key: globalKey, child: child);
  }

  @override
  Widget build(BuildContext context) {
    if (widget.animateItems) {
      final children = <Widget>[
        for (var index = 0; index < widget.childCount; index++)
          widget.childBuilder(index),
      ];
      return QuickjsUiAnimatedListView(
        controller: _controller,
        axis: widget.axis,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        duration: widget.itemDuration,
        curve: widget.itemCurve,
        items: <QuickjsUiAnimatedListItem>[
          for (var index = 0; index < children.length; index++)
            QuickjsUiAnimatedListItem(
              key: widget.childKeys[index]!,
              child: children[index],
            ),
        ],
      );
    }

    Widget buildItem(BuildContext context, int index) =>
        _wrapItem(widget.childKeys[index], widget.childBuilder(index));

    if (widget.gap > 0) {
      return ListView.separated(
        controller: _controller,
        scrollDirection: widget.axis,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        scrollCacheExtent: widget.cacheExtent == null
            ? null
            : ScrollCacheExtent.pixels(widget.cacheExtent!),
        addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
        addRepaintBoundaries: widget.addRepaintBoundaries,
        itemCount: widget.childCount,
        itemBuilder: buildItem,
        separatorBuilder: (_, _) => widget.axis == Axis.horizontal
            ? SizedBox(width: widget.gap)
            : SizedBox(height: widget.gap),
      );
    }

    return ListView.builder(
      controller: _controller,
      scrollDirection: widget.axis,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      itemExtent: widget.itemExtent,
      scrollCacheExtent: widget.cacheExtent == null
          ? null
          : ScrollCacheExtent.pixels(widget.cacheExtent!),
      addAutomaticKeepAlives: widget.addAutomaticKeepAlives,
      addRepaintBoundaries: widget.addRepaintBoundaries,
      itemCount: widget.childCount,
      itemBuilder: buildItem,
    );
  }
}

final class QuickjsUiScrollableColumn extends StatefulWidget {
  const QuickjsUiScrollableColumn({
    super.key,
    required this.padding,
    required this.children,
    required this.scroll,
  });

  final EdgeInsetsGeometry? padding;
  final List<Widget> children;
  final QuickjsUiScrollCommand scroll;

  @override
  State<QuickjsUiScrollableColumn> createState() =>
      _QuickjsUiScrollableColumnState();
}

final class _QuickjsUiScrollableColumnState
    extends State<QuickjsUiScrollableColumn> {
  late final ScrollController _controller;
  int _lastScrollToken = 0;

  @override
  void initState() {
    super.initState();
    _controller = ScrollController(
      initialScrollOffset: widget.scroll.initialScrollOffset,
    );
    _lastScrollToken = widget.scroll.scrollToken;
    if (widget.scroll.scrollToken > 0) {
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollCommand(),
      );
    }
  }

  @override
  void didUpdateWidget(covariant QuickjsUiScrollableColumn oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.scroll.scrollToken != _lastScrollToken) {
      _lastScrollToken = widget.scroll.scrollToken;
      WidgetsBinding.instance.addPostFrameCallback(
        (_) => _applyScrollCommand(),
      );
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _applyScrollCommand() {
    if (!mounted || !_controller.hasClients) {
      return;
    }
    final scrollToOffset = widget.scroll.scrollToOffset;
    if (scrollToOffset == null) {
      return;
    }
    final position = _controller.position;
    _controller.animateTo(
      scrollToOffset.clamp(position.minScrollExtent, position.maxScrollExtent),
      duration:
          widget.scroll.scrollDuration ?? const Duration(milliseconds: 250),
      curve: widget.scroll.scrollCurve,
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      controller: _controller,
      padding: widget.padding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: widget.children,
      ),
    );
  }
}

final class QuickjsUiAnimatedListItem {
  const QuickjsUiAnimatedListItem({required this.key, required this.child});

  final String key;
  final Widget child;
}

final class QuickjsUiAnimatedListView extends StatefulWidget {
  const QuickjsUiAnimatedListView({
    super.key,
    required this.controller,
    required this.axis,
    required this.shrinkWrap,
    required this.padding,
    required this.duration,
    required this.curve,
    required this.items,
  });

  final ScrollController controller;
  final Axis axis;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final Duration duration;
  final Curve curve;
  final List<QuickjsUiAnimatedListItem> items;

  @override
  State<QuickjsUiAnimatedListView> createState() =>
      _QuickjsUiAnimatedListViewState();
}

final class _QuickjsUiAnimatedListViewState
    extends State<QuickjsUiAnimatedListView> {
  final GlobalKey<AnimatedListState> _listKey = GlobalKey<AnimatedListState>();
  late List<QuickjsUiAnimatedListItem> _items;

  @override
  void initState() {
    super.initState();
    _items = List<QuickjsUiAnimatedListItem>.of(widget.items);
  }

  @override
  void didUpdateWidget(covariant QuickjsUiAnimatedListView oldWidget) {
    super.didUpdateWidget(oldWidget);
    _syncItems(widget.items);
  }

  void _syncItems(List<QuickjsUiAnimatedListItem> target) {
    final listState = _listKey.currentState;
    if (listState == null) {
      _items = List<QuickjsUiAnimatedListItem>.of(target);
      return;
    }

    final targetByKey = <String, QuickjsUiAnimatedListItem>{
      for (final item in target) item.key: item,
    };

    var index = 0;
    while (index < _items.length) {
      if (!targetByKey.containsKey(_items[index].key)) {
        final removed = _items.removeAt(index);
        listState.removeItem(
          index,
          (context, animation) => _transition(removed.child, animation),
          duration: widget.duration,
        );
        continue;
      }
      index++;
    }

    final existingKeys = _items.map((item) => item.key).toSet();
    final reordered = <QuickjsUiAnimatedListItem>[];
    for (final item in target) {
      if (existingKeys.contains(item.key)) {
        reordered.add(item);
      }
    }
    _items = reordered;

    for (var targetIndex = 0; targetIndex < target.length; targetIndex++) {
      final item = target[targetIndex];
      if (existingKeys.contains(item.key)) {
        continue;
      }
      final insertIndex = targetIndex.clamp(0, _items.length);
      _items.insert(insertIndex, item);
      listState.insertItem(insertIndex, duration: widget.duration);
    }
  }

  Widget _transition(Widget child, Animation<double> animation) {
    final curved = CurvedAnimation(parent: animation, curve: widget.curve);
    return SizeTransition(
      axis: widget.axis,
      sizeFactor: curved,
      child: FadeTransition(opacity: animation, child: child),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedList(
      key: _listKey,
      controller: widget.controller,
      scrollDirection: widget.axis,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      initialItemCount: _items.length,
      itemBuilder: (context, index, animation) {
        if (index >= _items.length) {
          return const SizedBox.shrink();
        }
        return _transition(_items[index].child, animation);
      },
    );
  }
}
