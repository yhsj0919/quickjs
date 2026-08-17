import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_basic_components.dart';
import 'quickjs_ui_auto_refresh_components.dart';
import 'quickjs_ui_canvas_component.dart';
import 'quickjs_ui_feedback_components.dart';
import 'quickjs_ui_input_components.dart';
import 'quickjs_ui_layout_components.dart';
import 'quickjs_ui_media_components.dart';
import 'quickjs_ui_navigation_components.dart';
import 'quickjs_ui_particle_flow_component.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_scroll_components.dart';
import 'quickjs_ui_snapshot_component.dart';
import 'quickjs_ui_component_types.dart';

export 'quickjs_ui_component_types.dart';

/// Callback contract for js ui component controller factory.
typedef JsUiComponentControllerFactory =
    JsUiComponentController Function(JsUiNode node);

/// Callback contract for js ui lifecycle component builder.
typedef JsUiLifecycleComponentBuilder<T extends JsUiComponentController> =
    Widget Function(JsUiRenderContext context, JsUiNode node, T controller);

/// Public JSUI js ui component controller API.
base class JsUiComponentController {
  /// Performs the mount operation.
  void mount(JsUiNode node) {}

  /// Performs the update operation.
  void update(JsUiNode previous, JsUiNode next) {}

  /// Performs the show operation.
  void show() {}

  /// Performs the hide operation.
  void hide() {}

  /// Performs the pause operation.
  void pause() {}

  /// Performs the resume operation.
  void resume() {}

  /// Performs the dispose operation.
  void dispose() {}
}

/// Public JSUI js ui component registry API.
final class JsUiComponentRegistry {
  /// Creates a js ui component registry.
  JsUiComponentRegistry();

  /// Creates a js ui component registry.
  factory JsUiComponentRegistry.defaults() {
    final registry = JsUiComponentRegistry();
    registry._registerAll(<String, JsUiComponentBuilder>{
      ...jsUiBasicComponentBuilders,
      ...jsUiAutoRefreshComponentBuilders,
      ...jsUiCanvasComponentBuilders,
      ...jsUiLayoutComponentBuilders,
      ...jsUiMediaComponentBuilders,
      ...jsUiScrollComponentBuilders,
      ...jsUiInputComponentBuilders,
      ...jsUiNavigationComponentBuilders,
      ...jsUiParticleFlowComponentBuilders,
      ...jsUiFeedbackComponentBuilders,
      ...jsUiSnapshotComponentBuilders,
    });
    return registry;
  }

  final Map<String, _JsUiComponentDefinition> _components =
      <String, _JsUiComponentDefinition>{};

  void _registerAll(Map<String, JsUiComponentBuilder> builders) {
    for (final entry in builders.entries) {
      register(entry.key, entry.value);
    }
  }

  /// Returns the current types.
  Iterable<String> get types => _components.keys;

  /// Performs the contains operation.
  bool contains(String type) {
    return _components.containsKey(type);
  }

  /// Performs the register operation.
  void register(String type, JsUiComponentBuilder builder) {
    _components[type] = _JsUiComponentDefinition.builder(builder);
  }

  /// The value value.
  void registerLifecycle<T extends JsUiComponentController>(
    String type, {
    required T Function(JsUiNode node) createController,
    required JsUiLifecycleComponentBuilder<T> build,
  }) {
    _components[type] = _JsUiComponentDefinition.lifecycle(
      createController: createController,
      build: build,
    );
  }

  /// Performs the unregister operation.
  void unregister(String type) {
    _components.remove(type);
  }

  /// Performs the has lifecycle operation.
  bool hasLifecycle(String type) {
    return _components[type]?.hasLifecycle == true;
  }

  /// Performs the create controller operation.
  JsUiComponentController createController(JsUiNode node) {
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

  /// Performs the build operation.
  Widget build(
    JsUiRenderContext context,
    JsUiNode node, {
    JsUiComponentController? controller,
  }) {
    if (isJsUiRouteOverlayType(node.type)) {
      return const SizedBox.shrink();
    }
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return component.build(context, node, controller);
  }
}

final class _JsUiComponentDefinition {
  _JsUiComponentDefinition.builder(JsUiComponentBuilder builder)
    : createController = null,
      _build = ((context, node, _) => builder(context, node));

  _JsUiComponentDefinition._({
    required this.createController,
    required this._build,
  });

  static _JsUiComponentDefinition lifecycle<T extends JsUiComponentController>({
    required T Function(JsUiNode node) createController,
    required JsUiLifecycleComponentBuilder<T> build,
  }) {
    return _JsUiComponentDefinition._(
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

  final JsUiComponentControllerFactory? createController;
  final Widget Function(
    JsUiRenderContext context,
    JsUiNode node,
    JsUiComponentController? controller,
  )
  _build;

  bool get hasLifecycle => createController != null;

  Widget build(
    JsUiRenderContext context,
    JsUiNode node,
    JsUiComponentController? controller,
  ) {
    if (hasLifecycle && controller == null) {
      throw StateError(
        'quickjs_ui lifecycle component ${node.type} has no controller',
      );
    }
    return _build(context, node, controller);
  }
}
