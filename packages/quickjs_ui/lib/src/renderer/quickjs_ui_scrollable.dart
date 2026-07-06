import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
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
        defaultCoalesceKey: _eventKey(node, 'onScroll'),
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

String _eventKey(QuickjsUiNode node, String prop) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return '${node.type}:$key:$prop';
  }
  return '${node.type}:${identityHashCode(node)}:$prop';
}

final class QuickjsUiScrollableList extends StatefulWidget {
  const QuickjsUiScrollableList({
    super.key,
    required this.axis,
    required this.shrinkWrap,
    required this.padding,
    required this.children,
    required this.childKeys,
    required this.scroll,
    required this.animateItems,
    required this.itemDuration,
    required this.itemCurve,
  });

  final Axis axis;
  final bool shrinkWrap;
  final EdgeInsetsGeometry? padding;
  final List<Widget> children;
  final List<String?> childKeys;
  final QuickjsUiScrollCommand scroll;
  final bool animateItems;
  final Duration itemDuration;
  final Curve itemCurve;

  @override
  State<QuickjsUiScrollableList> createState() =>
      _QuickjsUiScrollableListState();
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
      return QuickjsUiAnimatedListView(
        controller: _controller,
        axis: widget.axis,
        shrinkWrap: widget.shrinkWrap,
        padding: widget.padding,
        duration: widget.itemDuration,
        curve: widget.itemCurve,
        items: <QuickjsUiAnimatedListItem>[
          for (var index = 0; index < widget.children.length; index++)
            QuickjsUiAnimatedListItem(
              key: widget.childKeys[index]!,
              child: widget.children[index],
            ),
        ],
      );
    }

    return ListView(
      controller: _controller,
      scrollDirection: widget.axis,
      shrinkWrap: widget.shrinkWrap,
      padding: widget.padding,
      children: <Widget>[
        for (var index = 0; index < widget.children.length; index++)
          _wrapItem(widget.childKeys[index], widget.children[index]),
      ],
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
