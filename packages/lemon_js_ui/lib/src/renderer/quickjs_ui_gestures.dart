// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

Widget withJsUiInput(JsUiRenderContext context, JsUiNode node, Widget child) {
  final enabled = JsUiProps.boolValue(node.props['enabled']) ?? true;
  final onMouseEnter = JsUiProps.event(node.props['onMouseEnter']);
  final onMouseExit = JsUiProps.event(node.props['onMouseExit']);
  final onMouseHover = JsUiProps.event(node.props['onMouseHover']);
  final onMouseScroll = JsUiProps.event(node.props['onMouseScroll']);
  final onPointerDown = JsUiProps.event(node.props['onPointerDown']);
  final onPointerMove = JsUiProps.event(node.props['onPointerMove']);
  final onPointerUp = JsUiProps.event(node.props['onPointerUp']);
  final onPointerCancel = JsUiProps.event(node.props['onPointerCancel']);
  final behavior = _hitTestBehavior(node.props['hitTestBehavior']);
  Widget result = child;
  if (enabled &&
      (onPointerDown != null ||
          onPointerMove != null ||
          onPointerUp != null ||
          onPointerCancel != null ||
          onMouseScroll != null)) {
    result = Listener(
      behavior: behavior,
      onPointerDown: onPointerDown == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onPointerDown,
              details,
              'onPointerDown',
            ),
      onPointerMove: onPointerMove == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onPointerMove,
              details,
              'onPointerMove',
              sample: true,
            ),
      onPointerUp: onPointerUp == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onPointerUp,
              details,
              'onPointerUp',
            ),
      onPointerCancel: onPointerCancel == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onPointerCancel,
              details,
              'onPointerCancel',
            ),
      onPointerSignal: onMouseScroll == null
          ? null
          : (details) {
              if (details is PointerScrollEvent) {
                GestureBinding.instance.pointerSignalResolver.register(
                  details,
                  (resolvedEvent) {
                    final scrollEvent = resolvedEvent as PointerScrollEvent;
                    _dispatchPointer(
                      context,
                      node,
                      onMouseScroll,
                      scrollEvent,
                      'onMouseScroll',
                      scrollDelta: scrollEvent.scrollDelta,
                    );
                  },
                );
              }
            },
      child: result,
    );
  }
  final cursor = _mouseCursor(
    node.props['mouseCursor'] ?? node.props['cursor'],
  );
  if (enabled &&
      (onMouseEnter != null ||
          onMouseExit != null ||
          onMouseHover != null ||
          cursor != MouseCursor.defer)) {
    result = MouseRegion(
      cursor: cursor,
      onEnter: onMouseEnter == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onMouseEnter,
              details,
              'onMouseEnter',
            ),
      onExit: onMouseExit == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onMouseExit,
              details,
              'onMouseExit',
            ),
      onHover: onMouseHover == null
          ? null
          : (details) => _dispatchPointer(
              context,
              node,
              onMouseHover,
              details,
              'onMouseHover',
              sample: true,
            ),
      child: result,
    );
  }
  result = _withKeyboardAndFocus(context, node, result, enabled: enabled);
  if (JsUiProps.boolValue(node.props['absorbPointer']) ?? false) {
    result = AbsorbPointer(child: result);
  }
  if (JsUiProps.boolValue(node.props['ignorePointer']) ?? false) {
    result = IgnorePointer(child: result);
  }
  return result;
}

Widget withJsUiGestures(
  JsUiRenderContext context,
  JsUiNode node,
  Widget child,
) {
  if (!(JsUiProps.boolValue(node.props['enabled']) ?? true)) {
    return child;
  }
  final onTap = JsUiProps.event(node.props['onTap']);
  final onLongPress = JsUiProps.event(node.props['onLongPress']);
  final onDoubleTap = JsUiProps.event(node.props['onDoubleTap']);
  final onDragStart = JsUiProps.event(node.props['onDragStart']);
  final onDragUpdate = JsUiProps.event(node.props['onDragUpdate']);
  final onDragEnd = JsUiProps.event(node.props['onDragEnd']);
  final onSwipe = JsUiProps.event(node.props['onSwipe']);
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
    behavior: _hitTestBehavior(node.props['hitTestBehavior']),
    onTap: onTap == null
        ? null
        : () => context.dispatch(
            onTap,
            defaultCoalesceKey: jsUiEventKey(node, 'onTap'),
          ),
    onLongPress: onLongPress == null
        ? null
        : () => context.dispatch(
            onLongPress,
            defaultCoalesceKey: jsUiEventKey(node, 'onLongPress'),
          ),
    onDoubleTap: onDoubleTap == null
        ? null
        : () => context.dispatch(
            onDoubleTap,
            defaultCoalesceKey: jsUiEventKey(node, 'onDoubleTap'),
          ),
    onPanStart: !hasPan
        ? null
        : (details) {
            dragTotal = Offset.zero;
            if (onDragStart != null) {
              context.dispatch(
                onDragStart,
                defaultCoalesceKey: jsUiEventKey(node, 'onDragStart'),
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
              context.dispatch(
                onDragUpdate,
                defaultCoalesceKey: jsUiEventKey(node, 'onDragUpdate'),
                kind: JsUiEventKind.sample,
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
              context.dispatch(
                onDragEnd,
                defaultCoalesceKey: jsUiEventKey(node, 'onDragEnd'),
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
                context.dispatch(
                  onSwipe,
                  defaultCoalesceKey: jsUiEventKey(node, 'onSwipe'),
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

void _dispatchPointer(
  JsUiRenderContext context,
  JsUiNode node,
  Map<String, Object?> event,
  PointerEvent details,
  String prop, {
  bool sample = false,
  Offset? scrollDelta,
}) {
  context.dispatch(
    event,
    defaultCoalesceKey: jsUiEventKey(node, prop),
    kind: sample ? JsUiEventKind.sample : JsUiEventKind.command,
    payload: <String, Object?>{
      'pointer': details.pointer,
      'kind': details.kind.name,
      'x': details.localPosition.dx,
      'y': details.localPosition.dy,
      'localX': details.localPosition.dx,
      'localY': details.localPosition.dy,
      'globalX': details.position.dx,
      'globalY': details.position.dy,
      'deltaX': details.delta.dx,
      'deltaY': details.delta.dy,
      'buttons': details.buttons,
      'pressure': details.pressure,
      ..._modifierPayload(),
      if (scrollDelta != null) 'scrollDeltaX': scrollDelta.dx,
      if (scrollDelta != null) 'scrollDeltaY': scrollDelta.dy,
      'timestampMs': DateTime.now().millisecondsSinceEpoch,
    },
  );
}

Widget _withKeyboardAndFocus(
  JsUiRenderContext context,
  JsUiNode node,
  Widget child, {
  required bool enabled,
}) {
  final managesOwnFocus =
      node.type == 'TextField' || node.type == 'TextFormField';
  final onFocus = managesOwnFocus
      ? null
      : JsUiProps.event(node.props['onFocus']);
  final onBlur = managesOwnFocus ? null : JsUiProps.event(node.props['onBlur']);
  final onKeyDown = JsUiProps.event(node.props['onKeyDown']);
  final onKeyUp = JsUiProps.event(node.props['onKeyUp']);
  final autofocus = managesOwnFocus
      ? false
      : JsUiProps.boolValue(node.props['autofocus']) ?? false;
  final canRequestFocus =
      JsUiProps.boolValue(node.props['canRequestFocus']) ?? true;
  if (onFocus == null &&
      onBlur == null &&
      onKeyDown == null &&
      onKeyUp == null &&
      !autofocus &&
      node.props['canRequestFocus'] == null) {
    return child;
  }
  return Focus(
    autofocus: autofocus && enabled,
    canRequestFocus: canRequestFocus && enabled,
    onFocusChange: (focused) {
      final event = focused ? onFocus : onBlur;
      if (enabled && event != null) {
        context.dispatch(
          event,
          defaultCoalesceKey: jsUiEventKey(
            node,
            focused ? 'onFocus' : 'onBlur',
          ),
          payload: <String, Object?>{'focused': focused},
        );
      }
    },
    onKeyEvent: (focusNode, event) {
      final descriptor = switch (event) {
        KeyDownEvent() => onKeyDown,
        KeyUpEvent() => onKeyUp,
        _ => null,
      };
      if (enabled && descriptor != null) {
        context.dispatch(
          descriptor,
          defaultCoalesceKey: jsUiEventKey(
            node,
            event is KeyDownEvent ? 'onKeyDown' : 'onKeyUp',
          ),
          payload: <String, Object?>{
            'key': event.logicalKey.keyLabel,
            'keyId': event.logicalKey.keyId,
            'character': event.character,
            'repeat': event is KeyRepeatEvent,
            ..._modifierPayload(),
          },
        );
      }
      return KeyEventResult.ignored;
    },
    child: child,
  );
}

Map<String, Object?> _modifierPayload() {
  final keyboard = HardwareKeyboard.instance;
  return <String, Object?>{
    'controlKey': keyboard.isControlPressed,
    'shiftKey': keyboard.isShiftPressed,
    'altKey': keyboard.isAltPressed,
    'metaKey': keyboard.isMetaPressed,
  };
}

HitTestBehavior _hitTestBehavior(Object? value) => switch (value) {
  null || 'opaque' => HitTestBehavior.opaque,
  'deferToChild' => HitTestBehavior.deferToChild,
  'translucent' => HitTestBehavior.translucent,
  _ => throw const FormatException('Unknown quickjs_ui hitTestBehavior'),
};

MouseCursor _mouseCursor(Object? value) => switch (value) {
  'click' || 'pointer' => SystemMouseCursors.click,
  'text' => SystemMouseCursors.text,
  'basic' || 'default' => SystemMouseCursors.basic,
  'move' => SystemMouseCursors.move,
  'grab' => SystemMouseCursors.grab,
  'grabbing' => SystemMouseCursors.grabbing,
  'forbidden' || 'notAllowed' => SystemMouseCursors.forbidden,
  'wait' => SystemMouseCursors.wait,
  'progress' => SystemMouseCursors.progress,
  'resizeLeftRight' => SystemMouseCursors.resizeLeftRight,
  'resizeUpDown' => SystemMouseCursors.resizeUpDown,
  'resizeUpLeftDownRight' => SystemMouseCursors.resizeUpLeftDownRight,
  'resizeUpRightDownLeft' => SystemMouseCursors.resizeUpRightDownLeft,
  'resizeColumn' => SystemMouseCursors.resizeColumn,
  'resizeRow' => SystemMouseCursors.resizeRow,
  _ => MouseCursor.defer,
};

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

String jsUiEventKey(JsUiNode node, String prop) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return '${node.type}:$key:$prop';
  }
  return '${node.type}:${identityHashCode(node)}:$prop';
}
