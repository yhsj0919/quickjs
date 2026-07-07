import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

Widget withQuickjsUiGestures(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Widget child,
) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  final onLongPress = QuickjsUiProps.event(node.props['onLongPress']);
  final onDoubleTap = QuickjsUiProps.event(node.props['onDoubleTap']);
  final onDragStart = QuickjsUiProps.event(node.props['onDragStart']);
  final onDragUpdate = QuickjsUiProps.event(node.props['onDragUpdate']);
  final onDragEnd = QuickjsUiProps.event(node.props['onDragEnd']);
  final onSwipe = QuickjsUiProps.event(node.props['onSwipe']);
  final hasPan =
      onDragStart != null ||
      onDragUpdate != null ||
      onDragEnd != null ||
      onSwipe != null;
  if (onTap == null && onLongPress == null && onDoubleTap == null && !hasPan) {
    return child;
  }
  Offset dragTotal = Offset.zero;
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap == null
        ? null
        : () => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onTap'),
          ),
    onLongPress: onLongPress == null
        ? null
        : () => context.dispatchEvent(
            onLongPress,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onLongPress'),
          ),
    onDoubleTap: onDoubleTap == null
        ? null
        : () => context.dispatchEvent(
            onDoubleTap,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onDoubleTap'),
          ),
    onPanStart: !hasPan
        ? null
        : (details) {
            dragTotal = Offset.zero;
            if (onDragStart != null) {
              context.dispatchEvent(
                onDragStart,
                defaultCoalesceKey: quickjsUiEventKey(node, 'onDragStart'),
                payload: <String, Object?>{
                  'x': details.localPosition.dx,
                  'y': details.localPosition.dy,
                  'globalX': details.globalPosition.dx,
                  'globalY': details.globalPosition.dy,
                },
              );
            }
          },
    onPanUpdate: !hasPan
        ? null
        : (details) {
            dragTotal += details.delta;
            if (onDragUpdate != null) {
              context.dispatchEvent(
                onDragUpdate,
                defaultCoalesceKey: quickjsUiEventKey(node, 'onDragUpdate'),
                kind: QuickjsUiEventKind.sample,
                payload: <String, Object?>{
                  'deltaX': details.delta.dx,
                  'deltaY': details.delta.dy,
                  'totalDeltaX': dragTotal.dx,
                  'totalDeltaY': dragTotal.dy,
                  'x': details.localPosition.dx,
                  'y': details.localPosition.dy,
                  'globalX': details.globalPosition.dx,
                  'globalY': details.globalPosition.dy,
                },
              );
            }
          },
    onPanEnd: onDragEnd == null && onSwipe == null
        ? null
        : (details) {
            if (onDragEnd != null) {
              context.dispatchEvent(
                onDragEnd,
                defaultCoalesceKey: quickjsUiEventKey(node, 'onDragEnd'),
                payload: <String, Object?>{
                  'velocityX': details.velocity.pixelsPerSecond.dx,
                  'velocityY': details.velocity.pixelsPerSecond.dy,
                  'totalDeltaX': dragTotal.dx,
                  'totalDeltaY': dragTotal.dy,
                },
              );
            }
            if (onSwipe != null) {
              final direction = _swipeDirection(
                dragTotal,
                details.velocity.pixelsPerSecond,
              );
              if (direction != null) {
                context.dispatchEvent(
                  onSwipe,
                  defaultCoalesceKey: quickjsUiEventKey(node, 'onSwipe'),
                  payload: <String, Object?>{
                    'direction': direction,
                    'velocityX': details.velocity.pixelsPerSecond.dx,
                    'velocityY': details.velocity.pixelsPerSecond.dy,
                    'totalDeltaX': dragTotal.dx,
                    'totalDeltaY': dragTotal.dy,
                  },
                );
              }
            }
          },
    child: child,
  );
}

String? _swipeDirection(Offset delta, Offset velocity) {
  const minDistance = 40.0;
  const minVelocity = 300.0;
  final primaryDelta = delta.dx.abs() >= delta.dy.abs() ? delta.dx : delta.dy;
  final primaryVelocity = delta.dx.abs() >= delta.dy.abs()
      ? velocity.dx
      : velocity.dy;
  if (primaryDelta.abs() < minDistance && primaryVelocity.abs() < minVelocity) {
    return null;
  }
  if (delta.dx.abs() >= delta.dy.abs()) {
    return primaryDelta >= 0 ? 'right' : 'left';
  }
  return primaryDelta >= 0 ? 'down' : 'up';
}

String quickjsUiEventKey(QuickjsUiNode node, String prop) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return '${node.type}:$key:$prop';
  }
  return '${node.type}:${identityHashCode(node)}:$prop';
}
