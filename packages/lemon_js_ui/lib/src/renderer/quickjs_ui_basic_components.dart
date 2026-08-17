// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_control_style.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiBasicComponentBuilders =
    <String, JsUiComponentBuilder>{
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

Widget _buildText(JsUiRenderContext context, JsUiNode node) {
  final data = JsUiProps.string(node.props['data'] ?? node.props['text']) ?? '';
  return Text(
    data,
    textAlign: JsUiProps.textAlign(node.props['textAlign']),
    maxLines: JsUiProps.intValue(node.props['maxLines']),
    softWrap: JsUiProps.boolValue(node.props['softWrap']),
    overflow: _textOverflow(node.props['overflow']),
    style: context.textStyle(node.props['style']),
  );
}

TextOverflow? _textOverflow(Object? value) => switch (value) {
  null => null,
  'clip' => TextOverflow.clip,
  'fade' => TextOverflow.fade,
  'ellipsis' => TextOverflow.ellipsis,
  'visible' => TextOverflow.visible,
  _ => throw const FormatException('Unknown quickjs_ui Text overflow'),
};

Widget _buildElevatedButton(JsUiRenderContext context, JsUiNode node) {
  return _buildButton(context, node, _JsUiButtonKind.elevated);
}

Widget _buildTextButton(JsUiRenderContext context, JsUiNode node) {
  return _buildButton(context, node, _JsUiButtonKind.text);
}

Widget _buildOutlinedButton(JsUiRenderContext context, JsUiNode node) {
  return _buildButton(context, node, _JsUiButtonKind.outlined);
}

Widget _buildButton(
  JsUiRenderContext context,
  JsUiNode node,
  _JsUiButtonKind kind,
) {
  final event = JsUiProps.event(node.props['onPressed']);
  final style = JsUiControlStyle.from(context, node.props['stateStyles']);
  final transition = JsUiControlTransition.from(node.props['stateTransition']);
  final onPressed = event == null ? null : () => context.dispatch(event);
  final child = _buttonChild(context, node);
  return JsUiControlInteractionScope(
    enabled: event != null,
    builder: (buildContext, interaction) {
      final effectiveTransition =
          MediaQuery.maybeOf(buildContext)?.disableAnimations ?? false
          ? JsUiControlTransition(
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
        _JsUiButtonKind.elevated => ElevatedButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
        _JsUiButtonKind.text => TextButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
        _JsUiButtonKind.outlined => OutlinedButton(
          focusNode: interaction.focusNode,
          statesController: interaction.statesController,
          onPressed: onPressed,
          style: buttonStyle,
          child: interactiveChild,
        ),
      };
      return JsUiControlTransitionBuilder(
        styles: <JsUiControlStyle>[style],
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

enum _JsUiButtonKind { elevated, text, outlined }

Widget _buildIconButton(JsUiRenderContext context, JsUiNode node) {
  final event = JsUiProps.event(node.props['onPressed']);
  final tooltip = JsUiProps.string(node.props['tooltip']);
  return IconButton(
    tooltip: tooltip,
    iconSize: JsUiProps.doubleValue(node.props['iconSize']),
    color: context.color(node.props['color']),
    onPressed: event == null ? null : () => context.dispatch(event),
    icon:
        context.child(node) ??
        Icon(jsUiIconData(JsUiProps.string(node.props['icon']) ?? 'help')),
  );
}

Widget _buildInkWell(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    context.child(node) ?? const SizedBox(),
  );
}

Widget _buildFloatingActionButton(JsUiRenderContext context, JsUiNode node) {
  final event = JsUiProps.event(node.props['onPressed']);
  return FloatingActionButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    tooltip: JsUiProps.string(node.props['tooltip']),
    backgroundColor: context.color(node.props['backgroundColor']),
    foregroundColor: context.color(node.props['foregroundColor']),
    child:
        context.child(node) ??
        Icon(jsUiIconData(JsUiProps.string(node.props['icon']) ?? 'add')),
  );
}

Widget _buttonChild(JsUiRenderContext context, JsUiNode node) {
  final leading = context.slot(node, 'leading');
  final content =
      context.child(node) ??
      context.slot(node, 'content') ??
      Text(JsUiProps.string(node.props['label']) ?? '');
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

Widget _buildIcon(JsUiRenderContext context, JsUiNode node) {
  return Icon(
    jsUiIconData(JsUiProps.string(node.props['icon'] ?? node.props['name'])),
    size: JsUiProps.doubleValue(node.props['size']),
    color: context.color(node.props['color']),
    semanticLabel: JsUiProps.string(node.props['semanticLabel']),
  );
}

Widget _buildDivider(JsUiRenderContext context, JsUiNode node) {
  return Divider(
    height: JsUiProps.doubleValue(node.props['height']),
    thickness: JsUiProps.doubleValue(node.props['thickness']),
    indent: JsUiProps.doubleValue(node.props['indent']),
    endIndent: JsUiProps.doubleValue(node.props['endIndent']),
    color: context.color(node.props['color']),
  );
}

Widget _buildVerticalDivider(JsUiRenderContext context, JsUiNode node) {
  return VerticalDivider(
    width: JsUiProps.doubleValue(node.props['width']),
    thickness: JsUiProps.doubleValue(node.props['thickness']),
    indent: JsUiProps.doubleValue(node.props['indent']),
    endIndent: JsUiProps.doubleValue(node.props['endIndent']),
    color: context.color(node.props['color']),
  );
}

Widget _buildPlaceholder(JsUiRenderContext context, JsUiNode node) {
  return Placeholder(
    color: context.color(node.props['color']) ?? const Color(0xFF455A64),
    strokeWidth: JsUiProps.doubleValue(node.props['strokeWidth']) ?? 2,
    fallbackWidth: JsUiProps.doubleValue(node.props['fallbackWidth']) ?? 400,
    fallbackHeight: JsUiProps.doubleValue(node.props['fallbackHeight']) ?? 400,
  );
}

Widget _buildGestureDetector(JsUiRenderContext context, JsUiNode node) {
  return withJsUiGestures(
    context,
    node,
    context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildTooltip(JsUiRenderContext context, JsUiNode node) {
  final message = JsUiProps.string(node.props['message']);
  if (message == null || message.isEmpty) {
    throw const FormatException('quickjs_ui Tooltip message is required');
  }
  return Tooltip(
    message: message,
    waitDuration: JsUiProps.duration(node.props['waitDurationMs']),
    showDuration: JsUiProps.duration(node.props['showDurationMs']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildCard(JsUiRenderContext context, JsUiNode node) {
  return Card(
    color: context.color(node.props['color']),
    elevation: context.elevation(node.props['elevation']),
    margin: context.edgeInsets(node.props['margin']),
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node),
  );
}

Widget _buildClipRRect(JsUiRenderContext context, JsUiNode node) {
  return ClipRRect(
    borderRadius:
        context.borderRadius(node.props['borderRadius']) ?? BorderRadius.zero,
    clipBehavior: _clipBehavior(node.props['clipBehavior']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildBackdropFilter(JsUiRenderContext context, JsUiNode node) {
  return BackdropFilter(
    filter: _imageFilter(node.props['filter'] ?? node.props['imageFilter']),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildDecoratedBox(JsUiRenderContext context, JsUiNode node) {
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

Widget _buildRichText(JsUiRenderContext context, JsUiNode node) {
  return RichText(
    textAlign: JsUiProps.textAlign(node.props['textAlign']) ?? TextAlign.start,
    text: TextSpan(
      style: context.textStyle(node.props['style']),
      children: _textSpans(context, node.props['spans'] ?? node.props['text']),
    ),
  );
}

Widget _buildCircularProgressIndicator(
  JsUiRenderContext context,
  JsUiNode node,
) {
  return CircularProgressIndicator(
    value: JsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    strokeWidth: JsUiProps.doubleValue(node.props['strokeWidth']) ?? 4,
  );
}

Widget _buildLinearProgressIndicator(JsUiRenderContext context, JsUiNode node) {
  return LinearProgressIndicator(
    value: JsUiProps.doubleValue(node.props['value']),
    color: context.color(node.props['color']),
    backgroundColor: context.color(node.props['backgroundColor']),
    minHeight: JsUiProps.doubleValue(node.props['minHeight']),
  );
}

List<InlineSpan> _textSpans(JsUiRenderContext context, Object? value) {
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

InlineSpan _textSpan(JsUiRenderContext context, Object? value) {
  if (value is String) {
    return TextSpan(text: value);
  }
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    return TextSpan(
      text: JsUiProps.string(props['text']) ?? '',
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
      final sigma = JsUiProps.doubleValue(props['sigma']);
      return ui.ImageFilter.blur(
        sigmaX: JsUiProps.doubleValue(props['sigmaX']) ?? sigma ?? 0,
        sigmaY: JsUiProps.doubleValue(props['sigmaY']) ?? sigma ?? 0,
      );
  }
  throw FormatException('Unsupported quickjs_ui ImageFilter "$type"');
}
