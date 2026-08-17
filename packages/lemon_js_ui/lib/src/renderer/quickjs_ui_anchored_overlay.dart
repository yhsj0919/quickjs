// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

final class JsUiAnchoredOverlay extends StatefulWidget {
  const JsUiAnchoredOverlay({
    super.key,
    required this.visible,
    required this.anchor,
    required this.overlay,
    required this.placement,
    required this.offset,
    required this.gap,
    required this.screenPadding,
    required this.consumeOutsideTap,
    required this.dismissOnTapOutside,
    required this.useRootOverlay,
    required this.animated,
    required this.matchAnchorWidth,
    required this.onDismissed,
  });

  final bool visible;
  final Widget anchor;
  final Widget overlay;
  final String placement;
  final Offset offset;
  final double gap;
  final EdgeInsets screenPadding;
  final bool consumeOutsideTap;
  final bool dismissOnTapOutside;
  final bool useRootOverlay;
  final bool animated;
  final bool matchAnchorWidth;
  final VoidCallback? onDismissed;

  @override
  State<JsUiAnchoredOverlay> createState() => _JsUiAnchoredOverlayState();
}

final class _JsUiAnchoredOverlayState extends State<JsUiAnchoredOverlay> {
  final OverlayPortalController _controller = OverlayPortalController();
  final Object _tapRegionGroup = Object();

  @override
  void initState() {
    super.initState();
    _scheduleSync();
  }

  @override
  void didUpdateWidget(covariant JsUiAnchoredOverlay oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.visible != widget.visible ||
        oldWidget.placement != widget.placement ||
        oldWidget.offset != widget.offset) {
      _scheduleSync();
    }
  }

  void _scheduleSync() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (widget.visible && !_controller.isShowing) {
        _controller.show();
      } else if (!widget.visible && _controller.isShowing) {
        _controller.hide();
      }
    });
  }

  void _handleOutsideTap(PointerDownEvent event) {
    if (!_controller.isShowing) return;
    _controller.hide();
    widget.onDismissed?.call();
  }

  @override
  Widget build(BuildContext context) {
    return OverlayPortal.overlayChildLayoutBuilder(
      controller: _controller,
      overlayLocation: widget.useRootOverlay
          ? OverlayChildLocation.rootOverlay
          : OverlayChildLocation.nearestOverlay,
      overlayChildBuilder: (context, info) {
        final anchor = MatrixUtils.transformRect(
          info.childPaintTransform,
          Offset.zero & info.childSize,
        );
        final visibleBounds = Offset.zero & info.overlaySize;
        if (!anchor.overlaps(visibleBounds)) {
          return const SizedBox.shrink();
        }
        Widget overlay = TapRegion(
          groupId: _tapRegionGroup,
          child: Material(
            type: MaterialType.transparency,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: widget.matchAnchorWidth
                  ? CrossAxisAlignment.stretch
                  : CrossAxisAlignment.center,
              children: <Widget>[widget.overlay],
            ),
          ),
        );
        if (widget.animated) {
          overlay = TweenAnimationBuilder<double>(
            tween: Tween<double>(begin: 0, end: 1),
            duration: const Duration(milliseconds: 140),
            curve: Curves.easeOutCubic,
            builder: (context, value, child) => Opacity(
              opacity: value,
              child: Transform.scale(
                scale: 0.96 + value * 0.04,
                alignment: Alignment.topCenter,
                child: child,
              ),
            ),
            child: overlay,
          );
        }
        return CustomSingleChildLayout(
          delegate: _AnchoredOverlayLayout(
            anchor: anchor,
            placement: widget.placement,
            offset: widget.offset,
            gap: widget.gap,
            screenPadding: widget.screenPadding,
            matchAnchorWidth: widget.matchAnchorWidth,
          ),
          child: overlay,
        );
      },
      child: TapRegion(
        groupId: _tapRegionGroup,
        consumeOutsideTaps:
            widget.dismissOnTapOutside &&
            widget.consumeOutsideTap &&
            widget.visible,
        onTapOutside: widget.visible && widget.dismissOnTapOutside
            ? _handleOutsideTap
            : null,
        child: widget.anchor,
      ),
    );
  }
}

final class _AnchoredOverlayLayout extends SingleChildLayoutDelegate {
  const _AnchoredOverlayLayout({
    required this.anchor,
    required this.placement,
    required this.offset,
    required this.gap,
    required this.screenPadding,
    required this.matchAnchorWidth,
  });

  final Rect anchor;
  final String placement;
  final Offset offset;
  final double gap;
  final EdgeInsets screenPadding;
  final bool matchAnchorWidth;

  @override
  BoxConstraints getConstraintsForChild(BoxConstraints constraints) {
    final maxWidth = (constraints.maxWidth - screenPadding.horizontal).clamp(
      0.0,
      double.infinity,
    );
    final maxHeight = (constraints.maxHeight - screenPadding.vertical).clamp(
      0.0,
      double.infinity,
    );
    if (matchAnchorWidth) {
      final width = anchor.width.clamp(0.0, maxWidth);
      return BoxConstraints.tightFor(
        width: width,
      ).copyWith(maxHeight: maxHeight);
    }
    return BoxConstraints(maxWidth: maxWidth, maxHeight: maxHeight);
  }

  @override
  Offset getPositionForChild(Size size, Size childSize) {
    final allowed = Rect.fromLTRB(
      screenPadding.left,
      screenPadding.top,
      size.width - screenPadding.right,
      size.height - screenPadding.bottom,
    );
    final resolved = placement == 'auto'
        ? (allowed.bottom - anchor.bottom >= childSize.height + gap
              ? 'bottomStart'
              : 'topStart')
        : placement;
    var position =
        _desiredPosition(resolved, childSize) + _directionalOffset(resolved);
    if (_overflows(resolved, position, childSize, allowed)) {
      final opposite = _opposite(resolved);
      position =
          _desiredPosition(opposite, childSize) + _directionalOffset(opposite);
    }
    return Offset(
      position.dx.clamp(allowed.left, allowed.right - childSize.width),
      position.dy.clamp(allowed.top, allowed.bottom - childSize.height),
    );
  }

  Offset _desiredPosition(String value, Size child) => switch (value) {
    'topStart' => Offset(anchor.left, anchor.top - child.height - gap),
    'top' || 'topCenter' => Offset(
      anchor.center.dx - child.width / 2,
      anchor.top - child.height - gap,
    ),
    'topEnd' => Offset(
      anchor.right - child.width,
      anchor.top - child.height - gap,
    ),
    'bottomEnd' => Offset(anchor.right - child.width, anchor.bottom + gap),
    'bottom' || 'bottomCenter' => Offset(
      anchor.center.dx - child.width / 2,
      anchor.bottom + gap,
    ),
    'left' || 'centerLeft' => Offset(
      anchor.left - child.width - gap,
      anchor.center.dy - child.height / 2,
    ),
    'right' || 'centerRight' => Offset(
      anchor.right + gap,
      anchor.center.dy - child.height / 2,
    ),
    'center' => Offset(
      anchor.center.dx - child.width / 2,
      anchor.center.dy - child.height / 2,
    ),
    'bottomStart' => Offset(anchor.left, anchor.bottom + gap),
    _ => throw FormatException(
      'Unknown quickjs_ui anchored placement "$value"',
    ),
  };

  bool _isAbove(String value) => value.startsWith('top');
  bool _isBelow(String value) => value.startsWith('bottom');
  bool _isLeft(String value) => value == 'left' || value == 'centerLeft';
  bool _isRight(String value) => value == 'right' || value == 'centerRight';

  bool _overflows(String value, Offset position, Size child, Rect allowed) {
    if (_isAbove(value)) return position.dy < allowed.top;
    if (_isBelow(value)) return position.dy + child.height > allowed.bottom;
    if (_isLeft(value)) return position.dx < allowed.left;
    if (_isRight(value)) return position.dx + child.width > allowed.right;
    return false;
  }

  Offset _directionalOffset(String value) => Offset(
    _isLeft(value) ? -offset.dx : offset.dx,
    _isAbove(value) ? -offset.dy : offset.dy,
  );

  String _opposite(String value) => switch (value) {
    'topStart' => 'bottomStart',
    'top' || 'topCenter' => 'bottomCenter',
    'topEnd' => 'bottomEnd',
    'bottomStart' => 'topStart',
    'bottom' || 'bottomCenter' => 'topCenter',
    'bottomEnd' => 'topEnd',
    'left' || 'centerLeft' => 'centerRight',
    'right' || 'centerRight' => 'centerLeft',
    _ => value,
  };

  @override
  bool shouldRelayout(covariant _AnchoredOverlayLayout oldDelegate) {
    return anchor != oldDelegate.anchor ||
        placement != oldDelegate.placement ||
        offset != oldDelegate.offset ||
        gap != oldDelegate.gap ||
        screenPadding != oldDelegate.screenPadding ||
        matchAnchorWidth != oldDelegate.matchAnchorWidth;
  }
}
