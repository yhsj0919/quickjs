import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_anchored_overlay.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiFeedbackComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'Overlay': _buildRouteOverlayPlaceholder,
      'AnchoredOverlay': _buildAnchoredOverlay,
      'SnackBar': _buildRouteOverlayPlaceholder,
      'AlertDialog': _buildRouteOverlayPlaceholder,
      'BottomSheet': _buildRouteOverlayPlaceholder,
    };

Widget _buildAnchoredOverlay(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
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
          QuickjsUiProps.doubleValue(rawOffset['x']) ?? 0,
          QuickjsUiProps.doubleValue(rawOffset['y']) ?? 0,
        )
      : Offset.zero;
  final onDismissed = QuickjsUiProps.event(node.props['onDismissed']);
  return QuickjsUiAnchoredOverlay(
    visible: QuickjsUiProps.boolValue(node.props['visible']) ?? false,
    anchor: anchor,
    overlay: overlay,
    placement: QuickjsUiProps.string(node.props['placement']) ?? 'auto',
    offset: offset,
    gap: QuickjsUiProps.doubleValue(node.props['gap']) ?? 0,
    screenPadding: node.props['screenPadding'] == null
        ? const EdgeInsets.all(8)
        : quickjsUiEdgeInsets(context.edgeInsets(node.props['screenPadding'])),
    consumeOutsideTap:
        QuickjsUiProps.boolValue(node.props['consumeOutsideTap']) ?? false,
    dismissOnTapOutside:
        QuickjsUiProps.boolValue(node.props['dismissOnTapOutside']) ?? true,
    useRootOverlay:
        QuickjsUiProps.boolValue(node.props['useRootOverlay']) ?? true,
    animated: QuickjsUiProps.boolValue(node.props['animated']) ?? true,
    matchAnchorWidth:
        QuickjsUiProps.boolValue(node.props['matchAnchorWidth']) ?? false,
    onDismissed: onDismissed == null
        ? null
        : () => context.dispatchEvent(onDismissed),
  );
}

Widget _buildRouteOverlayPlaceholder(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) => const SizedBox.shrink();
