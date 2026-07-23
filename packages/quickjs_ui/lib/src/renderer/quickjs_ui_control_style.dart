import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

/// Resolves the shared JS control-state model to typed, interpolatable values.
///
/// State overrides are merged over `normal`. The most specific active state
/// wins in this order: disabled, pressed, selected, focused, hovered.
final class QuickjsUiControlStyle {
  QuickjsUiControlStyle._(this.context, Map<String, Object?> value)
    : _states = _parseStates(value),
      _keys = _styleKeys(value);

  factory QuickjsUiControlStyle.from(
    QuickjsUiRenderContext context,
    Object? value,
  ) {
    final root = QuickjsUiProps.map(value, name: 'control style');
    return QuickjsUiControlStyle._(
      context,
      QuickjsUiProps.map(root['stateStyles'] ?? root, name: 'stateStyles'),
    );
  }

  final QuickjsUiRenderContext context;
  final Map<String, Map<String, Object?>> _states;
  final Set<String> _keys;

  Object? value(String key, Set<WidgetState> states) {
    Object? result = _states['normal']?[key];
    for (final entry in _stateOrder) {
      if (states.contains(entry.$1)) {
        final style = _states[entry.$2];
        if (style != null && style.containsKey(key)) {
          result = style[key];
        }
      }
    }
    return result;
  }

  QuickjsUiResolvedControlStyle resolve(Set<WidgetState> states) {
    return QuickjsUiResolvedControlStyle(<String, Object?>{
      for (final key in _keys) key: _resolveValue(key, value(key, states)),
    });
  }

  Object? _resolveValue(String key, Object? value) {
    if (_colorKeys.contains(key)) {
      return context.color(value);
    }
    if (_numberKeys.contains(key)) {
      return QuickjsUiProps.doubleValue(value, name: key);
    }
    return switch (key) {
      'padding' => context.edgeInsets(value),
      'textStyle' => context.textStyle(value),
      'borderRadius' => context.borderRadius(value),
      _ => value,
    };
  }

  static Map<String, Map<String, Object?>> _parseStates(
    Map<String, Object?> value,
  ) {
    return <String, Map<String, Object?>>{
      for (final name in _stateNames)
        if (value[name] != null)
          name: QuickjsUiProps.map(value[name], name: '$name state style'),
    };
  }

  static Set<String> _styleKeys(Map<String, Object?> value) {
    return <String>{
      for (final name in _stateNames)
        ...QuickjsUiProps.map(value[name], name: '$name state style').keys,
    };
  }
}

/// A fully resolved visual state. Values are converted once when interaction
/// state changes and are then interpolated locally by Flutter's ticker.
@immutable
final class QuickjsUiResolvedControlStyle {
  const QuickjsUiResolvedControlStyle(this._values);

  final Map<String, Object?> _values;

  bool has(String key) => _values[key] != null;

  Color? color(String key) => _values[key] as Color?;

  double? number(String key) => _values[key] as double?;

  EdgeInsetsGeometry? padding(String key) =>
      _values[key] as EdgeInsetsGeometry?;

  TextStyle? textStyle(String key) => _values[key] as TextStyle?;

  BorderRadiusGeometry? borderRadius(String key) =>
      _values[key] as BorderRadiusGeometry?;

  ButtonStyle buttonStyle() {
    final borderColor = color('borderColor');
    final borderWidth = number('borderWidth');
    final radius = borderRadius('borderRadius');
    return ButtonStyle(
      animationDuration: Duration.zero,
      backgroundColor: _all(color('backgroundColor')),
      foregroundColor: _all(color('foregroundColor')),
      overlayColor: _all(color('overlayColor')),
      shadowColor: _all(color('shadowColor')),
      surfaceTintColor: _all(color('surfaceTintColor')),
      elevation: _all(number('elevation')),
      padding: _all(padding('padding')),
      textStyle: _all(textStyle('textStyle')),
      shape: radius == null
          ? null
          : WidgetStatePropertyAll<OutlinedBorder>(
              RoundedRectangleBorder(borderRadius: radius),
            ),
      side: borderColor == null && borderWidth == null
          ? null
          : WidgetStatePropertyAll<BorderSide>(
              BorderSide(
                color: borderColor ?? Colors.transparent,
                width: borderWidth ?? 1,
              ),
            ),
    );
  }

  Widget decorate(Widget child) {
    final opacity = (number('opacity') ?? 1).clamp(0.0, 1.0);
    final scale = number('scale') ?? 1;
    Widget result = child;
    if (scale != 1) {
      result = Transform.scale(scale: scale, child: result);
    }
    if (opacity != 1) {
      result = Opacity(opacity: opacity, child: result);
    }
    return result;
  }

  static QuickjsUiResolvedControlStyle lerp(
    QuickjsUiResolvedControlStyle a,
    QuickjsUiResolvedControlStyle b,
    double t,
  ) {
    final keys = <String>{...a._values.keys, ...b._values.keys};
    return QuickjsUiResolvedControlStyle(<String, Object?>{
      for (final key in keys)
        key: _lerpValue(a._values[key], b._values[key], t),
    });
  }

  static Object? _lerpValue(Object? a, Object? b, double t) {
    if (a == null && b == null) return null;
    if (a is Color? && b is Color?) {
      return Color.lerp(a, b, t);
    }
    if (a is num? && b is num?) {
      if (a == null) return b?.toDouble();
      if (b == null) return a.toDouble();
      return lerpDouble(a.toDouble(), b.toDouble(), t);
    }
    if (a is EdgeInsetsGeometry? && b is EdgeInsetsGeometry?) {
      return EdgeInsetsGeometry.lerp(a, b, t);
    }
    if (a is TextStyle? && b is TextStyle?) {
      return TextStyle.lerp(a, b, t);
    }
    if (a is BorderRadiusGeometry? && b is BorderRadiusGeometry?) {
      return BorderRadiusGeometry.lerp(a, b, t);
    }
    return t < 0.5 ? a : b;
  }

  @override
  bool operator ==(Object other) =>
      other is QuickjsUiResolvedControlStyle &&
      mapEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAll(
    _values.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// Shared duration and curve for native control-state transitions.
@immutable
final class QuickjsUiControlTransition {
  const QuickjsUiControlTransition({
    this.duration = const Duration(milliseconds: 140),
    this.curve = Curves.easeOutCubic,
  });

  factory QuickjsUiControlTransition.from(Object? value) {
    if (value == false) {
      return const QuickjsUiControlTransition(duration: Duration.zero);
    }
    final props = QuickjsUiProps.map(value, name: 'stateTransition');
    return QuickjsUiControlTransition(
      duration:
          QuickjsUiProps.duration(
            props['durationMs'] ?? props['duration'],
            name: 'stateTransition duration',
          ) ??
          const Duration(milliseconds: 140),
      curve: QuickjsUiProps.curve(props['curve'] ?? 'easeOutCubic'),
    );
  }

  final Duration duration;
  final Curve curve;
}

typedef QuickjsUiControlTransitionWidgetBuilder =
    Widget Function(
      BuildContext context,
      List<QuickjsUiResolvedControlStyle> styles,
    );

/// Animates one or more related visual styles as a single state transaction.
///
/// [TweenAnimationBuilder] retargets from the current sampled frame, so rapid
/// hover/press/focus changes do not jump back to a previous endpoint.
final class QuickjsUiControlTransitionBuilder extends StatelessWidget {
  const QuickjsUiControlTransitionBuilder({
    required this.styles,
    required this.states,
    required this.transition,
    required this.builder,
    super.key,
  });

  final List<QuickjsUiControlStyle> styles;
  final Set<WidgetState> states;
  final QuickjsUiControlTransition transition;
  final QuickjsUiControlTransitionWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    final target = _QuickjsUiResolvedControlStyles(
      <QuickjsUiResolvedControlStyle>[
        for (final style in styles) style.resolve(states),
      ],
    );
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations ? Duration.zero : transition.duration;
    if (duration == Duration.zero) {
      return builder(context, target.values);
    }
    return TweenAnimationBuilder<_QuickjsUiResolvedControlStyles>(
      tween: _QuickjsUiControlStylesTween(end: target),
      duration: duration,
      curve: transition.curve,
      builder: (context, value, _) => builder(context, value.values),
    );
  }
}

typedef QuickjsUiControlStateWidgetBuilder =
    Widget Function(
      BuildContext context,
      List<QuickjsUiResolvedControlStyle> styles,
      FocusNode focusNode,
    );

/// Supplies native hover, focus, press, selected and disabled states to every
/// control through one lifecycle-safe interaction boundary.
final class QuickjsUiControlStateBuilder extends StatefulWidget {
  const QuickjsUiControlStateBuilder({
    required this.enabled,
    required this.styles,
    required this.transition,
    required this.builder,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final bool selected;
  final List<QuickjsUiControlStyle> styles;
  final QuickjsUiControlTransition transition;
  final QuickjsUiControlStateWidgetBuilder builder;

  @override
  State<QuickjsUiControlStateBuilder> createState() =>
      _QuickjsUiControlStateBuilderState();
}

final class _QuickjsUiControlStateBuilderState
    extends State<QuickjsUiControlStateBuilder> {
  final FocusNode _focusNode = FocusNode();
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant QuickjsUiControlStateBuilder oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _focused || _pressed)) {
      _hovered = false;
      _focused = false;
      _pressed = false;
    }
  }

  @override
  void dispose() {
    _focusNode.removeListener(_handleFocus);
    _focusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final states = <WidgetState>{
      if (!widget.enabled) WidgetState.disabled,
      if (widget.selected) WidgetState.selected,
      if (_hovered) WidgetState.hovered,
      if (_focused) WidgetState.focused,
      if (_pressed) WidgetState.pressed,
    };
    return MouseRegion(
      onEnter: widget.enabled ? (_) => _setState(hovered: true) : null,
      onExit: widget.enabled ? (_) => _setState(hovered: false) : null,
      child: Listener(
        behavior: HitTestBehavior.translucent,
        onPointerDown: widget.enabled ? (_) => _setState(pressed: true) : null,
        onPointerUp: widget.enabled ? (_) => _setState(pressed: false) : null,
        onPointerCancel: widget.enabled
            ? (_) => _setState(pressed: false)
            : null,
        child: QuickjsUiControlTransitionBuilder(
          styles: widget.styles,
          states: states,
          transition: widget.transition,
          builder: (context, styles) =>
              widget.builder(context, styles, _focusNode),
        ),
      ),
    );
  }

  void _handleFocus() {
    _setState(focused: _focusNode.hasFocus);
  }

  void _setState({bool? hovered, bool? focused, bool? pressed}) {
    final nextHovered = hovered ?? _hovered;
    final nextFocused = focused ?? _focused;
    final nextPressed = pressed ?? _pressed;
    if (nextHovered == _hovered &&
        nextFocused == _focused &&
        nextPressed == _pressed) {
      return;
    }
    setState(() {
      _hovered = nextHovered;
      _focused = nextFocused;
      _pressed = nextPressed;
    });
  }
}

@immutable
final class _QuickjsUiResolvedControlStyles {
  const _QuickjsUiResolvedControlStyles(this.values);

  final List<QuickjsUiResolvedControlStyle> values;

  static _QuickjsUiResolvedControlStyles lerp(
    _QuickjsUiResolvedControlStyles a,
    _QuickjsUiResolvedControlStyles b,
    double t,
  ) {
    assert(a.values.length == b.values.length);
    return _QuickjsUiResolvedControlStyles(<QuickjsUiResolvedControlStyle>[
      for (var index = 0; index < a.values.length; index += 1)
        QuickjsUiResolvedControlStyle.lerp(a.values[index], b.values[index], t),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is _QuickjsUiResolvedControlStyles &&
      listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

final class _QuickjsUiControlStylesTween
    extends Tween<_QuickjsUiResolvedControlStyles> {
  _QuickjsUiControlStylesTween({required _QuickjsUiResolvedControlStyles end})
    : super(end: end);

  @override
  _QuickjsUiResolvedControlStyles lerp(double t) {
    return _QuickjsUiResolvedControlStyles.lerp(begin!, end!, t);
  }
}

WidgetStateProperty<T>? _all<T>(T? value) =>
    value == null ? null : WidgetStatePropertyAll<T>(value);

const _stateNames = <String>[
  'normal',
  'hovered',
  'focused',
  'selected',
  'pressed',
  'disabled',
];

const _stateOrder = <(WidgetState, String)>[
  (WidgetState.hovered, 'hovered'),
  (WidgetState.focused, 'focused'),
  (WidgetState.selected, 'selected'),
  (WidgetState.pressed, 'pressed'),
  (WidgetState.disabled, 'disabled'),
];

const _colorKeys = <String>{
  'backgroundColor',
  'foregroundColor',
  'overlayColor',
  'shadowColor',
  'surfaceTintColor',
  'borderColor',
  'fillColor',
  'thumbColor',
  'trackColor',
  'activeTrackColor',
  'inactiveTrackColor',
  'trackOutlineColor',
  'valueIndicatorColor',
  'color',
  'activeColor',
  'inactiveColor',
};

const _numberKeys = <String>{
  'borderWidth',
  'elevation',
  'trackOutlineWidth',
  'trackHeight',
  'thumbRadius',
  'overlayRadius',
  'height',
  'radius',
  'scale',
  'opacity',
};
