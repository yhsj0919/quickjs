import 'package:flutter/widgets.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_render_context.dart';

typedef QuickjsUiComponentBuilder =
    Widget Function(QuickjsUiRenderContext context, QuickjsUiNode node);

typedef QuickjsUiComponentBuilderMap = Map<String, QuickjsUiComponentBuilder>;
