import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_basic_components.dart';
import 'quickjs_ui_feedback_components.dart';
import 'quickjs_ui_input_components.dart';
import 'quickjs_ui_layout_components.dart';
import 'quickjs_ui_media_components.dart';
import 'quickjs_ui_navigation_components.dart';
import 'quickjs_ui_overlay_layer.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_scroll_components.dart';
import 'quickjs_ui_component_types.dart';

export 'quickjs_ui_component_types.dart';

typedef QuickjsUiComponentControllerFactory =
    QuickjsUiComponentController Function(QuickjsUiNode node);

typedef QuickjsUiLifecycleComponentBuilder<
  T extends QuickjsUiComponentController
> =
    Widget Function(
      QuickjsUiRenderContext context,
      QuickjsUiNode node,
      T controller,
    );

base class QuickjsUiComponentController {
  void mount(QuickjsUiNode node) {}

  void update(QuickjsUiNode previous, QuickjsUiNode next) {}

  void show() {}

  void hide() {}

  void pause() {}

  void resume() {}

  void dispose() {}
}

final class QuickjsUiComponentRegistry {
  QuickjsUiComponentRegistry([Map<String, QuickjsUiComponentBuilder>? builders])
    : _components = <String, _QuickjsUiComponentDefinition>{
        for (final entry in builders?.entries ?? const Iterable.empty())
          entry.key: _QuickjsUiComponentDefinition.builder(entry.value),
      };

  factory QuickjsUiComponentRegistry.defaults() {
    return QuickjsUiComponentRegistry(<String, QuickjsUiComponentBuilder>{
      ...quickjsUiBasicComponentBuilders,
      ...quickjsUiLayoutComponentBuilders,
      ...quickjsUiMediaComponentBuilders,
      ...quickjsUiScrollComponentBuilders,
      ...quickjsUiInputComponentBuilders,
      ...quickjsUiNavigationComponentBuilders,
      ...quickjsUiFeedbackComponentBuilders,
    });
  }

  final Map<String, _QuickjsUiComponentDefinition> _components;

  Iterable<String> get types => _components.keys;

  bool contains(String type) {
    return _components.containsKey(type);
  }

  void register(String type, QuickjsUiComponentBuilder builder) {
    _components[type] = _QuickjsUiComponentDefinition.builder(builder);
  }

  void registerLifecycle<T extends QuickjsUiComponentController>(
    String type, {
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    _components[type] = _QuickjsUiComponentDefinition.lifecycle(
      createController: createController,
      build: build,
    );
  }

  void unregister(String type) {
    _components.remove(type);
  }

  bool hasLifecycle(String type) {
    return _components[type]?.hasLifecycle == true;
  }

  QuickjsUiComponentController createController(QuickjsUiNode node) {
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    final create = component.createController;
    if (create == null) {
      throw FormatException(
        'quickjs_ui node type ${node.type} does not define a controller',
      );
    }
    return create(node);
  }

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node, {
    QuickjsUiComponentController? controller,
  }) {
    if (context.buildContext != null && isQuickjsUiOverlayNode(node.type)) {
      return const SizedBox.shrink();
    }
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return component.build(context, node, controller);
  }
}

final class _QuickjsUiComponentDefinition {
  _QuickjsUiComponentDefinition.builder(QuickjsUiComponentBuilder builder)
    : createController = null,
      _build = ((context, node, _) => builder(context, node));

  _QuickjsUiComponentDefinition._({
    required this.createController,
    required this._build,
  });

  static _QuickjsUiComponentDefinition
  lifecycle<T extends QuickjsUiComponentController>({
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    return _QuickjsUiComponentDefinition._(
      createController: createController,
      build: (context, node, controller) {
        if (controller is! T) {
          throw StateError(
            'quickjs_ui lifecycle controller type mismatch for ${node.type}',
          );
        }
        return build(context, node, controller);
      },
    );
  }

  final QuickjsUiComponentControllerFactory? createController;
  final Widget Function(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  )
  _build;

  bool get hasLifecycle => createController != null;

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  ) {
    if (hasLifecycle && controller == null) {
      throw StateError(
        'quickjs_ui lifecycle component ${node.type} has no controller',
      );
    }
    return _build(context, node, controller);
  }
}
