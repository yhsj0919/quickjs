import 'package:flutter/widgets.dart';

import 'quickjs_ui_component_registry.dart';
import 'quickjs_ui_node.dart';
import 'quickjs_ui_render_context.dart';

final class QuickjsUiRenderer {
  QuickjsUiRenderer({
    required this.onEvent,
    QuickjsUiComponentRegistry? registry,
  }) : registry = registry ?? QuickjsUiComponentRegistry.defaults();

  final QuickjsUiEventHandler onEvent;
  final QuickjsUiComponentRegistry registry;

  Widget build(QuickjsUiNode node) {
    late final QuickjsUiRenderContext context;
    context = QuickjsUiRenderContext(
      buildNode: (node) => registry.build(context, node),
      onEvent: onEvent,
    );
    return registry.build(context, node);
  }
}
