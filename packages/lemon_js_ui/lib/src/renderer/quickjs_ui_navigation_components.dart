// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiNavigationComponentBuilders =
    <String, JsUiComponentBuilder>{
      'Scaffold': _buildScaffold,
      'AppBar': _buildAppBar,
      'BottomNavigationBar': _buildBottomNavigationBar,
      'TabBar': _buildTabBar,
      'TabBarView': _buildTabBarView,
      'Drawer': _buildDrawer,
    };

Widget _buildScaffold(JsUiRenderContext context, JsUiNode node) {
  final appBar = jsUiNodeProp(node.props['appBar']);
  final body = jsUiNodeProp(node.props['body']);
  final bottomNavigationBar = jsUiNodeProp(node.props['bottomNavigationBar']);
  final drawer = jsUiNodeProp(node.props['drawer']);
  final floatingActionButton = jsUiNodeProp(node.props['floatingActionButton']);
  final scaffold = Scaffold(
    appBar: appBar == null
        ? null
        : jsUiAsPreferredSizeWidget(context.build(appBar), 'Scaffold.appBar'),
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
  final tabLength = JsUiProps.intValue(node.props['tabLength']);
  if (tabLength == null || tabLength <= 0) {
    return scaffold;
  }
  return DefaultTabController(
    length: tabLength,
    initialIndex: JsUiProps.intValue(node.props['initialTabIndex']) ?? 0,
    child: scaffold,
  );
}

Widget _buildAppBar(JsUiRenderContext context, JsUiNode node) {
  final title = jsUiNodeProp(node.props['title']);
  final leading = jsUiNodeProp(node.props['leading']);
  final bottom = jsUiNodeProp(node.props['bottom']);
  return AppBar(
    title: title == null
        ? jsUiOptionalText(JsUiProps.string(node.props['titleText']))
        : context.build(title),
    leading: leading == null ? null : context.build(leading),
    actions: jsUiNodeListProp(context, node.props['actions']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    centerTitle: JsUiProps.boolValue(node.props['centerTitle']),
    elevation: context.elevation(node.props['elevation']),
    bottom: bottom == null
        ? null
        : jsUiAsPreferredSizeWidget(context.build(bottom), 'AppBar.bottom'),
  );
}

Widget _buildBottomNavigationBar(JsUiRenderContext context, JsUiNode node) {
  final onTap = JsUiProps.event(node.props['onTap']);
  return BottomNavigationBar(
    currentIndex: JsUiProps.intValue(node.props['currentIndex']) ?? 0,
    type: node.props['typeMode'] == 'shifting'
        ? BottomNavigationBarType.shifting
        : BottomNavigationBarType.fixed,
    onTap: onTap == null
        ? null
        : (index) => context.dispatch(
            onTap,
            defaultCoalesceKey: jsUiEventKey(node, 'onTap'),
            kind: JsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    items: jsUiBottomNavigationItems(context, node.props['items']),
  );
}

Widget _buildTabBar(JsUiRenderContext context, JsUiNode node) {
  final onTap = JsUiProps.event(node.props['onTap']);
  return TabBar(
    isScrollable: JsUiProps.boolValue(node.props['isScrollable']) ?? false,
    onTap: onTap == null
        ? null
        : (index) => context.dispatch(
            onTap,
            defaultCoalesceKey: jsUiEventKey(node, 'onTap'),
            kind: JsUiEventKind.sample,
            payload: <String, Object?>{'index': index},
          ),
    tabs: jsUiTabs(context, node.props['tabs']),
  );
}

Widget _buildTabBarView(JsUiRenderContext context, JsUiNode node) {
  return TabBarView(children: context.children(node));
}

Widget _buildDrawer(JsUiRenderContext context, JsUiNode node) {
  return Drawer(child: context.child(node));
}
