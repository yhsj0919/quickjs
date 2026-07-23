import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiLayoutComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
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

Widget _buildRow(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Row(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: quickjsUiGap(context, node),
    children: context.children(node),
  );
}

Widget _buildColumn(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Column(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
    spacing: quickjsUiGap(context, node),
    children: context.children(node),
  );
}

Widget _buildContainer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final decoration = context.boxDecoration(node.props);
  final animationDuration = quickjsUiAnimationDuration(node);
  final curve = QuickjsUiProps.curve(node.props['animationCurve']);
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final padding = context.edgeInsets(node.props['padding']);
  final margin = context.edgeInsets(node.props['margin']);
  final alignment = QuickjsUiProps.alignment(node.props['alignment']);
  final elevation = context.elevation(node.props['elevation']);
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
          decoration: decoration,
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
          decoration: decoration,
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
  return withQuickjsUiGestures(context, node, child);
}

Widget _buildStack(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Stack(
    alignment:
        QuickjsUiProps.alignment(node.props['alignment']) ??
        AlignmentDirectional.topStart,
    fit: QuickjsUiProps.stackFit(node.props['fit']),
    children: context.children(node),
  );
}

Widget _buildPositioned(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Positioned(
    left: QuickjsUiProps.doubleValue(node.props['left']),
    top: QuickjsUiProps.doubleValue(node.props['top']),
    right: QuickjsUiProps.doubleValue(node.props['right']),
    bottom: QuickjsUiProps.doubleValue(node.props['bottom']),
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildPadding(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final padding = context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero;
  final animationDuration = quickjsUiAnimationDuration(node);
  final child = context.child(node) ?? const SizedBox.shrink();
  return withQuickjsUiGestures(
    context,
    node,
    animationDuration == null
        ? Padding(padding: padding, child: child)
        : AnimatedPadding(
            padding: padding,
            duration: animationDuration,
            curve: QuickjsUiProps.curve(node.props['animationCurve']),
            child: child,
          ),
  );
}

Widget _buildMargin(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final margin =
      context.edgeInsets(
        node.props['margin'] ?? node.props['padding'] ?? node.props['value'],
      ) ??
      EdgeInsets.zero;
  return withQuickjsUiGestures(
    context,
    node,
    Padding(padding: margin, child: context.child(node) ?? const SizedBox()),
  );
}

Widget _buildAlign(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return withQuickjsUiGestures(
    context,
    node,
    Align(
      alignment:
          QuickjsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
      widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildCenter(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return withQuickjsUiGestures(
    context,
    node,
    Center(
      widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
      heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
      child: context.child(node),
    ),
  );
}

Widget _buildSizedBox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return withQuickjsUiGestures(
    context,
    node,
    SizedBox(
      width: QuickjsUiProps.doubleValue(node.props['width']),
      height: QuickjsUiProps.doubleValue(node.props['height']),
      child: context.child(node),
    ),
  );
}

Widget _buildExpanded(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Expanded(
    flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildFlexible(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Flexible(
    flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1,
    fit: _flexFit(node.props['fit']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildSpacer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Spacer(flex: QuickjsUiProps.intValue(node.props['flex']) ?? 1);
}

Widget _buildWrap(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return withQuickjsUiGestures(
    context,
    node,
    Wrap(
      direction: QuickjsUiProps.axis(node.props['direction']),
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

Widget _buildAspectRatio(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final ratio = QuickjsUiProps.doubleValue(node.props['aspectRatio']) ?? 1;
  return withQuickjsUiGestures(
    context,
    node,
    AspectRatio(
      aspectRatio: ratio,
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildConstrainedBox(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return withQuickjsUiGestures(
    context,
    node,
    ConstrainedBox(
      constraints: BoxConstraints(
        minWidth: QuickjsUiProps.doubleValue(node.props['minWidth']) ?? 0,
        maxWidth:
            QuickjsUiProps.doubleValue(node.props['maxWidth']) ??
            double.infinity,
        minHeight: QuickjsUiProps.doubleValue(node.props['minHeight']) ?? 0,
        maxHeight:
            QuickjsUiProps.doubleValue(node.props['maxHeight']) ??
            double.infinity,
      ),
      child: context.child(node) ?? const SizedBox.shrink(),
    ),
  );
}

Widget _buildSafeArea(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return SafeArea(
    left: QuickjsUiProps.boolValue(node.props['left']) ?? true,
    top: QuickjsUiProps.boolValue(node.props['top']) ?? true,
    right: QuickjsUiProps.boolValue(node.props['right']) ?? true,
    bottom: QuickjsUiProps.boolValue(node.props['bottom']) ?? true,
    minimum: quickjsUiEdgeInsets(context.edgeInsets(node.props['minimum'])),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedAlign(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return AnimatedAlign(
    alignment:
        QuickjsUiProps.alignment(node.props['alignment']) ?? Alignment.center,
    duration:
        quickjsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: QuickjsUiProps.curve(node.props['animationCurve']),
    widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
    heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
    child: context.child(node),
  );
}

Widget _buildAnimatedContainer(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final decoration = context.boxDecoration(node.props);
  return AnimatedContainer(
    duration:
        quickjsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: QuickjsUiProps.curve(node.props['animationCurve']),
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    padding: context.edgeInsets(node.props['padding']),
    margin: context.edgeInsets(node.props['margin']),
    alignment: QuickjsUiProps.alignment(node.props['alignment']),
    decoration: decoration,
    color: decoration == null
        ? context.color(node.props['color'] ?? node.props['backgroundColor'])
        : null,
    child: context.child(node),
  );
}

Widget _buildAnimatedOpacity(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return AnimatedOpacity(
    opacity: QuickjsUiProps.opacity(node.props['opacity']),
    duration:
        quickjsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: QuickjsUiProps.curve(node.props['animationCurve']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedPadding(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return AnimatedPadding(
    padding: context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero,
    duration:
        quickjsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    curve: QuickjsUiProps.curve(node.props['animationCurve']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildHero(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final tag = node.props['tag'];
  if (tag is! String && tag is! num && tag is! bool) {
    throw const FormatException(
      'quickjs_ui Hero tag must be a string, number or boolean',
    );
  }
  return Hero(
    tag: tag as Object,
    transitionOnUserGestures:
        QuickjsUiProps.boolValue(node.props['transitionOnUserGestures']) ??
        false,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildAnimatedSwitcher(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return AnimatedSwitcher(
    duration:
        quickjsUiAnimationDuration(node) ?? const Duration(milliseconds: 200),
    reverseDuration: QuickjsUiProps.duration(
      node.props['reverseDurationMs'],
      name: 'reverse animation duration',
    ),
    switchInCurve: QuickjsUiProps.curve(node.props['switchInCurve']),
    switchOutCurve: QuickjsUiProps.curve(node.props['switchOutCurve']),
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
