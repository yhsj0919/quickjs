import 'dart:ui';

import 'package:flutter/material.dart';

@immutable
final class QuickjsUiDesignTokens
    extends ThemeExtension<QuickjsUiDesignTokens> {
  QuickjsUiDesignTokens({
    Map<String, Color> colors = const <String, Color>{},
    Map<String, TextStyle> textStyles = const <String, TextStyle>{},
    Map<String, double> spacing = const <String, double>{},
    Map<String, double> radius = const <String, double>{},
    Map<String, double> elevation = const <String, double>{},
  }) : colors = _normalizeColorMap(colors),
       textStyles = _normalizeTextStyleMap(textStyles),
       spacing = _normalizeNumberMap(spacing),
       radius = _normalizeNumberMap(radius),
       elevation = _normalizeNumberMap(elevation);

  final Map<String, Color> colors;
  final Map<String, TextStyle> textStyles;
  final Map<String, double> spacing;
  final Map<String, double> radius;
  final Map<String, double> elevation;

  Color? color(Object? value) {
    final token = tokenKey(value);
    return token == null ? null : colors[token];
  }

  TextStyle? textStyle(Object? value) {
    final token = tokenKey(value);
    return token == null ? null : textStyles[token];
  }

  double? number(Object? value, QuickjsUiTokenCategory category) {
    final token = tokenKey(value);
    if (token == null) {
      return null;
    }
    final stripped = stripCategory(token, category.prefixes);
    return switch (category) {
      QuickjsUiTokenCategory.spacing =>
        spacing[token] ?? spacing[stripped] ?? _defaultSpacing[stripped],
      QuickjsUiTokenCategory.radius =>
        radius[token] ?? radius[stripped] ?? _defaultRadius[stripped],
      QuickjsUiTokenCategory.elevation =>
        elevation[token] ?? elevation[stripped] ?? _defaultElevation[stripped],
    };
  }

  @override
  QuickjsUiDesignTokens copyWith({
    Map<String, Color>? colors,
    Map<String, TextStyle>? textStyles,
    Map<String, double>? spacing,
    Map<String, double>? radius,
    Map<String, double>? elevation,
  }) {
    return QuickjsUiDesignTokens(
      colors: colors ?? this.colors,
      textStyles: textStyles ?? this.textStyles,
      spacing: spacing ?? this.spacing,
      radius: radius ?? this.radius,
      elevation: elevation ?? this.elevation,
    );
  }

  @override
  QuickjsUiDesignTokens lerp(
    ThemeExtension<QuickjsUiDesignTokens>? other,
    double t,
  ) {
    if (other is! QuickjsUiDesignTokens) {
      return this;
    }
    return QuickjsUiDesignTokens(
      colors: _lerpColors(colors, other.colors, t),
      textStyles: _lerpTextStyles(textStyles, other.textStyles, t),
      spacing: _lerpNumbers(spacing, other.spacing, t),
      radius: _lerpNumbers(radius, other.radius, t),
      elevation: _lerpNumbers(elevation, other.elevation, t),
    );
  }

  static String? tokenKey(Object? value) {
    if (value is! String || !value.startsWith(r'$')) {
      return null;
    }
    return normalizeToken(value);
  }

  static String stripCategory(String token, Iterable<String> prefixes) {
    for (final prefix in prefixes) {
      if (token.startsWith(prefix)) {
        return token.substring(prefix.length);
      }
    }
    return token;
  }

  static String normalizeToken(String value) {
    final raw = value.startsWith(r'$') ? value.substring(1) : value;
    return raw.toLowerCase().replaceAll(RegExp(r'[^a-z0-9]'), '');
  }
}

enum QuickjsUiTokenCategory {
  spacing(<String>['space', 'spacing']),
  radius(<String>['radius', 'radii']),
  elevation(<String>['elevation', 'shadow']);

  const QuickjsUiTokenCategory(this.prefixes);

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

Map<String, Color> _normalizeColorMap(Map<String, Color> values) {
  return Map<String, Color>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, Color>(
        QuickjsUiDesignTokens.normalizeToken(key),
        value,
      );
    }),
  );
}

Map<String, TextStyle> _normalizeTextStyleMap(Map<String, TextStyle> values) {
  return Map<String, TextStyle>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, TextStyle>(
        QuickjsUiDesignTokens.normalizeToken(key),
        value,
      );
    }),
  );
}

Map<String, double> _normalizeNumberMap(Map<String, double> values) {
  return Map<String, double>.unmodifiable(
    values.map((key, value) {
      return MapEntry<String, double>(
        QuickjsUiDesignTokens.normalizeToken(key),
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
