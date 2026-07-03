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
      'Form': _buildForm,
      'Checkbox': _buildCheckbox,
      'Switch': _buildSwitch,
      'Radio': _buildRadio,
      'DropdownButton': _buildDropdownButton,
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
    spacing: _gap(node),
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
    spacing: _gap(node),
    children: context.children(node),
  );
}

Widget _buildContainer(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final decoration = context.boxDecoration(node.props);
  final opacity = QuickjsUiProps.opacity(node.props['opacity']);
  final animationDuration = _animationDuration(node);
  final curve = QuickjsUiProps.curve(node.props['animationCurve']);
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final padding = QuickjsUiProps.edgeInsets(node.props['padding']);
  final margin = QuickjsUiProps.edgeInsets(node.props['margin']);
  final alignment = QuickjsUiProps.alignment(node.props['alignment']);
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
  if (opacity != 1) {
    child = animationDuration == null
        ? Opacity(opacity: opacity, child: child)
        : AnimatedOpacity(
            opacity: opacity,
            duration: animationDuration,
            curve: curve,
            child: child,
          );
  }
  return _withGestures(context, node, child);
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
    return _withGestures(
      context,
      node,
      Image.network(
        source,
        width: width,
        height: height,
        fit: fit,
        errorBuilder: (_, _, _) {
          return SizedBox(width: width, height: height);
        },
      ),
    );
  }
  return _withGestures(
    context,
    node,
    Image.asset(source, width: width, height: height, fit: fit),
  );
}

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final onScroll = QuickjsUiProps.event(node.props['onScroll']);
  final listView = ListView(
    scrollDirection: axis,
    shrinkWrap:
        QuickjsUiProps.boolValue(node.props['shrinkWrap']) ??
        (node.props['shrinkWrap'] == null),
    padding: QuickjsUiProps.edgeInsets(node.props['padding']),
    children: _childrenWithGap(context, node, axis),
  );
  final withGestures = _withGestures(context, node, listView);
  if (onScroll == null) {
    return withGestures;
  }
  return NotificationListener<ScrollNotification>(
    onNotification: (notification) {
      final metrics = notification.metrics;
      context.dispatchEvent(
        onScroll,
        defaultCoalesceKey: _eventKey(node, 'onScroll'),
        payload: <String, Object?>{
          'pixels': metrics.pixels,
          'minScrollExtent': metrics.minScrollExtent,
          'maxScrollExtent': metrics.maxScrollExtent,
          'viewportDimension': metrics.viewportDimension,
          'axis': metrics.axis.name,
        },
      );
      return false;
    },
    child: withGestures,
  );
}

List<Widget> _childrenWithGap(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Axis axis,
) {
  final children = context.children(node);
  final gap = _gap(node);
  if (children.length < 2 || gap <= 0) {
    return children;
  }
  return <Widget>[
    for (var index = 0; index < children.length; index++) ...<Widget>[
      if (index > 0)
        axis == Axis.horizontal ? SizedBox(width: gap) : SizedBox(height: gap),
      children[index],
    ],
  ];
}

double _gap(QuickjsUiNode node) {
  return QuickjsUiProps.doubleValue(node.props['gap'], name: 'gap') ?? 0;
}

Duration? _animationDuration(QuickjsUiNode node) {
  return QuickjsUiProps.duration(
    node.props['animationDurationMs'] ?? node.props['durationMs'],
    name: 'animation duration',
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
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            payload: <String, Object?>{'value': value},
          ),
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
  final padding =
      QuickjsUiProps.edgeInsets(node.props['padding']) ?? EdgeInsets.zero;
  final animationDuration = _animationDuration(node);
  final child = context.child(node) ?? const SizedBox.shrink();
  return _withGestures(
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

Widget _buildCenter(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return _withGestures(
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
  return _withGestures(
    context,
    node,
    SizedBox(
      width: QuickjsUiProps.doubleValue(node.props['width']),
      height: QuickjsUiProps.doubleValue(node.props['height']),
      child: context.child(node),
    ),
  );
}

Widget _buildForm(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return Form(child: context.child(node) ?? const SizedBox.shrink());
}

Widget _buildCheckbox(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  return Checkbox(
    value: QuickjsUiProps.boolValue(node.props['value']) ?? false,
    tristate: QuickjsUiProps.boolValue(node.props['tristate']) ?? false,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildSwitch(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  return Switch(
    value: QuickjsUiProps.boolValue(node.props['value']) ?? false,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildRadio(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final value = node.props['value'];
  // Keep compatibility with the package's older Flutter lower bound.
  // ignore: deprecated_member_use
  return Radio<Object?>(
    value: value,
    // ignore: deprecated_member_use
    groupValue: node.props['groupValue'],
    // ignore: deprecated_member_use
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildDropdownButton(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final items = _dropdownItems(node.props['items']);
  final value = node.props['value'];
  final hint = QuickjsUiProps.string(node.props['hint']);
  return DropdownButton<Object?>(
    value: items.any((item) => item.value == value) ? value : null,
    isExpanded: QuickjsUiProps.boolValue(node.props['isExpanded']) ?? false,
    hint: hint == null ? null : Text(hint),
    items: items,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            payload: <String, Object?>{'value': value},
          ),
  );
}

List<DropdownMenuItem<Object?>> _dropdownItems(Object? value) {
  if (value == null) {
    return const <DropdownMenuItem<Object?>>[];
  }
  if (value is! List) {
    throw const FormatException(
      'quickjs_ui DropdownButton items must be a list',
    );
  }
  return <DropdownMenuItem<Object?>>[
    for (final item in value) _dropdownItem(item),
  ];
}

DropdownMenuItem<Object?> _dropdownItem(Object? value) {
  if (value is Map) {
    final props = value.map(
      (key, value) => MapEntry<String, Object?>('$key', value),
    );
    final itemValue = props['value'];
    return DropdownMenuItem<Object?>(
      value: itemValue,
      child: Text(QuickjsUiProps.string(props['label']) ?? '$itemValue'),
    );
  }
  return DropdownMenuItem<Object?>(value: value, child: Text('$value'));
}

Widget _withGestures(
  QuickjsUiRenderContext context,
  QuickjsUiNode node,
  Widget child,
) {
  final onTap = QuickjsUiProps.event(node.props['onTap']);
  final onLongPress = QuickjsUiProps.event(node.props['onLongPress']);
  if (onTap == null && onLongPress == null) {
    return child;
  }
  return GestureDetector(
    behavior: HitTestBehavior.opaque,
    onTap: onTap == null
        ? null
        : () => context.dispatchEvent(
            onTap,
            defaultCoalesceKey: _eventKey(node, 'onTap'),
          ),
    onLongPress: onLongPress == null
        ? null
        : () => context.dispatchEvent(
            onLongPress,
            defaultCoalesceKey: _eventKey(node, 'onLongPress'),
          ),
    child: child,
  );
}

String _eventKey(QuickjsUiNode node, String prop) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return '${node.type}:$key:$prop';
  }
  return '${node.type}:${identityHashCode(node)}:$prop';
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
