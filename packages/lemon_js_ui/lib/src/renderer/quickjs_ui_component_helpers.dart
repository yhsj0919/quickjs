import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

export 'quickjs_ui_component_types.dart';

QuickjsUiNode? quickjsUiNodeProp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return QuickjsUiNode.fromMap(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw const FormatException('quickjs_ui node property must be an object');
}

List<Widget>? quickjsUiNodeListProp(
  QuickjsUiRenderContext context,
  Object? value,
) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui node list property must be a list');
  }
  return <Widget>[
    for (final item in value)
      if (quickjsUiNodeProp(item) case final node?) context.build(node),
  ];
}

PreferredSizeWidget quickjsUiAsPreferredSizeWidget(Widget widget, String name) {
  if (widget is PreferredSizeWidget) {
    return widget;
  }
  throw FormatException('quickjs_ui $name must render a PreferredSizeWidget');
}

Widget? quickjsUiOptionalText(String? value) {
  if (value == null) {
    return null;
  }
  return Text(value);
}

double quickjsUiGap(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return context.spacing(node.props['gap'], name: 'gap') ?? 0;
}

Duration? quickjsUiAnimationDuration(QuickjsUiNode node) {
  return QuickjsUiProps.duration(
    node.props['animationDurationMs'] ?? node.props['durationMs'],
    name: 'animation duration',
  );
}

EdgeInsets quickjsUiEdgeInsets(EdgeInsetsGeometry? value) {
  return switch (value) {
    null => EdgeInsets.zero,
    EdgeInsets edgeInsets => edgeInsets,
    _ => EdgeInsets.zero,
  };
}

IconData quickjsUiIconData(String? name) {
  return switch (name) {
    'add' => Icons.add,
    'arrowBack' || 'back' => Icons.arrow_back,
    'check' => Icons.check,
    'close' => Icons.close,
    'delete' => Icons.delete,
    'edit' => Icons.edit,
    'favorite' => Icons.favorite,
    'home' => Icons.home,
    'info' => Icons.info,
    'menu' => Icons.menu,
    'moreVert' => Icons.more_vert,
    'pause' => Icons.pause,
    'playArrow' || 'play' => Icons.play_arrow,
    'refresh' => Icons.refresh,
    'search' => Icons.search,
    'settings' => Icons.settings,
    'share' => Icons.share,
    'star' => Icons.star,
    'warning' => Icons.warning,
    _ => Icons.help_outline,
  };
}

List<BottomNavigationBarItem> quickjsUiBottomNavigationItems(
  QuickjsUiRenderContext context,
  Object? value,
) {
  if (value is! List || value.length < 2) {
    throw const FormatException(
      'quickjs_ui BottomNavigationBar.items must contain at least two items',
    );
  }
  return <BottomNavigationBarItem>[
    for (final item in value) _bottomNavigationItem(context, item),
  ];
}

BottomNavigationBarItem _bottomNavigationItem(
  QuickjsUiRenderContext context,
  Object? value,
) {
  if (value is! Map) {
    throw const FormatException(
      'quickjs_ui BottomNavigationBar item must be an object',
    );
  }
  final props = value.map(
    (key, value) => MapEntry<String, Object?>('$key', value),
  );
  final icon = quickjsUiNodeProp(props['icon']);
  final activeIcon = quickjsUiNodeProp(props['activeIcon']);
  return BottomNavigationBarItem(
    icon: icon == null
        ? Icon(quickjsUiIconData(QuickjsUiProps.string(props['iconName'])))
        : context.build(icon),
    activeIcon: activeIcon == null ? null : context.build(activeIcon),
    label: QuickjsUiProps.string(props['label']) ?? '',
    tooltip: QuickjsUiProps.string(props['tooltip']),
  );
}

List<Widget> quickjsUiTabs(QuickjsUiRenderContext context, Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException(
      'quickjs_ui TabBar.tabs must be a non-empty list',
    );
  }
  return <Widget>[for (final tab in value) _tab(context, tab)];
}

Widget _tab(QuickjsUiRenderContext context, Object? value) {
  if (value is String) {
    return Tab(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final child = quickjsUiNodeProp(props['child']);
    final icon = quickjsUiNodeProp(props['icon']);
    return Tab(
      text: QuickjsUiProps.string(props['text'] ?? props['label']),
      icon: icon == null ? null : context.build(icon),
      child: child == null ? null : context.build(child),
    );
  }
  throw const FormatException('quickjs_ui Tab must be a string or object');
}
