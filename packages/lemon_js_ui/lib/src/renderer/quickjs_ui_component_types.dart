// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/widgets.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_render_context.dart';

typedef JsUiComponentBuilder =
    Widget Function(JsUiRenderContext context, JsUiNode node);

typedef JsUiComponentBuilderMap = Map<String, JsUiComponentBuilder>;
