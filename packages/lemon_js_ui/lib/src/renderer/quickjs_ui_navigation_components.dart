import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiNavigationComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'Scaffold': _buildScaffold,
      'AppBar': _buildAppBar,
      'BottomNavigationBar': _buildBottomNavigationBar,
      'TabBar': _buildTabBar,
      'TabBarView': _buildTabBarView,
      'Drawer': _buildDrawer,
    };

Widget _buildScaffold(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final appBar = quickjsUiNodeProp(node.props['appBar']);
  final body = quickjsUiNodeProp(node.props['body']);
  final bottomNavigationBar = quickjsUiNodeProp(
    node.props['bottomNavigationBar'],
  );
  final drawer = quickjsUiNodeProp(node.props['drawer']);
  final floatingActionButton = quickjsUiNodeProp(
    node.props['floatingActionButton'],
  );
  final scaffold = Scaffold(
    appBar: appBar == null
        ? null
        : quickjsUiAsPreferredSizeWidget(
            context.build(appBar),
            'Scaffold.appBar',
          ),
    body: body == null ? context.child(node) : context.build(body),
    drawer: drawer == null ? null : context.build(drawer),
    bottomNavigationBar: bottomNavigationBar == null
        ? null
        : context.build(bottomNavigationBar),
    floatingActionButton: floatingActionButton == null
        ? null
        : context.build(floatingActionButton),
    backgroundColor: context.color(node.props['backgroundColor']),
  );
  final tabLength = QuickjsUiProps.intValue(node.props['tabLength']);
  if (tabLength == null || tabLength <= 0) {
    return scaffold;
  }
  return DefaultTabController(
    length: tabLength,
    initialIndex: QuickjsUiProps.intValue(node.props['initialTabIndex']) ?? 0,
    child: scaffold,
  );
}

Widget _buildAppBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final title = quickjsUiNodeProp(node.props['title']);
  final leading = quickjsUiNodeProp(node.props['leading']);
  final bottom = quickjsUiNodeProp(node.props['bottom']);
  return AppBar(
    title: title == null
        ? quickjsUiOptionalText(QuickjsUiProps.string(node.props['titleText']))
        : context.build(title),
    leading: leading == null ? null : context.build(leading),
    actions: quickjsUiNodeListProp(context, node.props['actions']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    centerTitle: QuickjsUiProps.boolValue(node.props['centerTitle']),
    elevation: context.elevation(node.props['elevation']),
    bottom: bottom == null
        ? null
        : quickjsUiAsPreferredSizeWidget(
            context.build(bottom),
            'AppBar.bottom',
          ),
  );
}

Widget _buildBottomNavigationBar(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  return BottomNavigationBar(
    currentIndex: QuickjsUiProps.intValue(node.props['currentIndex']) ?? 0,
    type: node.props['typeMode'] == 'shifting'
        ? BottomNavigationBarType.shifting
        : BottomNavigationBarType.fixed,
    onTap: onTap == null
        ? null
        : (index) => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onTap'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    items: quickjsUiBottomNavigationItems(context, node.props['items']),
  );
}

Widget _buildTabBar(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  return TabBar(
    isScrollable: QuickjsUiProps.boolValue(node.props['isScrollable']) ?? false,
    onTap: onTap == null
        ? null
        : (index) => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onTap'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    tabs: quickjsUiTabs(context, node.props['tabs']),
  );
}

Widget _buildTabBarView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return TabBarView(children: context.children(node));
}

Widget _buildDrawer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Drawer(child: context.child(node));
}
