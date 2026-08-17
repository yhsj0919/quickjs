import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
/// Public JSUI js ui design tokens API.
final class JsUiDesignTokens extends ThemeExtension<JsUiDesignTokens> {
  /// Creates a js ui design tokens.
  JsUiDesignTokens({
    Map<String, Color> colors = const <String, Color>{},
    Map<String, TextStyle> textStyles = const <String, TextStyle>{},
    Map<String, double> spacing = const <String, double>{},
    Map<String, double> radius = const <String, double>{},
    Map<String, double> elevation = const <String, double>{},
    Map<String, double> fontSizes = const <String, double>{},
  }) : colors = _normalizeColorMap(colors),
       textStyles = _normalizeTextStyleMap(textStyles),
       spacing = _normalizeNumberMap(spacing),
       radius = _normalizeNumberMap(radius),
       elevation = _normalizeNumberMap(elevation),
       fontSizes = _normalizeNumberMap(fontSizes);

  /// The colors value.
  final Map<String, Color> colors;

  /// The text styles value.
  final Map<String, TextStyle> textStyles;

  /// The spacing value.
  final Map<String, double> spacing;

  /// The radius value.
  final Map<String, double> radius;

  /// The elevation value.
  final Map<String, double> elevation;

  /// The font sizes value.
  final Map<String, double> fontSizes;

  /// The color value.
  Color? color(Object? value) {
    final token = tokenKey(value);
    return token == null ? null : colors[token];
  }

  /// The text style value.
  TextStyle? textStyle(Object? value) {
    final token = tokenKey(value);
    return token == null ? null : textStyles[token];
  }

  /// The number value.
  double? number(Object? value, JsUiTokenCategory category) {
    final token = tokenKey(value);
    if (token == null) {
      return null;
    }
    final stripped = stripCategory(token, category.prefixes);
    return switch (category) {
      JsUiTokenCategory.spacing =>
        spacing[token] ?? spacing[stripped] ?? _defaultSpacing[stripped],
      JsUiTokenCategory.radius =>
        radius[token] ?? radius[stripped] ?? _defaultRadius[stripped],
      JsUiTokenCategory.elevation =>
        elevation[token] ?? elevation[stripped] ?? _defaultElevation[stripped],
      JsUiTokenCategory.fontSize =>
        fontSizes[token] ?? fontSizes[stripped] ?? _defaultFontSizes[stripped],
    };
  }

  @override
  JsUiDesignTokens copyWith({
    Map<String, Color>? colors,
    Map<String, TextStyle>? textStyles,
    Map<String, double>? spacing,
    Map<String, double>? radius,
    Map<String, double>? elevation,
    Map<String, double>? fontSizes,
  }) {
    return JsUiDesignTokens(
      colors: colors ?? this.colors,
      textStyles: textStyles ?? this.textStyles,
      spacing: spacing ?? this.spacing,
      radius: radius ?? this.radius,
      elevation: elevation ?? this.elevation,
      fontSizes: fontSizes ?? this.fontSizes,
    );
  }

  @override
  JsUiDesignTokens lerp(ThemeExtension<JsUiDesignTokens>? other, double t) {
    if (other is! JsUiDesignTokens) {
      return this;
    }
    return JsUiDesignTokens(
      colors: _lerpColors(colors, other.colors, t),
      textStyles: _lerpTextStyles(textStyles, other.textStyles, t),
      spacing: _lerpNumbers(spacing, other.spacing, t),
      radius: _lerpNumbers(radius, other.radius, t),
      elevation: _lerpNumbers(elevation, other.elevation, t),
      fontSizes: _lerpNumbers(fontSizes, other.fontSizes, t),
    );
  }

  /// The token key value.
  static String? tokenKey(Object? value) {
    if (value is! String || !value.startsWith(r'$')) {
      return null;
    }
    return normalizeToken(value);
  }

  /// Performs the strip category operation.
  static String stripCategory(String token, Iterable<String> prefixes) {
    for (final prefix in prefixes) {
      if (token.startsWith(prefix)) {
        return token.substring(prefix.length);
      }
    }
    return token;
  }

  /// Performs the normalize token operation.
  static String normalizeToken(String value) {
    final raw = value.startsWith(r'$') ? value.substring(1) : value;
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

/// Values supported by js ui token category.
enum JsUiTokenCategory {
  /// The spacing value.
  spacing(<String>['space', 'spacing']),

  /// The radius value.
  radius(<String>['radius', 'radii']),

  /// The elevation value.
  elevation(<String>['elevation', 'shadow']),

  /// The font size value.
  fontSize(<String>['font', 'fontsize', 'type', 'typography']);

  const JsUiTokenCategory(this.prefixes);

  /// The prefixes value.
  final List<String> prefixes;
}

const Map<String, double> _defaultSpacing = <String, double>{
  'none': 0,
  'xxs': 2,
  'xs': 4,
  'sm': 8,
  'md': 12,
  'lg': 16,
  'xl': 24,
  'xxl': 32,
};

const Map<String, double> _defaultRadius = <String, double>{
  'none': 0,
  'xs': 2,
  'sm': 4,
  'md': 8,
  'lg': 12,
  'xl': 16,
  'full': 9999,
};

const Map<String, double> _defaultElevation = <String, double>{
  'none': 0,
  'xs': 1,
  'sm': 2,
  'md': 4,
  'lg': 8,
  'xl': 12,
};

const Map<String, double> _defaultFontSizes = <String, double>{
  'xs': 12,
  'sm': 14,
  'md': 16,
  'lg': 20,
  'xl': 24,
  'xxl': 32,
};

Map<String, Color> _normalizeColorMap(Map<String, Color> values) {
  return Map<String, Color>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, Color>(
        JsUiDesignTokens.normalizeToken(key),
        value,
      );
    }),
  );
}

Map<String, TextStyle> _normalizeTextStyleMap(Map<String, TextStyle> values) {
  return Map<String, TextStyle>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, TextStyle>(
        JsUiDesignTokens.normalizeToken(key),
        value,
      );
    }),
  );
}

Map<String, double> _normalizeNumberMap(Map<String, double> values) {
  return Map<String, double>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, double>(
        JsUiDesignTokens.normalizeToken(key),
        value,
      );
    }),
  );
}

Map<String, Color> _lerpColors(
  Map<String, Color> a,
  Map<String, Color> b,
  double t,
) {
  final result = <String, Color>{};
  for (final key in <String>{...a.keys, ...b.keys}) {
    final color = Color.lerp(a[key], b[key], t);
    if (color != null) {
      result[key] = color;
    }
  }
  return result;
}

Map<String, TextStyle> _lerpTextStyles(
  Map<String, TextStyle> a,
  Map<String, TextStyle> b,
  double t,
) {
  final result = <String, TextStyle>{};
  for (final key in <String>{...a.keys, ...b.keys}) {
    final style = TextStyle.lerp(a[key], b[key], t);
    if (style != null) {
      result[key] = style;
    }
  }
  return result;
}

Map<String, double> _lerpNumbers(
  Map<String, double> a,
  Map<String, double> b,
  double t,
) {
  return <String, double>{
    for (final key in <String>{...a.keys, ...b.keys})
      key: lerpDouble(a[key], b[key], t) ?? a[key] ?? b[key]!,
  };
}
