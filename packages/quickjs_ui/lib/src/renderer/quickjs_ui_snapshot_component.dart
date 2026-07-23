import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_types.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_snapshot.dart';

final QuickjsUiComponentBuilderMap quickjsUiSnapshotComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'SnapshotBoundary': _buildSnapshotBoundary,
    };

Widget _buildSnapshotBoundary(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final boundaryId =
      QuickjsUiProps.string(node.props['snapshotKey']) ?? node.key;
  if (boundaryId == null || boundaryId.isEmpty) {
    throw const FormatException(
      'quickjs_ui SnapshotBoundary requires key or snapshotKey',
    );
  }
  final onCaptured = QuickjsUiProps.event(node.props['onCaptured']);
  final onCaptureError = QuickjsUiProps.event(node.props['onCaptureError']);
  return QuickjsUiSnapshotBoundary(
    boundaryId: boundaryId,
    captureToken: node.props['captureToken'],
    pixelRatio:
        QuickjsUiProps.doubleValue(node.props['pixelRatio'])?.clamp(0.25, 4) ??
        1,
    registry: context.snapshotRegistry,
    onCaptured: onCaptured == null
        ? null
        : (snapshot) => context.dispatchEvent(
            onCaptured,
            payload: snapshot.toPayload(),
            defaultCoalesceKey: 'SnapshotBoundary:$boundaryId:onCaptured',
          ),
    onCaptureError: onCaptureError == null
        ? null
        : (error) => context.dispatchEvent(
            onCaptureError,
            payload: <String, Object?>{'message': '$error'},
            defaultCoalesceKey: 'SnapshotBoundary:$boundaryId:onCaptureError',
          ),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

final class QuickjsUiSnapshotBoundary extends StatefulWidget {
  const QuickjsUiSnapshotBoundary({
    super.key,
    required this.boundaryId,
    required this.captureToken,
    required this.pixelRatio,
    required this.registry,
    this.onCaptured,
    this.onCaptureError,
    required this.child,
  });

  final String boundaryId;
  final Object? captureToken;
  final double pixelRatio;
  final QuickjsUiSnapshotRegistry registry;
  final ValueChanged<QuickjsUiSnapshot>? onCaptured;
  final ValueChanged<Object>? onCaptureError;
  final Widget child;

  @override
  State<QuickjsUiSnapshotBoundary> createState() =>
      _QuickjsUiSnapshotBoundaryState();
}

final class _QuickjsUiSnapshotBoundaryState
    extends State<QuickjsUiSnapshotBoundary> {
  final GlobalKey _boundaryKey = GlobalKey();
  int _captureGeneration = 0;

  @override
  void initState() {
    super.initState();
    if (widget.captureToken != null) _scheduleCapture();
  }

  @override
  void didUpdateWidget(covariant QuickjsUiSnapshotBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureToken != widget.captureToken &&
        widget.captureToken != null) {
      _scheduleCapture();
    }
  }

  void _scheduleCapture() {
    final generation = ++_captureGeneration;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || generation != _captureGeneration) return;
      unawaited(_capture(generation));
    });
  }

  Future<void> _capture(int generation) async {
    try {
      final renderObject = _boundaryKey.currentContext?.findRenderObject();
      if (renderObject is! RenderRepaintBoundary) {
        throw StateError('SnapshotBoundary is not attached');
      }
      if (renderObject.debugNeedsPaint) {
        _scheduleCapture();
        return;
      }
      final image = await renderObject.toImage(pixelRatio: widget.pixelRatio);
      if (!mounted || generation != _captureGeneration) {
        image.dispose();
        return;
      }
      final snapshot = widget.registry.register(
        boundaryId: widget.boundaryId,
        image: image,
        pixelRatio: widget.pixelRatio,
      );
      widget.onCaptured?.call(snapshot);
    } catch (error) {
      if (!mounted || generation != _captureGeneration) return;
      widget.onCaptureError?.call(error);
    }
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
