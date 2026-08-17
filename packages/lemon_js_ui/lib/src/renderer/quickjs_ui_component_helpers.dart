// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

export 'quickjs_ui_component_types.dart';

JsUiNode? jsUiNodeProp(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is Map) {
    return JsUiNode.fromMap(
      value.map((key, value) => MapEntry<String, Object?>('$key', value)),
    );
  }
  throw const FormatException('quickjs_ui node property must be an object');
}

List<Widget>? jsUiNodeListProp(JsUiRenderContext context, Object? value) {
  if (value == null) {
    return null;
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui node list property must be a list');
  }
  return <Widget>[
    for (final item in value)
      if (jsUiNodeProp(item) case final node?) context.build(node),
  ];
}

PreferredSizeWidget jsUiAsPreferredSizeWidget(Widget widget, String name) {
  if (widget is PreferredSizeWidget) {
    return widget;
  }
  throw FormatException('quickjs_ui $name must render a PreferredSizeWidget');
}

Widget? jsUiOptionalText(String? value) {
  if (value == null) {
    return null;
  }
  return Text(value);
}

double jsUiGap(JsUiRenderContext context, JsUiNode node) {
  return context.spacing(node.props['gap'], name: 'gap') ?? 0;
}

Duration? jsUiAnimationDuration(JsUiNode node) {
  return JsUiProps.duration(
    node.props['animationDurationMs'] ?? node.props['durationMs'],
    name: 'animation duration',
  );
}

EdgeInsets jsUiEdgeInsets(EdgeInsetsGeometry? value) {
  return switch (value) {
    null => EdgeInsets.zero,
    EdgeInsets edgeInsets => edgeInsets,
    _ => EdgeInsets.zero,
  };
}

IconData jsUiIconData(String? name) {
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

List<BottomNavigationBarItem> jsUiBottomNavigationItems(
  JsUiRenderContext context,
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
  JsUiRenderContext context,
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
  final icon = jsUiNodeProp(props['icon']);
  final activeIcon = jsUiNodeProp(props['activeIcon']);
  return BottomNavigationBarItem(
    icon: icon == null
        ? Icon(jsUiIconData(JsUiProps.string(props['iconName'])))
        : context.build(icon),
    activeIcon: activeIcon == null ? null : context.build(activeIcon),
    label: JsUiProps.string(props['label']) ?? '',
    tooltip: JsUiProps.string(props['tooltip']),
  );
}

List<Widget> jsUiTabs(JsUiRenderContext context, Object? value) {
  if (value is! List || value.isEmpty) {
    throw const FormatException(
      'quickjs_ui TabBar.tabs must be a non-empty list',
    );
  }
  return <Widget>[for (final tab in value) _tab(context, tab)];
}

Widget _tab(JsUiRenderContext context, Object? value) {
  if (value is String) {
    return Tab(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final child = jsUiNodeProp(props['child']);
    final icon = jsUiNodeProp(props['icon']);
    return Tab(
      text: JsUiProps.string(props['text'] ?? props['label']),
      icon: icon == null ? null : context.build(icon),
      child: child == null ? null : context.build(child),
    );
  }
  throw const FormatException('quickjs_ui Tab must be a string or object');
}
