import 'dart:ui' as ui;

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
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
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return ElevatedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

Widget _buildTextButton(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return TextButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

Widget _buildOutlinedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return OutlinedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: _buttonChild(context, node),
  );
}

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
  return context.child(node) ??
      Text(QuickjsUiProps.string(node.props['label']) ?? '');
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
