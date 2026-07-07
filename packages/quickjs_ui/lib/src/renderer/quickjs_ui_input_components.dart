import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_component_helpers.dart';
import 'quickjs_ui_gestures.dart';
import 'quickjs_ui_render_context.dart';

final QuickjsUiComponentBuilderMap quickjsUiInputComponentBuilders =
    <String, QuickjsUiComponentBuilder>{
      'TextField': _buildTextField,
      'Form': _buildForm,
      'Checkbox': _buildCheckbox,
      'Switch': _buildSwitch,
      'Slider': _buildSlider,
      'Radio': _buildRadio,
      'DropdownButton': _buildDropdownButton,
    };

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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onSelectionChanged'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
            kind: QuickjsUiEventKind.sample,
            payload: <String, Object?>{'value': next},
          ),
    onChangeEnd: onChangeEnd == null
        ? null
        : (next) => context.dispatchEvent(
            onChangeEnd,
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChangeEnd'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
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
            defaultCoalesceKey: quickjsUiEventKey(node, 'onChanged'),
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
    final handleEditingComplete =
        widget.onEditingComplete != null ||
        widget.submitFocusAction != _QuickjsUiSubmitFocusAction.none;
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
      onEditingComplete: handleEditingComplete ? _handleEditingComplete : null,
    );
  }
}

enum _QuickjsUiSubmitFocusAction { none, next, previous, unfocus }
