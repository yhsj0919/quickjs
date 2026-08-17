import 'dart:async';

import 'package:flutter/rendering.dart';
import 'package:flutter/widgets.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_types.dart';
import 'quickjs_ui_render_context.dart';
import 'quickjs_ui_snapshot.dart';

/// The js ui snapshot component builders value.
final JsUiComponentBuilderMap jsUiSnapshotComponentBuilders =
    <String, JsUiComponentBuilder>{'SnapshotBoundary': _buildSnapshotBoundary};

Widget _buildSnapshotBoundary(JsUiRenderContext context, JsUiNode node) {
  final boundaryId = JsUiProps.string(node.props['snapshotKey']) ?? node.key;
  if (boundaryId == null || boundaryId.isEmpty) {
    throw const FormatException(
      'quickjs_ui SnapshotBoundary requires key or snapshotKey',
    );
  }
  final onCaptured = JsUiProps.event(node.props['onCaptured']);
  final onCaptureError = JsUiProps.event(node.props['onCaptureError']);
  return JsUiSnapshotBoundary(
    boundaryId: boundaryId,
    captureToken: node.props['captureToken'],
    pixelRatio:
        JsUiProps.doubleValue(node.props['pixelRatio'])?.clamp(0.25, 4) ?? 1,
    registry: context.snapshotRegistry,
    onCaptured: onCaptured == null
        ? null
        : (snapshot) => context.dispatch(
            onCaptured,
            payload: snapshot.toPayload(),
            defaultCoalesceKey: 'SnapshotBoundary:$boundaryId:onCaptured',
          ),
    onCaptureError: onCaptureError == null
        ? null
        : (error) => context.dispatch(
            onCaptureError,
            payload: <String, Object?>{'message': '$error'},
            defaultCoalesceKey: 'SnapshotBoundary:$boundaryId:onCaptureError',
          ),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

/// Public JSUI js ui snapshot boundary API.
final class JsUiSnapshotBoundary extends StatefulWidget {
  /// Creates a js ui snapshot boundary.
  const JsUiSnapshotBoundary({
    super.key,
    required this.boundaryId,
    required this.captureToken,
    required this.pixelRatio,
    required this.registry,
    this.onCaptured,
    this.onCaptureError,
    required this.child,
  });

  /// The boundary id value.
  final String boundaryId;

  /// The capture token value.
  final Object? captureToken;

  /// The pixel ratio value.
  final double pixelRatio;

  /// The registry value.
  final JsUiSnapshotRegistry registry;

  /// The on captured value.
  final ValueChanged<JsUiSnapshot>? onCaptured;

  /// The on capture error value.
  final ValueChanged<Object>? onCaptureError;

  /// The child value.
  final Widget child;

  @override
  State<JsUiSnapshotBoundary> createState() => _JsUiSnapshotBoundaryState();
}

final class _JsUiSnapshotBoundaryState extends State<JsUiSnapshotBoundary> {
  final GlobalKey _boundaryKey = GlobalKey();
  final Object _claimOwner = Object();
  int _captureGeneration = 0;
  Object? _claimedToken;

  @override
  void initState() {
    super.initState();
    _requestCapture();
  }

  @override
  void didUpdateWidget(covariant JsUiSnapshotBoundary oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.captureToken != widget.captureToken &&
        widget.captureToken != null) {
      _requestCapture();
    }
  }

  void _requestCapture() {
    final token = widget.captureToken;
    widget.registry.cancelCapture(
      boundaryId: widget.boundaryId,
      owner: _claimOwner,
    );
    _claimedToken = null;
    if (token == null ||
        !widget.registry.claimCapture(
          boundaryId: widget.boundaryId,
          token: token,
          owner: _claimOwner,
        )) {
      return;
    }
    _claimedToken = token;
    _scheduleCapture();
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
      var debugNeedsPaint = false;
      assert(() {
        debugNeedsPaint = renderObject.debugNeedsPaint;
        return true;
      }());
      if (debugNeedsPaint) {
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
      widget.registry.completeCapture(
        boundaryId: widget.boundaryId,
        token: _claimedToken,
        owner: _claimOwner,
      );
      _claimedToken = null;
      widget.onCaptured?.call(snapshot);
    } catch (error) {
      if (!mounted || generation != _captureGeneration) return;
      widget.registry.cancelCapture(
        boundaryId: widget.boundaryId,
        owner: _claimOwner,
      );
      _claimedToken = null;
      widget.onCaptureError?.call(error);
    }
  }

  @override
  void dispose() {
    _captureGeneration += 1;
    widget.registry.cancelCapture(
      boundaryId: widget.boundaryId,
      owner: _claimOwner,
    );
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return RepaintBoundary(key: _boundaryKey, child: widget.child);
  }
}
