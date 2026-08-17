import 'package:flutter/material.dart';
import 'package:lemon_js/lemon_js.dart' show JsUndefined;

/// Resolves a protocol value to a themed Flutter color.
typedef JsUiColorResolver = Color? Function(Object? value);

/// Resolves a protocol value to a themed Flutter text style.
typedef JsUiTextStyleResolver = TextStyle? Function(Object? value);

/// Resolves a protocol value to a themed numeric token.
typedef JsUiNumberResolver = double? Function(Object? value);

/// Strict converters from JSON-compatible component props to Flutter values.
final class JsUiProps {
  const JsUiProps._();

  /// Reads an object-valued property, returning an empty map for `null`.
  static Map<String, Object?> map(Object? value, {String name = 'property'}) {
    if (value == null) {
      return const <String, Object?>{};
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>('$key', value),
      );
    }
    throw FormatException('quickjs_ui $name must be an object');
  }

  /// Reads an optional event descriptor.
  static Map<String, Object?>? event(Object? value) {
    if (value == null || value is JsUndefined) {
      return null;
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>('$key', value),
      );
    }
    throw const FormatException('quickjs_ui event must be an object');
  }

  /// Reads an optional string property.
  static String? string(Object? value, {String name = 'string property'}) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be a string');
  }

  /// Reads an optional numeric property as a double.
  static double? doubleValue(Object? value, {String name = 'number property'}) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw FormatException('quickjs_ui $name must be a number');
  }

  /// Reads a number, consulting [resolveNumber] before literal conversion.
  static double? number(
    Object? value, {
    String name = 'number property',
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) {
      return null;
    }
    final resolved = resolveNumber?.call(value);
    if (resolved != null) {
      return resolved;
    }
    return doubleValue(value, name: name);
  }

  /// Reads an optional integer property.
  static int? intValue(Object? value, {String name = 'int property'}) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be an int');
  }

  /// Reads an optional boolean property.
  static bool? boolValue(Object? value, {String name = 'bool property'}) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be a bool');
  }

  /// Reads an opacity clamped to the inclusive range from zero to one.
  static double opacity(Object? value) {
    return (doubleValue(value, name: 'opacity') ?? 1).clamp(0, 1).toDouble();
  }

  /// Reads an optional non-negative millisecond duration.
  static Duration? duration(Object? value, {String name = 'duration'}) {
    if (value == null) {
      return null;
    }
    if (value is! num || value < 0) {
      throw FormatException('quickjs_ui $name must be a non-negative number');
    }
    return Duration(milliseconds: value.round());
  }

  /// Reads a supported animation curve, defaulting to ease-in-out.
  static Curve curve(Object? value) {
    return switch (value) {
      null => Curves.easeInOut,
      'linear' => Curves.linear,
      'easeIn' => Curves.easeIn,
      'easeOut' => Curves.easeOut,
      'easeInOut' => Curves.easeInOut,
      'fastOutSlowIn' => Curves.fastOutSlowIn,
      'easeOutCubic' => Curves.easeOutCubic,
      _ => throw const FormatException('Unknown quickjs_ui animation curve'),
    };
  }

  /// Reads an integer, hex, or theme-resolved color.
  static Color? color(Object? value, {JsUiColorResolver? resolveColor}) {
    if (value == null) {
      return null;
    }
    final resolved = resolveColor?.call(value);
    if (resolved != null) {
      return resolved;
    }
    if (value is int) {
      return Color(value);
    }
    if (value is num) {
      return Color(value.toInt());
    }
    if (value is String) {
      var hex = value.trim();
      if (hex.startsWith('#')) {
        hex = hex.substring(1);
      } else if (hex.startsWith('0x') || hex.startsWith('0X')) {
        hex = hex.substring(2);
      }
      if (hex.length == 6) {
        return Color(int.parse('ff$hex', radix: 16));
      }
      if (hex.length == 8) {
        return Color(int.parse(hex, radix: 16));
      }
    }
    throw const FormatException(
      'quickjs_ui color property must be an int or hex string',
    );
  }

  /// Reads scalar or per-edge padding and margin values.
  static EdgeInsetsGeometry? edgeInsets(
    Object? value, {
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) {
      return null;
    }
    if (value is num || value is String) {
      final scalar = number(
        value,
        name: 'edge inset value',
        resolveNumber: resolveNumber,
      );
      if (scalar != null) {
        return EdgeInsets.all(scalar);
      }
    }
    final props = map(value, name: 'edge inset property');
    final all =
        number(
          props['all'],
          name: 'edge inset all',
          resolveNumber: resolveNumber,
        ) ??
        number(
          props['value'],
          name: 'edge inset value',
          resolveNumber: resolveNumber,
        );
    if (all != null) {
      return EdgeInsets.all(all);
    }
    final horizontal = number(
      props['horizontal'],
      name: 'edge inset horizontal',
      resolveNumber: resolveNumber,
    );
    final vertical = number(
      props['vertical'],
      name: 'edge inset vertical',
      resolveNumber: resolveNumber,
    );
    return EdgeInsets.fromLTRB(
      number(
            props['left'],
            name: 'edge inset left',
            resolveNumber: resolveNumber,
          ) ??
          horizontal ??
          0,
      number(
            props['top'],
            name: 'edge inset top',
            resolveNumber: resolveNumber,
          ) ??
          vertical ??
          0,
      number(
            props['right'],
            name: 'edge inset right',
            resolveNumber: resolveNumber,
          ) ??
          horizontal ??
          0,
      number(
            props['bottom'],
            name: 'edge inset bottom',
            resolveNumber: resolveNumber,
          ) ??
          vertical ??
          0,
    );
  }

  /// Reads scalar or per-corner border radii.
  static BorderRadiusGeometry? borderRadius(
    Object? value, {
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) {
      return null;
    }
    if (value is num || value is String) {
      final scalar = number(
        value,
        name: 'border radius value',
        resolveNumber: resolveNumber,
      );
      if (scalar != null) {
        return BorderRadius.circular(scalar);
      }
    }
    final props = map(value, name: 'border radius property');
    final all =
        number(
          props['all'],
          name: 'border radius all',
          resolveNumber: resolveNumber,
        ) ??
        number(
          props['radius'],
          name: 'border radius radius',
          resolveNumber: resolveNumber,
        );
    if (all != null) {
      return BorderRadius.circular(all);
    }
    return BorderRadius.only(
      topLeft: Radius.circular(
        number(
              props['topLeft'],
              name: 'border radius topLeft',
              resolveNumber: resolveNumber,
            ) ??
            0,
      ),
      topRight: Radius.circular(
        number(
              props['topRight'],
              name: 'border radius topRight',
              resolveNumber: resolveNumber,
            ) ??
            0,
      ),
      bottomLeft: Radius.circular(
        number(
              props['bottomLeft'],
              name: 'border radius bottomLeft',
              resolveNumber: resolveNumber,
            ) ??
            0,
      ),
      bottomRight: Radius.circular(
        number(
              props['bottomRight'],
              name: 'border radius bottomRight',
              resolveNumber: resolveNumber,
            ) ??
            0,
      ),
    );
  }

  /// Reads a supported alignment name.
  static AlignmentGeometry? alignment(Object? value) {
    return switch (value) {
      null => null,
      'topLeft' => Alignment.topLeft,
      'topCenter' => Alignment.topCenter,
      'topRight' => Alignment.topRight,
      'centerLeft' => Alignment.centerLeft,
      'center' => Alignment.center,
      'centerRight' => Alignment.centerRight,
      'bottomLeft' => Alignment.bottomLeft,
      'bottomCenter' => Alignment.bottomCenter,
      'bottomRight' => Alignment.bottomRight,
      _ => throw const FormatException('Unknown quickjs_ui alignment'),
    };
  }

  /// Reads a supported image fitting mode.
  static BoxFit? boxFit(Object? value) {
    return switch (value) {
      null => null,
      'fill' => BoxFit.fill,
      'contain' => BoxFit.contain,
      'cover' => BoxFit.cover,
      'fitWidth' => BoxFit.fitWidth,
      'fitHeight' => BoxFit.fitHeight,
      'none' => BoxFit.none,
      'scaleDown' => BoxFit.scaleDown,
      _ => throw const FormatException('Unknown quickjs_ui BoxFit'),
    };
  }

  /// Reads a layout axis, defaulting to vertical.
  static Axis axis(Object? value) {
    return switch (value) {
      null => Axis.vertical,
      'vertical' => Axis.vertical,
      'horizontal' => Axis.horizontal,
      _ => throw const FormatException('Unknown quickjs_ui axis'),
    };
  }

  /// Reads a stack fitting mode, defaulting to loose.
  static StackFit stackFit(Object? value) {
    return switch (value) {
      null => StackFit.loose,
      'loose' => StackFit.loose,
      'expand' => StackFit.expand,
      'passthrough' => StackFit.passthrough,
      _ => throw const FormatException('Unknown quickjs_ui StackFit'),
    };
  }

  /// Reads a supported software-keyboard input type.
  static TextInputType? textInputType(Object? value) {
    return switch (value) {
      null => null,
      'text' => TextInputType.text,
      'multiline' => TextInputType.multiline,
      'number' => TextInputType.number,
      'phone' => TextInputType.phone,
      'datetime' => TextInputType.datetime,
      'emailAddress' => TextInputType.emailAddress,
      'url' => TextInputType.url,
      'visiblePassword' => TextInputType.visiblePassword,
      _ => throw const FormatException('Unknown quickjs_ui TextInputType'),
    };
  }

  /// Reads a supported software-keyboard action.
  static TextInputAction? textInputAction(Object? value) {
    return switch (value) {
      null => null,
      'none' => TextInputAction.none,
      'unspecified' => TextInputAction.unspecified,
      'done' => TextInputAction.done,
      'go' => TextInputAction.go,
      'search' => TextInputAction.search,
      'send' => TextInputAction.send,
      'next' => TextInputAction.next,
      'previous' => TextInputAction.previous,
      'continueAction' => TextInputAction.continueAction,
      'join' => TextInputAction.join,
      'route' => TextInputAction.route,
      'emergencyCall' => TextInputAction.emergencyCall,
      'newline' => TextInputAction.newline,
      _ => throw const FormatException('Unknown quickjs_ui TextInputAction'),
    };
  }

  /// Reads main-axis alignment, defaulting to start.
  static MainAxisAlignment mainAxisAlignment(Object? value) {
    return switch (value) {
      null => MainAxisAlignment.start,
      'start' => MainAxisAlignment.start,
      'end' => MainAxisAlignment.end,
      'center' => MainAxisAlignment.center,
      'spaceBetween' => MainAxisAlignment.spaceBetween,
      'spaceAround' => MainAxisAlignment.spaceAround,
      'spaceEvenly' => MainAxisAlignment.spaceEvenly,
      _ => throw const FormatException('Unknown quickjs_ui mainAxisAlignment'),
    };
  }

  /// Reads main-axis sizing, defaulting to maximum size.
  static MainAxisSize mainAxisSize(Object? value) {
    return switch (value) {
      null || 'max' => MainAxisSize.max,
      'min' => MainAxisSize.min,
      _ => throw const FormatException('Unknown quickjs_ui mainAxisSize'),
    };
  }

  /// Reads cross-axis alignment, defaulting to center.
  static CrossAxisAlignment crossAxisAlignment(Object? value) {
    return switch (value) {
      null => CrossAxisAlignment.center,
      'start' => CrossAxisAlignment.start,
      'end' => CrossAxisAlignment.end,
      'center' => CrossAxisAlignment.center,
      'stretch' => CrossAxisAlignment.stretch,
      'baseline' => CrossAxisAlignment.baseline,
      _ => throw const FormatException('Unknown quickjs_ui crossAxisAlignment'),
    };
  }

  /// Reads a supported text alignment.
  static TextAlign? textAlign(Object? value) {
    return switch (value) {
      null => null,
      'left' => TextAlign.left,
      'right' => TextAlign.right,
      'center' => TextAlign.center,
      'justify' => TextAlign.justify,
      'start' => TextAlign.start,
      'end' => TextAlign.end,
      _ => throw const FormatException('Unknown quickjs_ui textAlign'),
    };
  }

  /// Reads a text style, optionally resolving theme tokens.
  static TextStyle? textStyle(
    Object? value, {
    JsUiColorResolver? resolveColor,
    JsUiTextStyleResolver? resolveTextStyle,
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) {
      return null;
    }
    final resolved = resolveTextStyle?.call(value);
    if (resolved != null) {
      return resolved;
    }
    final props = map(value, name: 'Text style');
    return TextStyle(
      color: color(props['color'], resolveColor: resolveColor),
      fontSize: number(
        props['fontSize'],
        name: 'fontSize',
        resolveNumber: resolveNumber,
      ),
      fontWeight: fontWeight(props['fontWeight']),
      letterSpacing: number(
        props['letterSpacing'],
        name: 'letterSpacing',
        resolveNumber: resolveNumber,
      ),
      height: number(
        props['height'],
        name: 'text style height',
        resolveNumber: resolveNumber,
      ),
      shadows: _textShadows(
        props['shadows'] ?? props['textShadows'] ?? props['textShadow'],
        resolveColor: resolveColor,
        resolveNumber: resolveNumber,
      ),
    );
  }

  static List<Shadow>? _textShadows(
    Object? value, {
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) return null;
    final values = value is List ? value : <Object?>[value];
    return values
        .map((raw) {
          final shadow = map(raw, name: 'Text shadow');
          final rawOffset = shadow['offset'];
          final offset = rawOffset == null
              ? const <String, Object?>{}
              : map(rawOffset, name: 'Text shadow offset');
          final blurRadius =
              number(
                shadow['blurRadius'] ?? shadow['blur'],
                name: 'text shadow blurRadius',
                resolveNumber: resolveNumber,
              ) ??
              0;
          if (blurRadius < 0) {
            throw const FormatException(
              'quickjs_ui Text shadow blurRadius must not be negative',
            );
          }
          return Shadow(
            color:
                color(shadow['color'], resolveColor: resolveColor) ??
                const Color(0x55000000),
            offset: Offset(
              number(
                    offset['x'] ?? shadow['offsetX'],
                    name: 'text shadow offset x',
                    resolveNumber: resolveNumber,
                  ) ??
                  0,
              number(
                    offset['y'] ?? shadow['offsetY'],
                    name: 'text shadow offset y',
                    resolveNumber: resolveNumber,
                  ) ??
                  0,
            ),
            blurRadius: blurRadius,
          );
        })
        .toList(growable: false);
  }

  /// Reads a named or numeric font weight.
  static FontWeight? fontWeight(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return switch (value.toInt()) {
        100 => FontWeight.w100,
        200 => FontWeight.w200,
        300 => FontWeight.w300,
        400 => FontWeight.w400,
        500 => FontWeight.w500,
        600 => FontWeight.w600,
        700 => FontWeight.w700,
        800 => FontWeight.w800,
        900 => FontWeight.w900,
        _ => throw const FormatException('Unknown quickjs_ui fontWeight'),
      };
    }
    return switch (value) {
      'normal' => FontWeight.normal,
      'bold' => FontWeight.bold,
      'w100' => FontWeight.w100,
      'w200' => FontWeight.w200,
      'w300' => FontWeight.w300,
      'w400' => FontWeight.w400,
      'w500' => FontWeight.w500,
      'w600' => FontWeight.w600,
      'w700' => FontWeight.w700,
      'w800' => FontWeight.w800,
      'w900' => FontWeight.w900,
      _ => throw const FormatException('Unknown quickjs_ui fontWeight'),
    };
  }

  /// Reads the decoration fields of a container's [props].
  static BoxDecoration? boxDecoration(
    Map<String, Object?> props, {
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveRadius,
    JsUiNumberResolver? resolveBorderWidth,
  }) {
    final decoration = map(props['decoration'], name: 'Container decoration');
    final merged = <String, Object?>{
      ...decoration,
      if (props.containsKey('color')) 'color': props['color'],
      if (props.containsKey('backgroundColor'))
        'color': props['backgroundColor'],
      if (props.containsKey('borderRadius'))
        'borderRadius': props['borderRadius'],
      if (props.containsKey('borderColor')) 'borderColor': props['borderColor'],
      if (props.containsKey('borderWidth')) 'borderWidth': props['borderWidth'],
      if (props.containsKey('border')) 'border': props['border'],
      if (props.containsKey('shape')) 'shape': props['shape'],
      if (props.containsKey('backgroundBlendMode'))
        'backgroundBlendMode': props['backgroundBlendMode'],
    };
    final background = color(merged['color'], resolveColor: resolveColor);
    final radius = borderRadius(
      merged['borderRadius'],
      resolveNumber: resolveRadius,
    );
    final border = _border(
      merged,
      resolveColor: resolveColor,
      resolveNumber: resolveBorderWidth,
    );
    final gradient = _gradient(
      merged['gradient'],
      resolveColor: resolveColor,
      resolveNumber: resolveRadius,
    );
    final shadows = _boxShadows(
      merged['boxShadow'] ?? merged['boxShadows'] ?? merged['shadows'],
      resolveColor: resolveColor,
      resolveNumber: resolveRadius,
    );
    final shape = switch (merged['shape']) {
      null || 'rectangle' => BoxShape.rectangle,
      'circle' => BoxShape.circle,
      _ => throw const FormatException('Unknown quickjs_ui decoration shape'),
    };
    if (background == null &&
        radius == null &&
        border == null &&
        gradient == null &&
        shadows == null &&
        merged['shape'] == null) {
      return null;
    }
    if (shape == BoxShape.circle && radius != null) {
      throw const FormatException(
        'quickjs_ui circle decoration cannot use borderRadius',
      );
    }
    return BoxDecoration(
      color: gradient == null ? background : null,
      gradient: gradient,
      borderRadius: radius,
      border: border,
      boxShadow: shadows,
      shape: shape,
      backgroundBlendMode: _blendMode(merged['backgroundBlendMode']),
    );
  }

  static List<BoxShadow>? _boxShadows(
    Object? value, {
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) return null;
    final values = value is List ? value : <Object?>[value];
    return values
        .map((raw) {
          final shadow = map(raw, name: 'Container boxShadow');
          final rawOffset = shadow['offset'];
          final offset = rawOffset == null
              ? const <String, Object?>{}
              : map(rawOffset, name: 'Container boxShadow offset');
          final blurRadius =
              number(
                shadow['blurRadius'] ?? shadow['blur'],
                name: 'boxShadow blurRadius',
                resolveNumber: resolveNumber,
              ) ??
              0;
          final spreadRadius =
              number(
                shadow['spreadRadius'] ?? shadow['spread'],
                name: 'boxShadow spreadRadius',
                resolveNumber: resolveNumber,
              ) ??
              0;
          if (blurRadius < 0) {
            throw const FormatException(
              'quickjs_ui Container boxShadow blurRadius must not be negative',
            );
          }
          return BoxShadow(
            color:
                color(shadow['color'], resolveColor: resolveColor) ??
                const Color(0x55000000),
            offset: Offset(
              number(
                    offset['x'] ?? shadow['offsetX'],
                    name: 'boxShadow offset x',
                    resolveNumber: resolveNumber,
                  ) ??
                  0,
              number(
                    offset['y'] ?? shadow['offsetY'],
                    name: 'boxShadow offset y',
                    resolveNumber: resolveNumber,
                  ) ??
                  0,
            ),
            blurRadius: blurRadius,
            spreadRadius: spreadRadius,
          );
        })
        .toList(growable: false);
  }

  static Gradient? _gradient(
    Object? value, {
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveNumber,
  }) {
    if (value == null) return null;
    final gradient = map(value, name: 'Container gradient');
    final rawColors = gradient['colors'];
    if (rawColors is! List || rawColors.length < 2) {
      throw const FormatException(
        'quickjs_ui Container gradient colors must contain at least two colors',
      );
    }
    final colors = rawColors
        .map((value) => color(value, resolveColor: resolveColor))
        .toList(growable: false);
    if (colors.any((value) => value == null)) {
      throw const FormatException(
        'quickjs_ui Container gradient colors must be valid colors',
      );
    }
    final rawStops = gradient['stops'];
    List<double>? stops;
    if (rawStops != null) {
      if (rawStops is! List || rawStops.length != colors.length) {
        throw const FormatException(
          'quickjs_ui Container gradient stops must match colors length',
        );
      }
      final parsedStops = rawStops
          .map(
            (value) => number(
              value,
              name: 'gradient stop',
              resolveNumber: resolveNumber,
            ),
          )
          .toList(growable: false);
      if (parsedStops.any((value) => value == null)) {
        throw const FormatException(
          'quickjs_ui Container gradient stops must be numbers',
        );
      }
      stops = parsedStops.cast<double>();
      for (var index = 0; index < stops.length; index += 1) {
        final stop = stops[index];
        if (stop < 0 || stop > 1 || (index > 0 && stop < stops[index - 1])) {
          throw const FormatException(
            'quickjs_ui Container gradient stops must be ordered from 0 to 1',
          );
        }
      }
    }
    final resolvedColors = colors.cast<Color>();
    return switch (gradient['type']) {
      null || 'linear' => LinearGradient(
        begin: alignment(gradient['begin']) ?? Alignment.topCenter,
        end: alignment(gradient['end']) ?? Alignment.bottomCenter,
        colors: resolvedColors,
        stops: stops,
        tileMode: _gradientTileMode(gradient['tileMode']),
      ),
      'radial' => RadialGradient(
        center: alignment(gradient['center']) ?? Alignment.center,
        radius: _positiveGradientRadius(
          gradient['radius'],
          resolveNumber: resolveNumber,
        ),
        colors: resolvedColors,
        stops: stops,
        tileMode: _gradientTileMode(gradient['tileMode']),
      ),
      _ => throw const FormatException(
        'quickjs_ui Container gradient type must be linear or radial',
      ),
    };
  }

  static TileMode _gradientTileMode(Object? value) => switch (value) {
    null || 'clamp' => TileMode.clamp,
    'repeat' => TileMode.repeated,
    'mirror' => TileMode.mirror,
    'decal' => TileMode.decal,
    _ => throw const FormatException(
      'quickjs_ui Container gradient tileMode is invalid',
    ),
  };

  static double _positiveGradientRadius(
    Object? value, {
    JsUiNumberResolver? resolveNumber,
  }) {
    final radius =
        number(value, name: 'gradient radius', resolveNumber: resolveNumber) ??
        0.5;
    if (radius <= 0) {
      throw const FormatException(
        'quickjs_ui Container radial gradient radius must be positive',
      );
    }
    return radius;
  }

  static BoxBorder? _border(
    Map<String, Object?> props, {
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveNumber,
  }) {
    final border = props['border'] == null
        ? const <String, Object?>{}
        : map(props['border'], name: 'Container border');
    final hasSides = <String>[
      'left',
      'top',
      'right',
      'bottom',
    ].any(border.containsKey);
    if (hasSides) {
      return Border(
        left: _borderSide(border['left'], resolveColor, resolveNumber),
        top: _borderSide(border['top'], resolveColor, resolveNumber),
        right: _borderSide(border['right'], resolveColor, resolveNumber),
        bottom: _borderSide(border['bottom'], resolveColor, resolveNumber),
      );
    }
    final colorValue = props['borderColor'] ?? border['color'];
    final widthValue = props['borderWidth'] ?? border['width'];
    if (colorValue == null && widthValue == null) {
      return null;
    }
    return Border.all(
      color: color(colorValue, resolveColor: resolveColor) ?? Colors.black,
      width:
          number(
            widthValue,
            name: 'border width',
            resolveNumber: resolveNumber,
          ) ??
          1,
    );
  }

  static BorderSide _borderSide(
    Object? value,
    JsUiColorResolver? resolveColor,
    JsUiNumberResolver? resolveNumber,
  ) {
    if (value == null) return BorderSide.none;
    final side = map(value, name: 'Container border side');
    return BorderSide(
      color: color(side['color'], resolveColor: resolveColor) ?? Colors.black,
      width:
          number(
            side['width'],
            name: 'border side width',
            resolveNumber: resolveNumber,
          ) ??
          1,
      style: side['style'] == 'none' ? BorderStyle.none : BorderStyle.solid,
    );
  }

  static BlendMode? _blendMode(Object? value) => switch (value) {
    null => null,
    'srcOver' => BlendMode.srcOver,
    'multiply' => BlendMode.multiply,
    'screen' => BlendMode.screen,
    'overlay' => BlendMode.overlay,
    'darken' => BlendMode.darken,
    'lighten' => BlendMode.lighten,
    'colorDodge' => BlendMode.colorDodge,
    'colorBurn' => BlendMode.colorBurn,
    'hardLight' => BlendMode.hardLight,
    'softLight' => BlendMode.softLight,
    'difference' => BlendMode.difference,
    'exclusion' => BlendMode.exclusion,
    'hue' => BlendMode.hue,
    'saturation' => BlendMode.saturation,
    'color' => BlendMode.color,
    'luminosity' => BlendMode.luminosity,
    _ => throw const FormatException('Unknown quickjs_ui blend mode'),
  };
}
