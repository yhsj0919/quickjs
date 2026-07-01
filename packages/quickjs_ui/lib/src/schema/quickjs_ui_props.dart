import 'package:flutter/material.dart';

final class QuickjsUiProps {
  const QuickjsUiProps._();

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

  static Map<String, Object?>? event(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is Map) {
      return value.map(
        (key, value) => MapEntry<String, Object?>('$key', value),
      );
    }
    throw const FormatException('quickjs_ui event must be an object');
  }

  static String? string(Object? value, {String name = 'string property'}) {
    if (value == null) {
      return null;
    }
    if (value is String) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be a string');
  }

  static double? doubleValue(Object? value, {String name = 'number property'}) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return value.toDouble();
    }
    throw FormatException('quickjs_ui $name must be a number');
  }

  static int? intValue(Object? value, {String name = 'int property'}) {
    if (value == null) {
      return null;
    }
    if (value is int) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be an int');
  }

  static bool? boolValue(Object? value, {String name = 'bool property'}) {
    if (value == null) {
      return null;
    }
    if (value is bool) {
      return value;
    }
    throw FormatException('quickjs_ui $name must be a bool');
  }

  static double opacity(Object? value) {
    return (doubleValue(value, name: 'opacity') ?? 1).clamp(0, 1).toDouble();
  }

  static Color? color(Object? value) {
    if (value == null) {
      return null;
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

  static EdgeInsetsGeometry? edgeInsets(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return EdgeInsets.all(value.toDouble());
    }
    final props = map(value, name: 'edge inset property');
    final all =
        doubleValue(props['all'], name: 'edge inset all') ??
        doubleValue(props['value'], name: 'edge inset value');
    if (all != null) {
      return EdgeInsets.all(all);
    }
    final horizontal = doubleValue(
      props['horizontal'],
      name: 'edge inset horizontal',
    );
    final vertical = doubleValue(
      props['vertical'],
      name: 'edge inset vertical',
    );
    return EdgeInsets.fromLTRB(
      doubleValue(props['left'], name: 'edge inset left') ?? horizontal ?? 0,
      doubleValue(props['top'], name: 'edge inset top') ?? vertical ?? 0,
      doubleValue(props['right'], name: 'edge inset right') ?? horizontal ?? 0,
      doubleValue(props['bottom'], name: 'edge inset bottom') ?? vertical ?? 0,
    );
  }

  static BorderRadiusGeometry? borderRadius(Object? value) {
    if (value == null) {
      return null;
    }
    if (value is num) {
      return BorderRadius.circular(value.toDouble());
    }
    final props = map(value, name: 'border radius property');
    final all =
        doubleValue(props['all'], name: 'border radius all') ??
        doubleValue(props['radius'], name: 'border radius radius');
    if (all != null) {
      return BorderRadius.circular(all);
    }
    return BorderRadius.only(
      topLeft: Radius.circular(
        doubleValue(props['topLeft'], name: 'border radius topLeft') ?? 0,
      ),
      topRight: Radius.circular(
        doubleValue(props['topRight'], name: 'border radius topRight') ?? 0,
      ),
      bottomLeft: Radius.circular(
        doubleValue(props['bottomLeft'], name: 'border radius bottomLeft') ?? 0,
      ),
      bottomRight: Radius.circular(
        doubleValue(props['bottomRight'], name: 'border radius bottomRight') ??
            0,
      ),
    );
  }

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

  static Axis axis(Object? value) {
    return switch (value) {
      null => Axis.vertical,
      'vertical' => Axis.vertical,
      'horizontal' => Axis.horizontal,
      _ => throw const FormatException('Unknown quickjs_ui axis'),
    };
  }

  static StackFit stackFit(Object? value) {
    return switch (value) {
      null => StackFit.loose,
      'loose' => StackFit.loose,
      'expand' => StackFit.expand,
      'passthrough' => StackFit.passthrough,
      _ => throw const FormatException('Unknown quickjs_ui StackFit'),
    };
  }

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

  static TextStyle? textStyle(Object? value) {
    if (value == null) {
      return null;
    }
    final props = map(value, name: 'Text style');
    return TextStyle(
      color: color(props['color']),
      fontSize: doubleValue(props['fontSize'], name: 'fontSize'),
      fontWeight: fontWeight(props['fontWeight']),
      letterSpacing: doubleValue(props['letterSpacing'], name: 'letterSpacing'),
      height: doubleValue(props['height'], name: 'text style height'),
    );
  }

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

  static BoxDecoration? boxDecoration(Map<String, Object?> props) {
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
    };
    final background = color(merged['color']);
    final radius = borderRadius(merged['borderRadius']);
    final border = _border(merged);
    if (background == null && radius == null && border == null) {
      return null;
    }
    return BoxDecoration(
      color: background,
      borderRadius: radius,
      border: border,
    );
  }

  static BoxBorder? _border(Map<String, Object?> props) {
    final border = props['border'] == null
        ? const <String, Object?>{}
        : map(props['border'], name: 'Container border');
    final colorValue = props['borderColor'] ?? border['color'];
    final widthValue = props['borderWidth'] ?? border['width'];
    if (colorValue == null && widthValue == null) {
      return null;
    }
    return Border.all(
      color: color(colorValue) ?? Colors.black,
      width: doubleValue(widthValue, name: 'border width') ?? 1,
    );
  }
}
