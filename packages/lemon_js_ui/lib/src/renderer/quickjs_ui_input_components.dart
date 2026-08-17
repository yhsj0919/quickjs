// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_control_style.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final JsUiComponentBuilderMap jsUiInputComponentBuilders =
    <String, JsUiComponentBuilder>{
      'TextField': _buildTextField,
      'TextFormField': _buildTextFormField,
      'Form': _buildForm,
      'Checkbox': _buildCheckbox,
      'Switch': _buildSwitch,
      'Slider': _buildSlider,
      'Radio': _buildRadio,
      'DropdownButton': _buildDropdownButton,
    };

Widget _buildTextField(JsUiRenderContext context, JsUiNode node) {
  return _buildTextInput(context, node, formField: false);
}

Widget _buildTextFormField(JsUiRenderContext context, JsUiNode node) {
  return _buildTextInput(context, node, formField: true);
}

Widget _buildTextInput(
  JsUiRenderContext context,
  JsUiNode node, {
  required bool formField,
}) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
  final onSubmitted = JsUiProps.event(node.props['onSubmitted']);
  final onFocus = JsUiProps.event(node.props['onFocus']);
  final onBlur = JsUiProps.event(node.props['onBlur']);
  final onEditingComplete = JsUiProps.event(node.props['onEditingComplete']);
  final onSelectionChanged = JsUiProps.event(node.props['onSelectionChanged']);
  final focusId = JsUiProps.string(node.props['focusId']);
  final enabled = JsUiProps.boolValue(node.props['enabled']) ?? true;
  final controlStyle = JsUiControlStyle.from(
    context,
    node.props['stateStyles'],
  );
  return JsUiControlStateBuilder(
    enabled: enabled,
    styles: <JsUiControlStyle>[controlStyle],
    transition: JsUiControlTransition.from(node.props['stateTransition']),
    builder: (buildContext, styles, focusNode) {
      final resolved = styles.single;
      return _JsUiTextField(
        formField: formField,
        value:
            JsUiProps.string(
              node.props['value'] ?? node.props['initialValue'],
              name: 'TextField value',
            ) ??
            '',
        focusId: focusId,
        enabled: enabled,
        autofocus:
            JsUiProps.boolValue(
              node.props['autofocus'] ?? node.props['focusOnMount'],
            ) ??
            false,
        requestFocus:
            JsUiProps.boolValue(
              node.props['requestFocus'] ?? node.props['autofocus'],
            ) ??
            false,
        clearFocus: JsUiProps.boolValue(node.props['clearFocus']) ?? false,
        obscureText: JsUiProps.boolValue(node.props['obscureText']) ?? false,
        maxLines: JsUiProps.intValue(node.props['maxLines']),
        keyboardType: JsUiProps.textInputType(node.props['keyboardType']),
        textInputAction: JsUiProps.textInputAction(
          node.props['textInputAction'],
        ),
        submitFocusAction: _submitFocusAction(
          node.props['submitFocusAction'],
          node.props['textInputAction'],
        ),
        style: context.textStyle(node.props['style']),
        decoration: _inputDecoration(context, node, resolved),
        focusNode: focusNode,
        onChanged: onChanged == null
            ? null
            : (value) => context.dispatch(
                onChanged,
                defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
                kind: JsUiEventKind.sample,
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
            : (value) =>
                  context.dispatch(<String, Object?>{...onFocus, ...value}),
        onBlur: onBlur == null
            ? null
            : (value) =>
                  context.dispatch(<String, Object?>{...onBlur, ...value}),
        onSelectionChanged: onSelectionChanged == null
            ? null
            : (value) => context.dispatch(
                onSelectionChanged,
                defaultCoalesceKey: jsUiEventKey(node, 'onSelectionChanged'),
                kind: JsUiEventKind.sample,
                payload: value,
              ),
      );
    },
  );
}

_JsUiSubmitFocusAction _submitFocusAction(
  Object? value,
  Object? textInputAction,
) {
  return switch (value) {
    null => switch (textInputAction) {
      'next' => _JsUiSubmitFocusAction.next,
      'previous' => _JsUiSubmitFocusAction.previous,
      _ => _JsUiSubmitFocusAction.none,
    },
    'none' => _JsUiSubmitFocusAction.none,
    'next' => _JsUiSubmitFocusAction.next,
    'previous' => _JsUiSubmitFocusAction.previous,
    'unfocus' => _JsUiSubmitFocusAction.unfocus,
    _ => throw const FormatException('Unknown quickjs_ui submitFocusAction'),
  };
}

Widget _buildForm(JsUiRenderContext context, JsUiNode node) {
  return Form(child: context.child(node) ?? const SizedBox.shrink());
}

Widget _buildCheckbox(JsUiRenderContext context, JsUiNode node) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
  return Checkbox(
    value: JsUiProps.boolValue(node.props['value']) ?? false,
    tristate: JsUiProps.boolValue(node.props['tristate']) ?? false,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatch(
            onChanged,
            defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
            kind: JsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildSwitch(JsUiRenderContext context, JsUiNode node) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
  final controlStyle = JsUiControlStyle.from(
    context,
    node.props['stateStyles'],
  );
  final thumbStyle = JsUiControlStyle.from(context, node.props['thumbStyle']);
  final trackStyle = JsUiControlStyle.from(context, node.props['trackStyle']);
  final overlayStyle = JsUiControlStyle.from(
    context,
    node.props['overlayStyle'],
  );
  final value = JsUiProps.boolValue(node.props['value']) ?? false;
  return JsUiControlStateBuilder(
    enabled: onChanged != null,
    selected: value,
    styles: <JsUiControlStyle>[
      controlStyle,
      thumbStyle,
      trackStyle,
      overlayStyle,
    ],
    transition: JsUiControlTransition.from(node.props['stateTransition']),
    builder: (buildContext, styles, focusNode) {
      final control = styles[0];
      final thumb = styles[1];
      final track = styles[2];
      final overlay = styles[3];
      return Switch(
        value: value,
        focusNode: focusNode,
        thumbColor: _allColor(
          thumb.color('color') ?? control.color('thumbColor'),
        ),
        trackColor: _allColor(
          track.color('color') ?? control.color('trackColor'),
        ),
        overlayColor: _allColor(
          overlay.color('color') ?? control.color('overlayColor'),
        ),
        trackOutlineColor: _allColor(
          track.color('borderColor') ?? control.color('trackOutlineColor'),
        ),
        trackOutlineWidth: _allDouble(
          track.number('borderWidth') ?? control.number('trackOutlineWidth'),
        ),
        onChanged: onChanged == null
            ? null
            : (value) => context.dispatch(
                onChanged,
                defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
                kind: JsUiEventKind.sample,
                payload: <String, Object?>{'value': value},
              ),
      );
    },
  );
}

Widget _buildSlider(JsUiRenderContext context, JsUiNode node) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
  final onChangeStart = JsUiProps.event(node.props['onChangeStart']);
  final onChangeEnd = JsUiProps.event(node.props['onChangeEnd']);
  final controlStyle = JsUiControlStyle.from(
    context,
    node.props['stateStyles'],
  );
  final thumbStyle = JsUiControlStyle.from(context, node.props['thumbStyle']);
  final trackStyle = JsUiControlStyle.from(context, node.props['trackStyle']);
  final overlayStyle = JsUiControlStyle.from(
    context,
    node.props['overlayStyle'],
  );
  final min = JsUiProps.doubleValue(node.props['min']) ?? 0;
  final max = JsUiProps.doubleValue(node.props['max']) ?? 1;
  final value = (JsUiProps.doubleValue(node.props['value']) ?? min).clamp(
    min,
    max,
  );
  return JsUiControlStateBuilder(
    enabled: onChanged != null,
    styles: <JsUiControlStyle>[
      controlStyle,
      thumbStyle,
      trackStyle,
      overlayStyle,
    ],
    transition: JsUiControlTransition.from(node.props['stateTransition']),
    builder: (buildContext, styles, focusNode) {
      final control = styles[0];
      final thumb = styles[1];
      final track = styles[2];
      final overlay = styles[3];
      final baseTheme = SliderTheme.of(buildContext);
      return SliderTheme(
        data: baseTheme.copyWith(
          activeTrackColor:
              track.color('activeColor') ?? control.color('activeTrackColor'),
          inactiveTrackColor:
              track.color('inactiveColor') ??
              control.color('inactiveTrackColor'),
          disabledActiveTrackColor:
              track.color('activeColor') ?? control.color('activeTrackColor'),
          disabledInactiveTrackColor:
              track.color('inactiveColor') ??
              control.color('inactiveTrackColor'),
          thumbColor: thumb.color('color') ?? control.color('thumbColor'),
          disabledThumbColor:
              thumb.color('color') ?? control.color('thumbColor'),
          overlayColor: overlay.color('color') ?? control.color('overlayColor'),
          valueIndicatorColor: control.color('valueIndicatorColor'),
          trackHeight: track.number('height') ?? control.number('trackHeight'),
          thumbShape: _sliderThumbShape(thumb, control),
          overlayShape: _sliderOverlayShape(overlay, control),
        ),
        child: Slider(
          focusNode: focusNode,
          min: min,
          max: max,
          value: value,
          divisions: JsUiProps.intValue(node.props['divisions']),
          label: JsUiProps.string(node.props['label']),
          onChanged: onChanged == null
              ? null
              : (next) => context.dispatch(
                  onChanged,
                  defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
                  kind: JsUiEventKind.sample,
                  payload: <String, Object?>{'value': next},
                ),
          onChangeStart: onChangeStart == null
              ? null
              : (next) => context.dispatch(
                  onChangeStart,
                  defaultCoalesceKey: jsUiEventKey(node, 'onChangeStart'),
                  payload: <String, Object?>{'value': next},
                ),
          onChangeEnd: onChangeEnd == null
              ? null
              : (next) => context.dispatch(
                  onChangeEnd,
                  defaultCoalesceKey: jsUiEventKey(node, 'onChangeEnd'),
                  payload: <String, Object?>{'value': next},
                ),
        ),
      );
    },
  );
}

WidgetStateProperty<Color?>? _allColor(Color? value) =>
    value == null ? null : WidgetStatePropertyAll<Color?>(value);

WidgetStateProperty<double?>? _allDouble(double? value) =>
    value == null ? null : WidgetStatePropertyAll<double?>(value);

SliderComponentShape? _sliderThumbShape(
  JsUiResolvedControlStyle thumb,
  JsUiResolvedControlStyle control,
) {
  final radius = thumb.number('radius') ?? control.number('thumbRadius');
  return radius == null
      ? null
      : RoundSliderThumbShape(enabledThumbRadius: radius);
}

SliderComponentShape? _sliderOverlayShape(
  JsUiResolvedControlStyle overlay,
  JsUiResolvedControlStyle control,
) {
  final radius = overlay.number('radius') ?? control.number('overlayRadius');
  return radius == null ? null : RoundSliderOverlayShape(overlayRadius: radius);
}

InputDecoration _inputDecoration(
  JsUiRenderContext context,
  JsUiNode node,
  JsUiResolvedControlStyle style,
) {
  final border = _inputBorder(style);
  return InputDecoration(
    labelText: JsUiProps.string(node.props['labelText']),
    hintText: JsUiProps.string(node.props['hintText']),
    helperText: JsUiProps.string(node.props['helperText']),
    errorText: JsUiProps.string(node.props['errorText']),
    icon: context.slot(node, 'leading'),
    prefix: context.slot(node, 'prefix'),
    suffix: context.slot(node, 'suffix'),
    suffixIcon: context.slot(node, 'trailing'),
    filled: style.has('fillColor'),
    fillColor: style.color('fillColor'),
    hoverColor: Colors.transparent,
    enabledBorder: border,
    focusedBorder: border,
    disabledBorder: border,
    errorBorder: border,
    focusedErrorBorder: border,
  );
}

InputBorder? _inputBorder(JsUiResolvedControlStyle style) {
  if (!style.has('borderColor') &&
      !style.has('borderWidth') &&
      !style.has('borderRadius')) {
    return null;
  }
  final borderRadius = style.borderRadius('borderRadius');
  return OutlineInputBorder(
    borderRadius: borderRadius is BorderRadius
        ? borderRadius
        : BorderRadius.zero,
    borderSide: BorderSide(
      color: style.color('borderColor') ?? Colors.transparent,
      width: style.number('borderWidth') ?? 1,
    ),
  );
}

Widget _buildRadio(JsUiRenderContext context, JsUiNode node) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
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
        : (value) => context.dispatch(
            onChanged,
            defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
            kind: JsUiEventKind.sample,
            payload: <String, Object?>{'value': value},
          ),
  );
}

Widget _buildDropdownButton(JsUiRenderContext context, JsUiNode node) {
  final onChanged = JsUiProps.event(node.props['onChanged']);
  final items = _dropdownItems(node.props['items']);
  final value = node.props['value'];
  final hint = JsUiProps.string(node.props['hint']);
  return DropdownButton<Object?>(
    value: items.any((item) => item.value == value) ? value : null,
    isExpanded: JsUiProps.boolValue(node.props['isExpanded']) ?? false,
    hint: hint == null ? null : Text(hint),
    items: items,
    onChanged: onChanged == null
        ? null
        : (value) => context.dispatch(
            onChanged,
            defaultCoalesceKey: jsUiEventKey(node, 'onChanged'),
            kind: JsUiEventKind.sample,
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
      child: Text(JsUiProps.string(props['label']) ?? '$itemValue'),
    );
  }
  return DropdownMenuItem<Object?>(value: value, child: Text('$value'));
}

final class _JsUiTextField extends StatefulWidget {
  const _JsUiTextField({
    required this.formField,
    required this.value,
    required this.focusId,
    required this.enabled,
    required this.autofocus,
    required this.requestFocus,
    required this.clearFocus,
    required this.obscureText,
    required this.decoration,
    required this.style,
    required this.focusNode,
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

  final bool formField;

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
  final _JsUiSubmitFocusAction submitFocusAction;
  final InputDecoration decoration;
  final TextStyle? style;
  final FocusNode focusNode;
  final ValueChanged<Map<String, Object?>>? onChanged;
  final ValueChanged<Map<String, Object?>>? onSubmitted;
  final ValueChanged<Map<String, Object?>>? onEditingComplete;
  final ValueChanged<Map<String, Object?>>? onFocus;
  final ValueChanged<Map<String, Object?>>? onBlur;
  final ValueChanged<Map<String, Object?>>? onSelectionChanged;

  @override
  State<_JsUiTextField> createState() => _JsUiTextFieldState();
}

final class _JsUiTextFieldState extends State<_JsUiTextField> {
  late final TextEditingController _controller;
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
    widget.focusNode.addListener(_handleFocusChange);
    if (widget.requestFocus) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _requestFocus());
    }
  }

  @override
  void didUpdateWidget(covariant _JsUiTextField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.focusNode != widget.focusNode) {
      oldWidget.focusNode.removeListener(_handleFocusChange);
      widget.focusNode.addListener(_handleFocusChange);
    }
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
    widget.focusNode.removeListener(_handleFocusChange);
    _controller.removeListener(_handleControllerChange);
    _controller.dispose();
    super.dispose();
  }

  void _handleFocusChange() {
    if (widget.focusNode.hasFocus) {
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
    if (!mounted || !widget.enabled || widget.focusNode.hasFocus) {
      return;
    }
    widget.focusNode.requestFocus();
  }

  void _clearFocus() {
    if (!mounted || !widget.focusNode.hasFocus) {
      return;
    }
    widget.focusNode.unfocus();
  }

  void _handleEditingComplete() {
    widget.onEditingComplete?.call(_snapshot());
    final scope = FocusScope.of(context);
    switch (widget.submitFocusAction) {
      case _JsUiSubmitFocusAction.none:
        break;
      case _JsUiSubmitFocusAction.next:
        scope.nextFocus();
      case _JsUiSubmitFocusAction.previous:
        scope.previousFocus();
      case _JsUiSubmitFocusAction.unfocus:
        widget.focusNode.unfocus();
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
    final handleEditingComplete =
        widget.onEditingComplete != null ||
        widget.submitFocusAction != _JsUiSubmitFocusAction.none;
    final onChanged = widget.onChanged == null
        ? null
        : (_) => widget.onChanged?.call(_snapshot());
    final onSubmitted = widget.onSubmitted == null
        ? null
        : (_) => widget.onSubmitted?.call(_snapshot());
    if (widget.formField) {
      return TextFormField(
        controller: _controller,
        focusNode: widget.focusNode,
        enabled: widget.enabled,
        autofocus: widget.autofocus,
        obscureText: widget.obscureText,
        maxLines: widget.maxLines,
        keyboardType: widget.keyboardType,
        textInputAction: widget.textInputAction,
        decoration: widget.decoration,
        style: widget.style,
        onChanged: onChanged,
        onFieldSubmitted: onSubmitted,
        onEditingComplete: handleEditingComplete
            ? _handleEditingComplete
            : null,
      );
    }
    return TextField(
      controller: _controller,
      focusNode: widget.focusNode,
      enabled: widget.enabled,
      autofocus: widget.autofocus,
      obscureText: widget.obscureText,
      maxLines: widget.maxLines,
      keyboardType: widget.keyboardType,
      textInputAction: widget.textInputAction,
      decoration: widget.decoration,
      style: widget.style,
      onChanged: onChanged,
      onSubmitted: onSubmitted,
      onEditingComplete: handleEditingComplete ? _handleEditingComplete : null,
    );
  }
}

enum _JsUiSubmitFocusAction { none, next, previous, unfocus }
