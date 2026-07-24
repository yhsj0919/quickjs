import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_control_style.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiBasicComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'Text': _buildText,
      'ElevatedButton': _buildElevatedButton,
      'TextButton': _buildTextButton,
      'OutlinedButton': _buildOutlinedButton,
      'IconButton': _buildIconButton,
      'InkWell': _buildInkWell,
      'FloatingActionButton': _buildFloatingActionButton,
      'Icon': _buildIcon,
      'Divider': _buildDivider,
      'VerticalDivider': _buildVerticalDivider,
      'Placeholder': _buildPlaceholder,
      'GestureDetector': _buildGestureDetector,
      'Tooltip': _buildTooltip,
      'Card': _buildCard,
      'ClipRRect': _buildClipRRect,
      'BackdropFilter': _buildBackdropFilter,
      'DecoratedBox': _buildDecoratedBox,
      'RichText': _buildRichText,
      'CircularProgressIndicator': _buildCircularProgressIndicator,
      'LinearProgressIndicator': _buildLinearProgressIndicator,
    };

Widget _buildText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final data =
      QuickjsUiProps.string(node.props['data'] ?? node.props['text']) ?? '';
  return Text(
    data,
    textAlign: QuickjsUiProps.textAlign(node.props['textAlign']),
    style: context.textStyle(node.props['style']),
  );
}

Widget _buildElevatedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return _buildButton(context, node, _QuickjsUiButtonKind.elevated);
}

Widget _buildTextButton(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _buildButton(context, node, _QuickjsUiButtonKind.text);
}

Widget _buildOutlinedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return _buildButton(context, node, _QuickjsUiButtonKind.outlined);
}

Widget _buildButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  _QuickjsUiButtonKind kind,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  final style = QuickjsUiControlStyle.from(context, node.props['stateStyles']);
  final transition = QuickjsUiControlTransition.from(
    node.props['stateTransition'],
  );
  final onPressed = event == null ? null : () => context.dispatch(event);
  final child = _buttonChild(context, node);
  return QuickjsUiControlInteractionScope(
    enabled: event != null,
    builder: (buildContext, interaction) {
      final effectiveTransition =
          MediaQuery.maybeOf(buildContext)?.disableAnimations ?? false
          ? QuickjsUiControlTransition(
              duration: Duration.zero,
              curve: transition.curve,
            )
          : transition;
      final resolved = style.resolve(interaction.states);
      final buttonStyle = style
          .buttonStyle(effectiveTransition)
          .copyWith(
            padding: const WidgetStatePropertyAll<EdgeInsetsGeometry>(
              EdgeInsets.zero,
            ),
          );
      final interactiveChild = Padding(
        padding:
            resolved.padding('padding') ??
            const EdgeInsets.symmetric(horizontal: 24, vertical: 10),
        child: child,
      );
      final button = switch (kind) {
        _QuickjsUiButtonKind.elevated => ElevatedButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
        _QuickjsUiButtonKind.text => TextButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
        _QuickjsUiButtonKind.outlined => OutlinedButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
      };
      return QuickjsUiControlTransitionBuilder(
        styles: <QuickjsUiControlStyle>[style],
        states: interaction.states,
        transition: transition,
        child: RepaintBoundary(child: button),
        builder: (context, styles, child) => styles.single.decorate(
          child!,
          stableScaleTopology: style.requiresStablePointerScale,
          stableOpacityTopology: style.requiresStablePointerOpacity,
        ),
      );
    },
  );
}

enum _QuickjsUiButtonKind { elevated, text, outlined }

Widget _buildIconButton(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  final tooltip = QuickjsUiProps.string(node.props['tooltip']);
  return IconButton(
    tooltip: tooltip,
    iconSize: QuickjsUiProps.doubleValue(node.props['iconSize']),
    color: context.color(node.props['color']),
    onPressed: event == null ? null : () => context.dispatch(event),
    icon:
        context.child(node) ??
        Icon(
          quickjsUiIconData(
            QuickjsUiProps.string(node.props['icon']) ?? 'help',
          ),
        ),
  );
}

Widget _buildInkWell(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return withQuickjsUiGestures(
    context,
    node,
    context.child(node) ?? const SizedBox(),
  );
}

Widget _buildFloatingActionButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return FloatingActionButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    tooltip: QuickjsUiProps.string(node.props['tooltip']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    child:
        context.child(node) ??
        Icon(
          quickjsUiIconData(QuickjsUiProps.string(node.props['icon']) ?? 'add'),
        ),
  );
}

Widget _buttonChild(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final leading = context.slot(node, 'leading');
  final content =
      context.child(node) ??
      context.slot(node, 'content') ??
      Text(QuickjsUiProps.string(node.props['label']) ?? '');
  final trailing = context.slot(node, 'trailing');
  if (leading == null && trailing == null) {
    return content;
  }
  final gap = context.spacing(node.props['gap'], name: 'button gap') ?? 8;
  return Row(
    mainAxisSize: MainAxisSize.min,
    children: <Widget>[
      ?leading,
      if (leading != null) SizedBox(width: gap),
      content,
      if (trailing != null) SizedBox(width: gap),
      ?trailing,
    ],
  );
}

Widget _buildIcon(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Icon(
    quickjsUiIconData(
      QuickjsUiProps.string(node.props['icon'] ?? node.props['name']),
    ),
    size: QuickjsUiProps.doubleValue(node.props['size']),
    color: context.color(node.props['color']),
    semanticLabel: QuickjsUiProps.string(node.props['semanticLabel']),
  );
}

Widget _buildDivider(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Divider(
    height: QuickjsUiProps.doubleValue(node.props['height']),
    thickness: QuickjsUiProps.doubleValue(node.props['thickness']),
    indent: QuickjsUiProps.doubleValue(node.props['indent']),
    endIndent: QuickjsUiProps.doubleValue(node.props['endIndent']),
    color: context.color(node.props['color']),
  );
}

Widget _buildVerticalDivider(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return VerticalDivider(
    width: QuickjsUiProps.doubleValue(node.props['width']),
    thickness: QuickjsUiProps.doubleValue(node.props['thickness']),
    indent: QuickjsUiProps.doubleValue(node.props['indent']),
    endIndent: QuickjsUiProps.doubleValue(node.props['endIndent']),
    color: context.color(node.props['color']),
  );
}

Widget _buildPlaceholder(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Placeholder(
    color: context.color(node.props['color']) ?? const Color(0xFF455A64),
    strokeWidth: QuickjsUiProps.doubleValue(node.props['strokeWidth']) ?? 2,
    fallbackWidth:
        QuickjsUiProps.doubleValue(node.props['fallbackWidth']) ?? 400,
    fallbackHeight:
        QuickjsUiProps.doubleValue(node.props['fallbackHeight']) ?? 400,
  );
}

Widget _buildGestureDetector(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return withQuickjsUiGestures(
    context,
    node,
    context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildTooltip(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final message = QuickjsUiProps.string(node.props['message']);
  if (message == null || message.isEmpty) {
    throw const FormatException('quickjs_ui Tooltip message is required');
  }
  return Tooltip(
    message: message,
    waitDuration: QuickjsUiProps.duration(node.props['waitDurationMs']),
    showDuration: QuickjsUiProps.duration(node.props['showDurationMs']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildCard(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Card(
    color: context.color(node.props['color']),
    elevation: context.elevation(node.props['elevation']),
    margin: context.edgeInsets(node.props['margin']),
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node),
  );
}

Widget _buildClipRRect(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return ClipRRect(
    borderRadius:
        context.borderRadius(node.props['borderRadius']) ?? BorderRadius.zero,
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildBackdropFilter(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return BackdropFilter(
    filter: _imageFilter(node.props['filter'] ?? node.props['imageFilter']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildDecoratedBox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return DecoratedBox(
    decoration:
        context.boxDecoration(node.props) ??
        BoxDecoration(color: context.color(node.props['color'])),
    position: node.props['position'] == 'foreground'
        ? DecorationPosition.foreground
        : DecorationPosition.background,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildRichText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return RichText(
    textAlign:
        QuickjsUiProps.textAlign(node.props['textAlign']) ?? TextAlign.start,
    text: TextSpan(
      style: context.textStyle(node.props['style']),
      children: _textSpans(context, node.props['spans'] ?? node.props['text']),
    ),
  );
}

Widget _buildCircularProgressIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return CircularProgressIndicator(
    value: QuickjsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    strokeWidth: QuickjsUiProps.doubleValue(node.props['strokeWidth']) ?? 4,
  );
}

Widget _buildLinearProgressIndicator(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  return LinearProgressIndicator(
    value: QuickjsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    minHeight: QuickjsUiProps.doubleValue(node.props['minHeight']),
  );
}

List<InlineSpan> _textSpans(QuickjsUiRenderContext context, Object? value) {
  if (value == null) {
    return const <InlineSpan>[];
  }
  if (value is String) {
    return <InlineSpan>[TextSpan(text: value)];
  }
  if (value is! List) {
    throw const FormatException('quickjs_ui RichText spans must be a list');
  }
  return <InlineSpan>[for (final item in value) _textSpan(context, item)];
}

InlineSpan _textSpan(QuickjsUiRenderContext context, Object? value) {
  if (value is String) {
    return TextSpan(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    return TextSpan(
      text: QuickjsUiProps.string(props['text']) ?? '',
      style: context.textStyle(props['style']),
      children: _textSpans(context, props['children']),
    );
  }
  throw const FormatException('quickjs_ui TextSpan must be a string or object');
}

Clip _clipBehavior(Object? value) {
  return switch (value) {
    null || 'antiAlias' => Clip.antiAlias,
    'none' => Clip.none,
    'hardEdge' => Clip.hardEdge,
    'antiAliasWithSaveLayer' => Clip.antiAliasWithSaveLayer,
    _ => throw const FormatException('Unknown quickjs_ui Clip'),
  };
}

ui.ImageFilter _imageFilter(Object? value) {
  if (value == null) {
    return ui.ImageFilter.blur();
  }
  if (value is String) {
    if (value == 'blur') {
      return ui.ImageFilter.blur();
    }
    throw FormatException('Unsupported quickjs_ui ImageFilter "$value"');
  }
  if (value is! Map) {
    throw const FormatException('quickjs_ui ImageFilter must be an object');
  }
  final props = value.map(
    (key, value) => MapEntry<String, Object?>('$key', value),
  );
  final type = props['type'] ?? props['kind'];
  switch (type) {
    case null:
    case 'blur':
      final sigma = QuickjsUiProps.doubleValue(props['sigma']);
      return ui.ImageFilter.blur(
        sigmaX: QuickjsUiProps.doubleValue(props['sigmaX']) ?? sigma ?? 0,
        sigmaY: QuickjsUiProps.doubleValue(props['sigmaY']) ?? sigma ?? 0,
      );
  }
  throw FormatException('Unsupported quickjs_ui ImageFilter "$type"');
}
