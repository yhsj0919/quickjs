import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../resource/quickjs_ui_resource.dart';
import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

typedef QuickjsUiComponentBuilder =
    Widget Function(QuickjsUiRenderContext context, QuickjsUiNode node);

typedef QuickjsUiComponentControllerFactory =
    QuickjsUiComponentController Function(QuickjsUiNode node);

typedef QuickjsUiLifecycleComponentBuilder<
  T extends QuickjsUiComponentController
> =
    Widget Function(
      QuickjsUiRenderContext context,
      QuickjsUiNode node,
      T controller,
    );

base class QuickjsUiComponentController {
  void mount(QuickjsUiNode node) {}

  void update(QuickjsUiNode previous, QuickjsUiNode next) {}

  void show() {}

  void hide() {}

  void pause() {}

  void resume() {}

  void dispose() {}
}

final class QuickjsUiComponentRegistry {
  QuickjsUiComponentRegistry([Map<String, QuickjsUiComponentBuilder>? builders])
    : _components = <String, _QuickjsUiComponentDefinition>{
        for (final entry in builders?.entries ?? const Iterable.empty())
          entry.key: _QuickjsUiComponentDefinition.builder(entry.value),
      };

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
      'Slider': _buildSlider,
      'Radio': _buildRadio,
      'DropdownButton': _buildDropdownButton,
    });
  }

  final Map<String, _QuickjsUiComponentDefinition> _components;

  Iterable<String> get types => _components.keys;

  bool contains(String type) {
    return _components.containsKey(type);
  }

  void register(String type, QuickjsUiComponentBuilder builder) {
    _components[type] = _QuickjsUiComponentDefinition.builder(builder);
  }

  void registerLifecycle<T extends QuickjsUiComponentController>(
    String type, {
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    _components[type] = _QuickjsUiComponentDefinition.lifecycle(
      createController: createController,
      build: build,
    );
  }

  void unregister(String type) {
    _components.remove(type);
  }

  bool hasLifecycle(String type) {
    return _components[type]?.hasLifecycle == true;
  }

  QuickjsUiComponentController createController(QuickjsUiNode node) {
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    final create = component.createController;
    if (create == null) {
      throw FormatException(
        'quickjs_ui node type ${node.type} does not define a controller',
      );
    }
    return create(node);
  }

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node, {
    QuickjsUiComponentController? controller,
  }) {
    final component = _components[node.type];
    if (component == null) {
      throw FormatException('Unknown quickjs_ui node type: ${node.type}');
    }
    return component.build(context, node, controller);
  }
}

final class _QuickjsUiComponentDefinition {
  _QuickjsUiComponentDefinition.builder(QuickjsUiComponentBuilder builder)
    : createController = null,
      _build = ((context, node, _) => builder(context, node));

  _QuickjsUiComponentDefinition._({
    required this.createController,
    required this._build,
  });

  static _QuickjsUiComponentDefinition
  lifecycle<T extends QuickjsUiComponentController>({
    required T Function(QuickjsUiNode node) createController,
    required QuickjsUiLifecycleComponentBuilder<T> build,
  }) {
    return _QuickjsUiComponentDefinition._(
      createController: createController,
      build: (context, node, controller) {
        if (controller is! T) {
          throw StateError(
            'quickjs_ui lifecycle controller type mismatch for ${node.type}',
          );
        }
        return build(context, node, controller);
      },
    );
  }

  final QuickjsUiComponentControllerFactory? createController;
  final Widget Function(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  )
  _build;

  bool get hasLifecycle => createController != null;

  Widget build(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    QuickjsUiComponentController? controller,
  ) {
    if (hasLifecycle && controller == null) {
      throw StateError(
        'quickjs_ui lifecycle component ${node.type} has no controller',
      );
    }
    return _build(context, node, controller);
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
    spacing: _gap(context, node),
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
    spacing: _gap(context, node),
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
  if (elevation != null && elevation > 0) {
    child = Material(
      elevation: elevation,
      color: Colors.transparent,
      child: child,
    );
  }
  return _withGestures(context, node, child);
}

Widget _buildImage(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final resource = context.resource(
    node.props['src'] ?? node.props['source'],
    name: 'Image src',
  );
  final width = QuickjsUiProps.doubleValue(node.props['width']);
  final height = QuickjsUiProps.doubleValue(node.props['height']);
  final fit = QuickjsUiProps.boxFit(node.props['fit']);
  final image = switch (resource.kind) {
    QuickjsUiResourceKind.asset => Image.asset(
      resource.location,
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.file => Image.file(
      File(_filePath(resource.location)),
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.network => Image.network(
      resource.location,
      headers: resource.headers.isEmpty ? null : resource.headers,
      width: width,
      height: height,
      fit: fit,
      errorBuilder: (_, _, _) {
        return SizedBox(width: width, height: height);
      },
    ),
    QuickjsUiResourceKind.data => Image.memory(
      _dataUriBytes(resource.location),
      width: width,
      height: height,
      fit: fit,
    ),
    QuickjsUiResourceKind.custom => throw FormatException(
      'quickjs_ui Image does not support custom resource: ${resource.location}',
    ),
  };
  return _withGestures(context, node, image);
}

String _filePath(String location) {
  final uri = Uri.tryParse(location);
  if (uri != null && uri.scheme == 'file') {
    return uri.toFilePath();
  }
  return location;
}

Uint8List _dataUriBytes(String location) {
  final comma = location.indexOf(',');
  if (!location.startsWith('data:') || comma == -1) {
    throw const FormatException('quickjs_ui Image data resource is invalid');
  }
  final metadata = location.substring(5, comma);
  final data = location.substring(comma + 1);
  if (metadata.split(';').contains('base64')) {
    return base64Decode(data);
  }
  return Uint8List.fromList(utf8.encode(Uri.decodeComponent(data)));
}

Widget _buildListView(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final axis = QuickjsUiProps.axis(node.props['scrollDirection']);
  final onScroll = QuickjsUiProps.event(node.props['onScroll']);
  final listView = ListView(
    scrollDirection: axis,
    shrinkWrap:
        QuickjsUiProps.boolValue(node.props['shrinkWrap']) ??
        (node.props['shrinkWrap'] == null),
    padding: context.edgeInsets(node.props['padding']),
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
        kind: QuickjsUiEventKind.sample,
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
  final gap = _gap(context, node);
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

double _gap(QuickjsUiRenderContext context, QuickjsUiNode node) {
  return context.spacing(node.props['gap'], name: 'gap') ?? 0;
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
  final onEditingComplete = QuickjsUiProps.event(
    node.props['onEditingComplete'],
  );
  final onSelectionChanged = QuickjsUiProps.event(
    node.props['onSelectionChanged'],
  );
  final focusId = QuickjsUiProps.string(node.props['focusId']);
  return _QuickjsUiTextField(
    value:
        QuickjsUiProps.string(
          node.props['value'] ?? node.props['initialValue'],
          name: 'TextField value',
        ) ??
        '',
    focusId: focusId,
    enabled: QuickjsUiProps.boolValue(node.props['enabled']) ?? true,
    autofocus:
        QuickjsUiProps.boolValue(
          node.props['autofocus'] ?? node.props['focusOnMount'],
        ) ??
        false,
    requestFocus: QuickjsUiProps.boolValue(node.props['requestFocus']) ?? false,
    clearFocus: QuickjsUiProps.boolValue(node.props['clearFocus']) ?? false,
    obscureText: QuickjsUiProps.boolValue(node.props['obscureText']) ?? false,
    maxLines: QuickjsUiProps.intValue(node.props['maxLines']),
    keyboardType: QuickjsUiProps.textInputType(node.props['keyboardType']),
    textInputAction: QuickjsUiProps.textInputAction(
      node.props['textInputAction'],
    ),
    submitFocusAction: _submitFocusAction(
      node.props['submitFocusAction'],
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
            kind: QuickjsUiEventKind.sample,
            payload: value,
          ),
    onSubmitted: onSubmitted == null
        ? null
        : (value) =>
              context.dispatch(<String, Object?>{...onSubmitted, ...value}),
    onEditingComplete: onEditingComplete == null
        ? null
        : (value) => context.dispatch(<String, Object?>{
            ...onEditingComplete,
            ...value,
          }),
    onFocus: onFocus == null
        ? null
        : (value) => context.dispatch(<String, Object?>{...onFocus, ...value}),
    onBlur: onBlur == null
        ? null
        : (value) => context.dispatch(<String, Object?>{...onBlur, ...value}),
    onSelectionChanged: onSelectionChanged == null
        ? null
        : (value) => context.dispatchEvent(
            onSelectionChanged,
            defaultCoalesceKey: _eventKey(node, 'onSelectionChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: value,
          ),
  );
}

_QuickjsUiSubmitFocusAction _submitFocusAction(
  Object? value,
  Object? textInputAction,
) {
  return switch (value) {
    null => switch (textInputAction) {
      'next' => _QuickjsUiSubmitFocusAction.next,
      'previous' => _QuickjsUiSubmitFocusAction.previous,
      _ => _QuickjsUiSubmitFocusAction.none,
    },
    'none' => _QuickjsUiSubmitFocusAction.none,
    'next' => _QuickjsUiSubmitFocusAction.next,
    'previous' => _QuickjsUiSubmitFocusAction.previous,
    'unfocus' => _QuickjsUiSubmitFocusAction.unfocus,
    _ => throw const FormatException('Unknown quickjs_ui submitFocusAction'),
  };
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
  final padding = context.edgeInsets(node.props['padding']) ?? EdgeInsets.zero;
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
            kind: QuickjsUiEventKind.sample,
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
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildSlider(QuickjsUiRenderContext context, QuickjsUiNode node) {
  final onChanged = QuickjsUiProps.event(node.props['onChanged']);
  final onChangeEnd = QuickjsUiProps.event(node.props['onChangeEnd']);
  final min = QuickjsUiProps.doubleValue(node.props['min']) ?? 0;
  final max = QuickjsUiProps.doubleValue(node.props['max']) ?? 1;
  final value = (QuickjsUiProps.doubleValue(node.props['value']) ?? min).clamp(
    min,
    max,
  );
  return Slider(
    min: min,
    max: max,
    value: value,
    divisions: QuickjsUiProps.intValue(node.props['divisions']),
    label: QuickjsUiProps.string(node.props['label']),
    onChanged: onChanged == null
        ? null
        : (next) => context.dispatchEvent(
            onChanged,
            defaultCoalesceKey: _eventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': next},
          ),
    onChangeEnd: onChangeEnd == null
        ? null
        : (next) => context.dispatchEvent(
            onChangeEnd,
            defaultCoalesceKey: _eventKey(node, 'onChangeEnd'),
            payload: <String, Object?>{'value': next},
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
            kind: QuickjsUiEventKind.sample,
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
            kind: QuickjsUiEventKind.sample,
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
    required this.focusId,
    required this.enabled,
    required this.autofocus,
    required this.requestFocus,
    required this.clearFocus,
    required this.obscureText,
    required this.decoration,
    required this.submitFocusAction,
    this.maxLines,
    this.keyboardType,
    this.textInputAction,
    this.onChanged,
    this.onSubmitted,
    this.onEditingComplete,
    this.onFocus,
    this.onBlur,
    this.onSelectionChanged,
  });

  final String value;
  final String? focusId;
  final bool enabled;
  final bool autofocus;
  final bool requestFocus;
  final bool clearFocus;
  final bool obscureText;
  final int? maxLines;
  final TextInputType? keyboardType;
  final TextInputAction? textInputAction;
  final _QuickjsUiSubmitFocusAction submitFocusAction;
  final InputDecoration decoration;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final ValueChanged<Map<String, Object?>>? onSubmitted;
  final ValueChanged<Map<String, Object?>>? onEditingComplete;
  final ValueChanged<Map<String, Object?>>? onFocus;
  final ValueChanged<Map<String, Object?>>? onBlur;
  final ValueChanged<Map<String, Object?>>? onSelectionChanged;

  @override
  State<_QuickjsUiTextField> createState() => _QuickjsUiTextFieldState();
}

final class _QuickjsUiTextFieldState extends State<_QuickjsUiTextField> {
  late final TextEditingController _controller;
  late final FocusNode _focusNode;
  TextSelection? _lastSelection;
  TextRange? _lastComposing;
  bool _syncingController = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.value);
    _lastSelection = _controller.selection;
    _lastComposing = _controller.value.composing;
    _controller.addListener(_handleControllerChange);
    _focusNode = FocusNode()..addListener(_handleFocusChange);
    if (widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
  }

  @override
  void didUpdateWidget(covariant _QuickjsUiTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.value != widget.value && _controller.text != widget.value) {
      _syncingController = true;
      _controller.value = TextEditingValue(
        text: widget.value,
        selection: TextSelection.collapsed(offset: widget.value.length),
      );
      _syncingController = false;
      _lastSelection = _controller.selection;
      _lastComposing = _controller.value.composing;
    }
    if (!oldWidget.requestFocus && widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
    if (!oldWidget.clearFocus && widget.clearFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _clearFocus());
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocusChange);
    _focusNode.dispose();
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (_focusNode.hasFocus) {
      widget.onFocus?.call(_snapshot());
    } else {
      widget.onBlur?.call(_snapshot());
    }
  }

  void _handleControllerChange() {
    if (_syncingController) {
      return;
    }
    final selection = _controller.selection;
    final composing = _controller.value.composing;
    if (selection == _lastSelection && composing == _lastComposing) {
      return;
    }
    _lastSelection = selection;
    _lastComposing = composing;
    widget.onSelectionChanged?.call(_snapshot());
  }

  void _requestFocus() {
    if (!mounted || !widget.enabled || _focusNode.hasFocus) {
      return;
    }
    _focusNode.requestFocus();
  }

  void _clearFocus() {
    if (!mounted || !_focusNode.hasFocus) {
      return;
    }
    _focusNode.unfocus();
  }

  void _handleEditingComplete() {
    widget.onEditingComplete?.call(_snapshot());
    final scope = FocusScope.of(context);
    switch (widget.submitFocusAction) {
      case _QuickjsUiSubmitFocusAction.none:
        break;
      case _QuickjsUiSubmitFocusAction.next:
        scope.nextFocus();
      case _QuickjsUiSubmitFocusAction.previous:
        scope.previousFocus();
      case _QuickjsUiSubmitFocusAction.unfocus:
        _focusNode.unfocus();
    }
  }

  Map<String, Object?> _snapshot() {
    final value = _controller.value;
    return <String, Object?>{
      'value': value.text,
      if (widget.focusId != null) 'focusId': widget.focusId,
      'selectionStart': value.selection.start,
      'selectionEnd': value.selection.end,
      'selectionBaseOffset': value.selection.baseOffset,
      'selectionExtentOffset': value.selection.extentOffset,
      'composingStart': value.composing.start,
      'composingEnd': value.composing.end,
    };
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
      onChanged: widget.onChanged == null
          ? null
          : (_) => widget.onChanged?.call(_snapshot()),
      onSubmitted: widget.onSubmitted == null
          ? null
          : (_) => widget.onSubmitted?.call(_snapshot()),
      onEditingComplete: _handleEditingComplete,
    );
  }
}

enum _QuickjsUiSubmitFocusAction { none, next, previous, unfocus }
