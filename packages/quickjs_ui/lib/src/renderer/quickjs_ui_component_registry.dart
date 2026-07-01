import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

typedef QuickjsUiComponentBuilder =
    Widget Function(QuickjsUiRenderContext context, QuickjsUiNode node);

final class QuickjsUiComponentRegistry {
  QuickjsUiComponentRegistry([Map<String, QuickjsUiComponentBuilder>? builders])
    : _builders = <String, QuickjsUiComponentBuilder>{...?builders};

  factory QuickjsUiComponentRegistry.defaults() {
    return QuickjsUiComponentRegistry(<String, QuickjsUiComponentBuilder>{
      'Text': _buildText,
      'ElevatedButton': _buildElevatedButton,
      'Row': _buildRow,
      'Column': _buildColumn,
      'Container': _buildContainer,
      'Image': _buildImage,
      'ListView': _buildListView,
      'TextField': _buildTextField,
      'Stack': _buildStack,
      'Padding': _buildPadding,
      'Center': _buildCenter,
      'SizedBox': _buildSizedBox,
    });
  }

  final Map<String, QuickjsUiComponentBuilder> _builders;

  Iterable<String> get types => _builders.keys;

  bool contains(String type) {
    return _builders.containsKey(type);
  }

  void register(String type, QuickjsUiComponentBuilder builder) {
    _builders[type] = builder;
  }

  void unregister(String type) {
    _builders.remove(type);
  }

  Widget build(QuickjsUiRenderContext context, QuickjsUiNode node) {
    final builder = _builders[node.type];
    if (builder == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return builder(context, node);
  }
}

Widget _buildText(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final data =
      QuickjsUiProps.string(node.props['data'] ?? node.props['text']) ?? '';
  return Text(
    data,
    textAlign: QuickjsUiProps.textAlign(node.props['textAlign']),
    style: QuickjsUiProps.textStyle(node.props['style']),
  );
}

Widget _buildElevatedButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final event = QuickjsUiProps.event(node.props['onPressed']);
  return ElevatedButton(
    onPressed: event == null ? null : () => context.dispatch(event),
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildRow(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Row(
    mainAxisAlignment: QuickjsUiProps.mainAxisAlignment(
      node.props['mainAxisAlignment'],
    ),
    crossAxisAlignment: QuickjsUiProps.crossAxisAlignment(
      node.props['crossAxisAlignment'],
    ),
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
    children: context.children(node),
  );
}

Widget _buildContainer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final decoration = QuickjsUiProps.boxDecoration(node.props);
  final opacity = QuickjsUiProps.opacity(node.props['opacity']);
  final child = Container(
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    padding: QuickjsUiProps.edgeInsets(node.props['padding']),
    margin: QuickjsUiProps.edgeInsets(node.props['margin']),
    alignment: QuickjsUiProps.alignment(node.props['alignment']),
    decoration: decoration,
    color: decoration == null
        ? QuickjsUiProps.color(
            node.props['color'] ?? node.props['backgroundColor'],
          )
        : null,
    child: context.child(node),
  );
  if (opacity == 1) {
    return child;
  }
  return Opacity(opacity: opacity, child: child);
}

Widget _buildImage(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final source =
      QuickjsUiProps.string(node.props['src'] ?? node.props['source']) ?? '';
  if (source.isEmpty) {
    throw const FormatException('quickjs_ui Image src must not be empty');
  }
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final fit = QuickjsUiProps.boxFit(node.props['fit']);
  final uri = Uri.tryParse(source);
  if (uri != null && uri.hasScheme && uri.scheme.startsWith('http')) {
    return Image.network(source, width: width, height: height, fit: fit);
  }
  return Image.asset(source, width: width, height: height, fit: fit);
}

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return ListView(
    scrollDirection: QuickjsUiProps.axis(node.props['scrollDirection']),
    shrinkWrap:
        QuickjsUiProps.boolValue(node.props['shrinkWrap']) ??
        (node.props['shrinkWrap'] == null),
    padding: QuickjsUiProps.edgeInsets(node.props['padding']),
    children: context.children(node),
  );
}

Widget _buildTextField(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final onSubmitted = QuickjsUiProps.event(node.props['onSubmitted']);
  final onFocus = QuickjsUiProps.event(node.props['onFocus']);
  final onBlur = QuickjsUiProps.event(node.props['onBlur']);
  return _QuickjsUiTextField(
    value:
        QuickjsUiProps.string(
          node.props['value'] ?? node.props['initialValue'],
          name: 'TextField value',
        ) ??
        '',
    enabled: QuickjsUiProps.boolValue(node.props['enabled']) ?? true,
    autofocus: QuickjsUiProps.boolValue(node.props['autofocus']) ?? false,
    obscureText: QuickjsUiProps.boolValue(node.props['obscureText']) ?? false,
    maxLines: QuickjsUiProps.intValue(node.props['maxLines']),
    keyboardType: QuickjsUiProps.textInputType(node.props['keyboardType']),
    textInputAction: QuickjsUiProps.textInputAction(
      node.props['textInputAction'],
    ),
    decoration: InputDecoration(
      labelText: QuickjsUiProps.string(node.props['labelText']),
      hintText: QuickjsUiProps.string(node.props['hintText']),
    ),
    onChanged: onChanged == null
        ? null
        : (value) =>
              context.dispatch(<String, Object?>{...onChanged, 'value': value}),
    onSubmitted: onSubmitted == null
        ? null
        : (value) => context.dispatch(<String, Object?>{
            ...onSubmitted,
            'value': value,
          }),
    onFocus: onFocus == null
        ? null
        : (value) =>
              context.dispatch(<String, Object?>{...onFocus, 'value': value}),
    onBlur: onBlur == null
        ? null
        : (value) =>
              context.dispatch(<String, Object?>{...onBlur, 'value': value}),
  );
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

Widget _buildPadding(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Padding(
    padding:
        QuickjsUiProps.edgeInsets(node.props['padding']) ?? EdgeInsets.zero,
    child: context.child(node) ?? const SizedBox.shrink(),
  );
}

Widget _buildCenter(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Center(
    widthFactor: QuickjsUiProps.doubleValue(node.props['widthFactor']),
    heightFactor: QuickjsUiProps.doubleValue(node.props['heightFactor']),
    child: context.child(node),
  );
}

Widget _buildSizedBox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return SizedBox(
    width: QuickjsUiProps.doubleValue(node.props['width']),
    height: QuickjsUiProps.doubleValue(node.props['height']),
    child: context.child(node),
  );
}

final class _QuickjsUiTextField extends StatefulWidget {
  const _QuickjsUiTextField({
    required this.value,
    required this.enabled,
    required this.autofocus,
    required this.obscureText,
    required this.decoration,
    this.maxLines,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onFocus,
    this.onBlur,
  });

  final String value;
  final bool enabled;
  final bool autofocus;
  final bool obscureText;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final InputDecoration decoration;
  final ValueChanged<String>? onChanged;
  final ValueChanged<String>? onSubmitted;
  final ValueChanged<String>? onFocus;
  final ValueChanged<String>? onBlur;

  @override
  State<_QuickjsUiTextField> createState() => _QuickjsUiTextFieldState();
}

final class _QuickjsUiTextFieldState extends State<_QuickjsUiTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call(_controller.text);
    } else {
      widget.onBlur?.call(_controller.text);
    }
  }

  @override
  Widget build(BuildContext context) {
    return TextField(
      controller: _controller,
      focusNode: _focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      onChanged: widget.onChanged,
      onSubmitted: widget.onSubmitted,
    );
  }
}
