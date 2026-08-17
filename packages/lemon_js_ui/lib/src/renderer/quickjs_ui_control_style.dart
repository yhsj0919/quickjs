// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'dart:ui' show lerpDouble;

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import '../schema/quickjs_ui_props.dart';
import 'quickjs_ui_render_context.dart';

/// Resolves the shared JS control-state model to typed, interpolatable values.
///
/// State overrides are merged over `normal`. The most specific active state
/// wins in this order: disabled, pressed, selected, focused, hovered.
final class JsUiControlStyle {
  JsUiControlStyle._(this.context, Map<String, Object?> value)
    : _states = _parseStates(value),
      _keys = _styleKeys(value);

  factory JsUiControlStyle.from(JsUiRenderContext context, Object? value) {
    final root = JsUiProps.map(value, name: 'control style');
    return JsUiControlStyle._(
      context,
      JsUiProps.map(root['stateStyles'] ?? root, name: 'stateStyles'),
    );
  }

  final JsUiRenderContext context;
  final Map<String, Map<String, Object?>> _states;
  final Set<String> _keys;

  bool has(String key) => _keys.contains(key);

  bool get requiresStablePointerScale =>
      _states['pressed']?.containsKey('scale') == true;

  bool get requiresStablePointerOpacity =>
      _states['pressed']?.containsKey('opacity') == true;

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

  JsUiResolvedControlStyle resolve(Set<WidgetState> states) {
    return JsUiResolvedControlStyle(<String, Object?>{
      for (final key in _keys)
        key: _resolveValue(key, _valueOrVisualDefault(key, states)),
    });
  }

  Object? _valueOrVisualDefault(String key, Set<WidgetState> states) {
    final resolved = value(key, states);
    if (resolved != null) {
      return resolved;
    }
    return switch (key) {
      'scale' || 'opacity' => 1.0,
      _ => null,
    };
  }

  WidgetStateProperty<Color?>? color(String key) {
    if (!has(key)) return null;
    return WidgetStateProperty.resolveWith(
      (states) => context.color(value(key, states)),
    );
  }

  WidgetStateProperty<double?>? number(String key) {
    if (!has(key)) return null;
    return WidgetStateProperty.resolveWith(
      (states) => JsUiProps.doubleValue(value(key, states), name: key),
    );
  }

  WidgetStateProperty<EdgeInsetsGeometry?>? padding(String key) {
    if (!has(key)) return null;
    return WidgetStateProperty.resolveWith(
      (states) => context.edgeInsets(value(key, states)),
    );
  }

  WidgetStateProperty<TextStyle?>? textStyle(String key) {
    if (!has(key)) return null;
    return WidgetStateProperty.resolveWith(
      (states) => context.textStyle(value(key, states)),
    );
  }

  ButtonStyle buttonStyle(JsUiControlTransition transition) {
    final borderColor = color('borderColor');
    final borderWidth = number('borderWidth');
    final radius = has('borderRadius')
        ? WidgetStateProperty.resolveWith<OutlinedBorder?>((states) {
            return RoundedRectangleBorder(
              borderRadius:
                  context.borderRadius(value('borderRadius', states)) ??
                  BorderRadius.zero,
            );
          })
        : null;
    final side = borderColor == null && borderWidth == null
        ? null
        : WidgetStateProperty.resolveWith<BorderSide?>((states) {
            return BorderSide(
              color: borderColor?.resolve(states) ?? Colors.transparent,
              width: borderWidth?.resolve(states) ?? 1,
            );
          });
    return ButtonStyle(
      animationDuration: transition.duration,
      backgroundColor: color('backgroundColor'),
      foregroundColor: color('foregroundColor'),
      overlayColor: color('overlayColor'),
      shadowColor: color('shadowColor'),
      surfaceTintColor: color('surfaceTintColor'),
      elevation: number('elevation'),
      padding: padding('padding'),
      textStyle: textStyle('textStyle'),
      shape: radius,
      side: side,
    );
  }

  Object? _resolveValue(String key, Object? value) {
    if (_colorKeys.contains(key)) {
      return context.color(value);
    }
    if (_numberKeys.contains(key)) {
      return JsUiProps.doubleValue(value, name: key);
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
          name: JsUiProps.map(value[name], name: '$name state style'),
    };
  }

  static Set<String> _styleKeys(Map<String, Object?> value) {
    return <String>{
      for (final name in _stateNames)
        ...JsUiProps.map(value[name], name: '$name state style').keys,
    };
  }
}

/// A fully resolved visual state. Values are converted once when interaction
/// state changes and are then interpolated locally by Flutter's ticker.
@immutable
final class JsUiResolvedControlStyle {
  const JsUiResolvedControlStyle(this._values);

  final Map<String, Object?> _values;

  bool has(String key) => _values[key] != null;

  Color? color(String key) => _values[key] as Color?;

  double? number(String key) => _values[key] as double?;

  EdgeInsetsGeometry? padding(String key) =>
      _values[key] as EdgeInsetsGeometry?;

  TextStyle? textStyle(String key) => _values[key] as TextStyle?;

  BorderRadiusGeometry? borderRadius(String key) =>
      _values[key] as BorderRadiusGeometry?;

  Widget decorate(
    Widget child, {
    bool stableScaleTopology = false,
    bool stableOpacityTopology = false,
  }) {
    final opacity = (number('opacity') ?? 1).clamp(0.0, 1.0);
    final scale = number('scale') ?? 1;
    Widget result = child;
    if (stableScaleTopology || scale != 1) {
      result = Transform.scale(scale: scale, child: result);
    }
    if (stableOpacityTopology || opacity != 1) {
      result = Opacity(opacity: opacity, child: result);
    }
    return result;
  }

  static JsUiResolvedControlStyle lerp(
    JsUiResolvedControlStyle a,
    JsUiResolvedControlStyle b,
    double t,
  ) {
    final keys = <String>{...a._values.keys, ...b._values.keys};
    return JsUiResolvedControlStyle(<String, Object?>{
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
      other is JsUiResolvedControlStyle && mapEquals(_values, other._values);

  @override
  int get hashCode => Object.hashAll(
    _values.entries.map((entry) => Object.hash(entry.key, entry.value)),
  );
}

/// Shared duration and curve for native control-state transitions.
@immutable
final class JsUiControlTransition {
  const JsUiControlTransition({
    this.duration = const Duration(milliseconds: 140),
    this.curve = Curves.easeOutCubic,
  });

  factory JsUiControlTransition.from(Object? value) {
    if (value == false) {
      return const JsUiControlTransition(duration: Duration.zero);
    }
    final props = JsUiProps.map(value, name: 'stateTransition');
    return JsUiControlTransition(
      duration:
          JsUiProps.duration(
            props['durationMs'] ?? props['duration'],
            name: 'stateTransition duration',
          ) ??
          const Duration(milliseconds: 140),
      curve: JsUiProps.curve(props['curve'] ?? 'easeOutCubic'),
    );
  }

  final Duration duration;
  final Curve curve;
}

typedef JsUiControlTransitionWidgetBuilder =
    Widget Function(
      BuildContext context,
      List<JsUiResolvedControlStyle> styles,
      Widget? child,
    );

/// Animates one or more related visual styles as a single state transaction.
///
/// [TweenAnimationBuilder] retargets from the current sampled frame, so rapid
/// hover/press/focus changes do not jump back to a previous endpoint.
final class JsUiControlTransitionBuilder extends StatelessWidget {
  const JsUiControlTransitionBuilder({
    required this.styles,
    required this.states,
    required this.transition,
    required this.builder,
    this.child,
    super.key,
  });

  final List<JsUiControlStyle> styles;
  final Set<WidgetState> states;
  final JsUiControlTransition transition;
  final JsUiControlTransitionWidgetBuilder builder;
  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final target = _JsUiResolvedControlStyles(<JsUiResolvedControlStyle>[
      for (final style in styles) style.resolve(states),
    ]);
    final disableAnimations =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final duration = disableAnimations ? Duration.zero : transition.duration;
    if (duration == Duration.zero) {
      return builder(context, target.values, child);
    }
    return TweenAnimationBuilder<_JsUiResolvedControlStyles>(
      tween: _JsUiControlStylesTween(end: target),
      duration: duration,
      curve: transition.curve,
      child: child,
      builder: (context, value, child) => builder(context, value.values, child),
    );
  }
}

typedef JsUiControlInteractionWidgetBuilder =
    Widget Function(
      BuildContext context,
      Set<WidgetState> states,
      FocusNode focusNode,
    );

typedef JsUiControlInteractionScopeWidgetBuilder =
    Widget Function(BuildContext context, JsUiControlInteraction interaction);

final class JsUiControlInteraction {
  const JsUiControlInteraction({
    required this.states,
    required this.statesController,
    required this.focusNode,
    required this.setHovered,
    required this.setPressed,
  });

  final Set<WidgetState> states;
  final WidgetStatesController statesController;
  final FocusNode focusNode;
  final ValueChanged<bool> setHovered;
  final ValueChanged<bool> setPressed;
}

final class JsUiControlInteractionScope extends StatefulWidget {
  const JsUiControlInteractionScope({
    required this.enabled,
    required this.builder,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final bool selected;
  final JsUiControlInteractionScopeWidgetBuilder builder;

  @override
  State<JsUiControlInteractionScope> createState() =>
      _JsUiControlInteractionScopeState();
}

final class _JsUiControlInteractionScopeState
    extends State<JsUiControlInteractionScope> {
  final FocusNode _focusNode = FocusNode();
  late final WidgetStatesController _statesController;
  bool _hovered = false;
  bool _focused = false;
  bool _pressed = false;

  @override
  void initState() {
    super.initState();
    _statesController = WidgetStatesController(<WidgetState>{
      if (!widget.enabled) WidgetState.disabled,
    });
    _statesController.addListener(_handleNativeStates);
    _focusNode.addListener(_handleFocus);
  }

  @override
  void didUpdateWidget(covariant JsUiControlInteractionScope oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled && (_hovered || _focused || _pressed)) {
      _hovered = false;
      _focused = false;
      _pressed = false;
    }
    _statesController.update(WidgetState.disabled, !widget.enabled);
  }

  @override
  void dispose() {
    _statesController.removeListener(_handleNativeStates);
    _statesController.dispose();
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
    return widget.builder(
      context,
      JsUiControlInteraction(
        states: states,
        statesController: _statesController,
        focusNode: _focusNode,
        setHovered: (value) => _setState(hovered: value),
        setPressed: (value) => _setState(pressed: value),
      ),
    );
  }

  void _handleFocus() {
    _setState(focused: _focusNode.hasFocus);
  }

  void _handleNativeStates() {
    final states = _statesController.value;
    _setState(
      hovered: states.contains(WidgetState.hovered),
      focused: states.contains(WidgetState.focused),
      pressed: states.contains(WidgetState.pressed),
    );
  }

  void _setState({bool? hovered, bool? focused, bool? pressed}) {
    final nextHovered = widget.enabled && (hovered ?? _hovered);
    final nextFocused = widget.enabled && (focused ?? _focused);
    final nextPressed = widget.enabled && (pressed ?? _pressed);
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

/// Publishes interaction state only when it changes. Animation frames are
/// deliberately handled by descendants so stable control subtrees can be
/// passed through [TweenAnimationBuilder.child].
final class JsUiControlInteractionBuilder extends StatelessWidget {
  const JsUiControlInteractionBuilder({
    required this.enabled,
    required this.builder,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final bool selected;
  final JsUiControlInteractionWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return JsUiControlInteractionScope(
      enabled: enabled,
      selected: selected,
      builder: (context, interaction) => MouseRegion(
        opaque: false,
        onEnter: enabled ? (_) => interaction.setHovered(true) : null,
        onExit: enabled ? (_) => interaction.setHovered(false) : null,
        child: Listener(
          behavior: HitTestBehavior.translucent,
          onPointerDown: enabled ? (_) => interaction.setPressed(true) : null,
          onPointerUp: enabled ? (_) => interaction.setPressed(false) : null,
          onPointerCancel: enabled
              ? (_) => interaction.setPressed(false)
              : null,
          child: builder(context, interaction.states, interaction.focusNode),
        ),
      ),
    );
  }
}

typedef JsUiControlStateWidgetBuilder =
    Widget Function(
      BuildContext context,
      List<JsUiResolvedControlStyle> styles,
      FocusNode focusNode,
    );

/// Supplies native hover, focus, press, selected and disabled states to every
/// control through one lifecycle-safe interaction boundary.
///
/// The native control is rebuilt once when interaction state changes, then
/// passed through [TweenAnimationBuilder.child]. Animation ticks rebuild only
/// the lightweight visual decorators, never the Switch, Slider or TextField
/// subtree.
final class JsUiControlStateBuilder extends StatelessWidget {
  const JsUiControlStateBuilder({
    required this.enabled,
    required this.styles,
    required this.transition,
    required this.builder,
    this.selected = false,
    super.key,
  });

  final bool enabled;
  final bool selected;
  final List<JsUiControlStyle> styles;
  final JsUiControlTransition transition;
  final JsUiControlStateWidgetBuilder builder;

  @override
  Widget build(BuildContext context) {
    return JsUiControlInteractionBuilder(
      enabled: enabled,
      selected: selected,
      builder: (context, states, focusNode) {
        final resolvedStyles = <JsUiResolvedControlStyle>[
          for (final style in styles) style.resolve(states),
        ];
        return JsUiControlTransitionBuilder(
          styles: styles,
          states: states,
          transition: transition,
          child: RepaintBoundary(
            child: builder(context, resolvedStyles, focusNode),
          ),
          builder: (context, styles, child) => styles.first.decorate(
            child!,
            stableScaleTopology: this.styles.first.requiresStablePointerScale,
            stableOpacityTopology:
                this.styles.first.requiresStablePointerOpacity,
          ),
        );
      },
    );
  }
}

@immutable
final class _JsUiResolvedControlStyles {
  const _JsUiResolvedControlStyles(this.values);

  final List<JsUiResolvedControlStyle> values;

  static _JsUiResolvedControlStyles lerp(
    _JsUiResolvedControlStyles a,
    _JsUiResolvedControlStyles b,
    double t,
  ) {
    assert(a.values.length == b.values.length);
    return _JsUiResolvedControlStyles(<JsUiResolvedControlStyle>[
      for (var index = 0; index < a.values.length; index += 1)
        JsUiResolvedControlStyle.lerp(a.values[index], b.values[index], t),
    ]);
  }

  @override
  bool operator ==(Object other) =>
      other is _JsUiResolvedControlStyles && listEquals(values, other.values);

  @override
  int get hashCode => Object.hashAll(values);
}

final class _JsUiControlStylesTween extends Tween<_JsUiResolvedControlStyles> {
  _JsUiControlStylesTween({required _JsUiResolvedControlStyles end})
    : super(end: end);

  @override
  _JsUiResolvedControlStyles lerp(double t) {
    return _JsUiResolvedControlStyles.lerp(begin!, end!, t);
  }
}

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
