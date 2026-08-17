// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_decoration.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiLayoutComponentBuilders =
    <String, JsUiComponentBuilder>{
      'Row': _buildRow,
      'Column': _buildColumn,
      'Container': _buildContainer,
      'Stack': _buildStack,
      'Positioned': _buildPositioned,
      'Padding': _buildPadding,
      'Margin': _buildMargin,
      'Align': _buildAlign,
      'Center': _buildCenter,
      'SizedBox': _buildSizedBox,
      'ResponsiveViewport': _buildResponsiveViewport,
      'RepaintBoundary': _buildRepaintBoundary,
      'Expanded': _buildExpanded,
      'Flexible': _buildFlexible,
      'Spacer': _buildSpacer,
      'Wrap': _buildWrap,
      'AspectRatio': _buildAspectRatio,
      'ConstrainedBox': _buildConstrainedBox,
      'SafeArea': _buildSafeArea,
      'AnimatedAlign': _buildAnimatedAlign,
      'AnimatedContainer': _buildAnimatedContainer,
      'AnimatedOpacity': _buildAnimatedOpacity,
      'AnimatedPadding': _buildAnimatedPadding,
      'AnimatedSwitcher': _buildAnimatedSwitcher,
      'Hero': _buildHero,
    };

Widget _buildRow(JsUiRenderContext context, JsUiNode node) {
  return Row(
    mainAxisSize: JsUiProps.mainAxisSize(node.props['mainAxisSize']),
    mainAxisAlignment: JsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: JsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: jsUiGap(context, node),
    children: context.children(node),
  );
}

Widget _buildColumn(JsUiRenderContext context, JsUiNode node) {
  return Column(
    mainAxisSize: JsUiProps.mainAxisSize(node.props['mainAxisSize']),
    mainAxisAlignment: JsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: JsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: jsUiGap(context, node),
    children: context.children(node),
  );
}

Widget _buildContainer(JsUiRenderContext context, JsUiNode node) {
  final resolvedDecoration = context.boxDecoration(node.props);
  final decorations = splitJsUiRoundedBorder(resolvedDecoration);
  final decoration = decorations.background;
  final animationDuration = jsUiAnimationDuration(node);
  final curve = JsUiProps.curve(node.props['animationCurve']);
  final width = JsUiProps.doubleValue(node.props['width']);
  final height = JsUiProps.doubleValue(node.props['height']);
  final padding = context.edgeInsets(node.props['padding']);
  final margin = context.edgeInsets(node.props['margin']);
  final alignment = JsUiProps.alignment(node.props['alignment']);
  final elevation = context.elevation(node.props['elevation']);
  final constraints = _boxConstraints(node.props);
  final color = decoration == null
      ? context.color(node.props['color'] ?? node.props['backgroundColor'])
      : null;
  final nodeChild = context.child(node);
  Widget child = animationDuration == null
      ? Container(
          width: width,
          height: height,
          padding: padding,
          margin: margin,
          alignment: alignment,
          constraints: constraints,
          decoration: decoration,
          foregroundDecoration: decorations.foreground,
          color: color,
          child: nodeChild,
        )
      : AnimatedContainer(
          duration: animationDuration,
          curve: curve,
          width: width,
          height: height,
          padding: padding,
          margin: margin,
          alignment: alignment,
          constraints: constraints,
          decoration: decoration,
          foregroundDecoration: decorations.foreground,
          color: color,
          child: nodeChild,
        );
  if (elevation != null && elevation > 0) {
    child = Material(
      elevation: elevation,
      color: Colors.transparent,
      child: child,
    );
  }
  return withJsUiGestures(context, node, child);
}

Widget _buildStack(JsUiRenderContext context, JsUiNode node) {
  return Stack(
    alignment:
        JsUiProps.alignment(node.props['alignment']) ??
        AlignmentDirectional.topStart,
    fit: JsUiProps.stackFit(node.props['fit']),
    clipBehavior: _stackClipBehavior(node.props['clipBehavior']),
    children: context.children(node),
  );
}

BoxConstraints? _boxConstraints(Map<String, Object?> props) {
  final hasConstraints = <String>[
    'minWidth',
    'maxWidth',
    'minHeight',
    'maxHeight',
  ].any(props.containsKey);
  if (!hasConstraints) return null;
  return BoxConstraints(
    minWidth: JsUiProps.doubleValue(props['minWidth']) ?? 0,
    maxWidth: JsUiProps.doubleValue(props['maxWidth']) ?? double.infinity,
    minHeight: JsUiProps.doubleValue(props['minHeight']) ?? 0,
    maxHeight: JsUiProps.doubleValue(props['maxHeight']) ?? double.infinity,
  );
}

Clip _stackClipBehavior(Object? value) => switch (value) {
  null || 'hardEdge' => Clip.hardEdge,
  'none' => Clip.none,
  'antiAlias' => Clip.antiAlias,
  'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
  _ => throw const FormatException('Unknown quickjs_ui Stack clipBehavior'),
};

Widget _buildPositioned(JsUiRenderContext context, JsUiNode node) {
  return Positioned(
    left: JsUiProps.doubleValue(node.props['left']),
    top: JsUiProps.doubleValue(node.props['top']),
    right: JsUiProps.doubleValue(node.props['right']),
    bottom: JsUiProps.doubleValue(node.props['bottom']),
    width: JsUiProps.doubleValue(node.props['width']),
    height: JsUiProps.doubleValue(node.props['height']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildPadding(JsUiRenderContext context, JsUiNode node) {
  final padding = context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero;
  final animationDuration = jsUiAnimationDuration(node);
  final child = context.child(node) ?? const SizedBox.shrink();
  return withJsUiGestures(
    context,
    node,
    animationDuration == null
        ? Padding(padding: padding, child: child)
        : AnimatedPadding(
            padding: padding,
            duration: animationDuration,
            curve: JsUiProps.curve(node.props['animationCurve']),
            child: child,
          ),
  );
}

Widget _buildMargin(JsUiRenderContext context, JsUiNode node) {
  final margin =
      context.edgeInsets(
        node.props['margin'] ?? node.props['padding'] ?? node.props['value'],
      ) ??
      EdgeInsets.zero;
  return withJsUiGestures(
    context,
    node,
    Padding(padding: margin, child: context.child(node) ?? const SizedBox()),
  );
}

Widget _buildAlign(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    Align(
      alignment:
          JsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
      widthFactor: JsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: JsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildCenter(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    Center(
      widthFactor: JsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: JsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildSizedBox(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    SizedBox(
      width: JsUiProps.doubleValue(node.props['width']),
      height: JsUiProps.doubleValue(node.props['height']),
      child: context.child(node),
    ),
  );
}

Widget _buildResponsiveViewport(JsUiRenderContext context, JsUiNode node) {
  final designWidth = JsUiProps.doubleValue(node.props['designWidth']);
  final designHeight = JsUiProps.doubleValue(node.props['designHeight']);
  if (designWidth == null ||
      designWidth <= 0 ||
      designHeight == null ||
      designHeight <= 0) {
    throw const FormatException(
      'quickjs_ui ResponsiveViewport requires positive designWidth and designHeight',
    );
  }
  final fit = JsUiProps.boxFit(node.props['fit']) ?? BoxFit.cover;
  final alignment =
      JsUiProps.alignment(node.props['alignment']) ?? Alignment.center;
  final child = SizedBox(
    width: designWidth,
    height: designHeight,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
  return LayoutBuilder(
    builder: (context, constraints) {
      if (!constraints.hasBoundedWidth || !constraints.hasBoundedHeight) {
        throw FlutterError(
          'quickjs_ui ResponsiveViewport requires bounded constraints',
        );
      }
      return SizedBox(
        width: constraints.maxWidth,
        height: constraints.maxHeight,
        child: ClipRect(
          child: FittedBox(fit: fit, alignment: alignment, child: child),
        ),
      );
    },
  );
}

Widget _buildRepaintBoundary(JsUiRenderContext context, JsUiNode node) {
  return RepaintBoundary(child: context.child(node) ?? const SizedBox.shrink());
}

Widget _buildExpanded(JsUiRenderContext context, JsUiNode node) {
  return Expanded(
    flex: JsUiProps.intValue(node.props['flex']) ?? 1,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildFlexible(JsUiRenderContext context, JsUiNode node) {
  return Flexible(
    flex: JsUiProps.intValue(node.props['flex']) ?? 1,
    fit: _flexFit(node.props['fit']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildSpacer(JsUiRenderContext context, JsUiNode node) {
  return Spacer(flex: JsUiProps.intValue(node.props['flex']) ?? 1);
}

Widget _buildWrap(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    Wrap(
      direction: node.props['direction'] == null
          ? Axis.horizontal
          : JsUiProps.axis(node.props['direction']),
      alignment: _wrapAlignment(node.props['alignment']),
      runAlignment: _wrapAlignment(node.props['runAlignment']),
      crossAxisAlignment: _wrapCrossAlignment(node.props['crossAxisAlignment']),
      spacing:
          context.spacing(node.props['spacing'], name: 'Wrap spacing') ?? 0,
      runSpacing:
          context.spacing(node.props['runSpacing'], name: 'Wrap runSpacing') ??
          0,
      children: context.children(node),
    ),
  );
}

Widget _buildAspectRatio(JsUiRenderContext context, JsUiNode node) {
  final ratio = JsUiProps.doubleValue(node.props['aspectRatio']) ?? 1;
  return withJsUiGestures(
    context,
    node,
    AspectRatio(
      aspectRatio: ratio,
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildConstrainedBox(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: JsUiProps.doubleValue(node.props['minWidth']) ?? 0,
        maxWidth:
            JsUiProps.doubleValue(node.props['maxWidth']) ?? double.infinity,
        minHeight: JsUiProps.doubleValue(node.props['minHeight']) ?? 0,
        maxHeight:
            JsUiProps.doubleValue(node.props['maxHeight']) ?? double.infinity,
      ),
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildSafeArea(JsUiRenderContext context, JsUiNode node) {
  return SafeArea(
    left: JsUiProps.boolValue(node.props['left']) ?? true,
    top: JsUiProps.boolValue(node.props['top']) ?? true,
    right: JsUiProps.boolValue(node.props['right']) ?? true,
    bottom: JsUiProps.boolValue(node.props['bottom']) ?? true,
    minimum: jsUiEdgeInsets(context.edgeInsets(node.props['minimum'])),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedAlign(JsUiRenderContext context, JsUiNode node) {
  return AnimatedAlign(
    alignment: JsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
    duration: jsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: JsUiProps.curve(node.props['animationCurve']),
    widthFactor: JsUiProps.doubleValue(node.props['widthFactor']),
    heightFactor: JsUiProps.doubleValue(node.props['heightFactor']),
    child: context.child(node),
  );
}

Widget _buildAnimatedContainer(JsUiRenderContext context, JsUiNode node) {
  final decoration = context.boxDecoration(node.props);
  return AnimatedContainer(
    duration: jsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: JsUiProps.curve(node.props['animationCurve']),
    width: JsUiProps.doubleValue(node.props['width']),
    height: JsUiProps.doubleValue(node.props['height']),
    padding: context.edgeInsets(node.props['padding']),
    margin: context.edgeInsets(node.props['margin']),
    alignment: JsUiProps.alignment(node.props['alignment']),
    decoration: decoration,
    color: decoration == null
        ? context.color(node.props['color'] ?? node.props['backgroundColor'])
        : null,
    child: context.child(node),
  );
}

Widget _buildAnimatedOpacity(JsUiRenderContext context, JsUiNode node) {
  return AnimatedOpacity(
    opacity: JsUiProps.opacity(node.props['opacity']),
    duration: jsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: JsUiProps.curve(node.props['animationCurve']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedPadding(JsUiRenderContext context, JsUiNode node) {
  return AnimatedPadding(
    padding: context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero,
    duration: jsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: JsUiProps.curve(node.props['animationCurve']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildHero(JsUiRenderContext context, JsUiNode node) {
  final tag = node.props['tag'];
  if (tag is! String && tag is! num && tag is! bool) {
    throw const FormatException(
      'quickjs_ui Hero tag must be a string, number or boolean',
    );
  }
  return Hero(
    tag: tag as Object,
    transitionOnUserGestures:
        JsUiProps.boolValue(node.props['transitionOnUserGestures']) ?? false,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedSwitcher(JsUiRenderContext context, JsUiNode node) {
  return AnimatedSwitcher(
    duration: jsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    reverseDuration: JsUiProps.duration(
      node.props['reverseDurationMs'],
      name: 'reverse animation duration',
    ),
    switchInCurve: JsUiProps.curve(node.props['switchInCurve']),
    switchOutCurve: JsUiProps.curve(node.props['switchOutCurve']),
    child: context.child(node),
  );
}

FlexFit _flexFit(Object? value) {
  return switch (value) {
    null || 'tight' => FlexFit.tight,
    'loose' => FlexFit.loose,
    _ => throw const FormatException('Unknown quickjs_ui FlexFit'),
  };
}

WrapAlignment _wrapAlignment(Object? value) {
  return switch (value) {
    null || 'start' => WrapAlignment.start,
    'end' => WrapAlignment.end,
    'center' => WrapAlignment.center,
    'spaceBetween' => WrapAlignment.spaceBetween,
    'spaceAround' => WrapAlignment.spaceAround,
    'spaceEvenly' => WrapAlignment.spaceEvenly,
    _ => throw const FormatException('Unknown quickjs_ui WrapAlignment'),
  };
}

WrapCrossAlignment _wrapCrossAlignment(Object? value) {
  return switch (value) {
    null || 'start' => WrapCrossAlignment.start,
    'end' => WrapCrossAlignment.end,
    'center' => WrapCrossAlignment.center,
    _ => throw const FormatException('Unknown quickjs_ui WrapCrossAlignment'),
  };
}
