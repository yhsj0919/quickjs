// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_anchored_overlay.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiFeedbackComponentBuilders =
    <String, JsUiComponentBuilder>{
      'Overlay': _buildRouteOverlayPlaceholder,
      'AnchoredOverlay': _buildAnchoredOverlay,
      'SnackBar': _buildRouteOverlayPlaceholder,
      'AlertDialog': _buildRouteOverlayPlaceholder,
      'BottomSheet': _buildRouteOverlayPlaceholder,
    };

Widget _buildAnchoredOverlay(JsUiRenderContext context, JsUiNode node) {
  final anchor = context.slot(node, 'anchor') ?? context.child(node);
  final overlay =
      context.slot(node, 'overlay') ?? context.slot(node, 'content');
  if (anchor == null || overlay == null) {
    throw const FormatException(
      'quickjs_ui AnchoredOverlay requires anchor and overlay nodes',
    );
  }
  final rawOffset = node.props['offset'];
  final offset = rawOffset is Map
      ? Offset(
          JsUiProps.doubleValue(rawOffset['x']) ?? 0,
          JsUiProps.doubleValue(rawOffset['y']) ?? 0,
        )
      : Offset.zero;
  final onDismissed = JsUiProps.event(node.props['onDismissed']);
  return JsUiAnchoredOverlay(
    visible: JsUiProps.boolValue(node.props['visible']) ?? false,
    anchor: anchor,
    overlay: overlay,
    placement: JsUiProps.string(node.props['placement']) ?? 'auto',
    offset: offset,
    gap: JsUiProps.doubleValue(node.props['gap']) ?? 0,
    screenPadding: node.props['screenPadding'] == null
        ? const EdgeInsets.all(8)
        : jsUiEdgeInsets(context.edgeInsets(node.props['screenPadding'])),
    consumeOutsideTap:
        JsUiProps.boolValue(node.props['consumeOutsideTap']) ?? false,
    dismissOnTapOutside:
        JsUiProps.boolValue(node.props['dismissOnTapOutside']) ?? true,
    useRootOverlay: JsUiProps.boolValue(node.props['useRootOverlay']) ?? true,
    animated: JsUiProps.boolValue(node.props['animated']) ?? true,
    matchAnchorWidth:
        JsUiProps.boolValue(node.props['matchAnchorWidth']) ?? false,
    onDismissed: onDismissed == null
        ? null
        : () => context.dispatch(onDismissed),
  );
}

Widget _buildRouteOverlayPlaceholder(
  JsUiRenderContext context,
  JsUiNode node,
) => const SizedBox.shrink();
