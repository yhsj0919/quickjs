import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';

// Keep the public constructor parameter named `buildNode`.
// ignore_for_file: prefer_initializing_formals

typedef QuickjsUiEventHandler = void Function(Map<String, Object?> event);
typedef QuickjsUiNodeBuilder = Widget Function(QuickjsUiNode node);

final class QuickjsUiRenderContext {
  const QuickjsUiRenderContext({
    required QuickjsUiNodeBuilder buildNode,
    required this.onEvent,
    this.buildContext,
  }) : _buildNode = buildNode;

  final QuickjsUiNodeBuilder _buildNode;
  final QuickjsUiEventHandler onEvent;
  final BuildContext? buildContext;

  Color? color(Object? value) {
    return QuickjsUiProps.color(value, resolveColor: _themeColor);
  }

  TextStyle? textStyle(Object? value) {
    return QuickjsUiProps.textStyle(
      value,
      resolveColor: _themeColor,
      resolveTextStyle: _themeTextStyle,
    );
  }

  BoxDecoration? boxDecoration(Map<String, Object?> props) {
    return QuickjsUiProps.boxDecoration(props, resolveColor: _themeColor);
  }

  Widget build(QuickjsUiNode node) {
    return _buildNode(node);
  }

  Widget? child(QuickjsUiNode node) {
    if (node.children.isEmpty) {
      return null;
    }
    if (node.children.length > 1) {
      throw FormatException('${node.type} expects a single child');
    }
    return build(node.children.single);
  }

  List<Widget> children(QuickjsUiNode node) {
    return <Widget>[for (final child in node.children) build(child)];
  }

  void dispatch(Map<String, Object?> event) {
    onEvent(event);
  }

  Color? _themeColor(Object? value) {
    final context = buildContext;
    if (context == null || value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final scheme = Theme.of(context).colorScheme;
    return switch (_normalizeToken(value)) {
      'primary' => scheme.primary,
      'onprimary' => scheme.onPrimary,
      'primarycontainer' => scheme.primaryContainer,
      'onprimarycontainer' => scheme.onPrimaryContainer,
      'secondary' => scheme.secondary,
      'onsecondary' => scheme.onSecondary,
      'secondarycontainer' => scheme.secondaryContainer,
      'onsecondarycontainer' => scheme.onSecondaryContainer,
      'tertiary' => scheme.tertiary,
      'ontertiary' => scheme.onTertiary,
      'surface' => scheme.surface,
      'onsurface' => scheme.onSurface,
      'surfacevariant' => scheme.surfaceContainerHighest,
      'background' => scheme.surface,
      'onbackground' => scheme.onSurface,
      'error' => scheme.error,
      'onerror' => scheme.onError,
      'outline' => scheme.outline,
      _ => null,
    };
  }

  TextStyle? _themeTextStyle(Object? value) {
    final context = buildContext;
    if (context == null || value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final textTheme = Theme.of(context).textTheme;
    return switch (_normalizeToken(value)) {
      'displaylarge' => textTheme.displayLarge,
      'displaymedium' => textTheme.displayMedium,
      'displaysmall' => textTheme.displaySmall,
      'headlinelarge' => textTheme.headlineLarge,
      'headlinemedium' => textTheme.headlineMedium,
      'headlinesmall' => textTheme.headlineSmall,
      'titlelarge' => textTheme.titleLarge,
      'titlemedium' => textTheme.titleMedium,
      'titlesmall' => textTheme.titleSmall,
      'bodylarge' => textTheme.bodyLarge,
      'bodymedium' => textTheme.bodyMedium,
      'bodysmall' => textTheme.bodySmall,
      'labellarge' => textTheme.labelLarge,
      'labelmedium' => textTheme.labelMedium,
      'labelsmall' => textTheme.labelSmall,
      _ => null,
    };
  }
}

String _normalizeToken(String value) {
  var token = value.substring(1).toLowerCase();
  for (final prefix in <String>[
    'texttheme.',
    'theme.',
    'colors.',
    'color.',
    'text.',
  ]) {
    if (token.startsWith(prefix)) {
      token = token.substring(prefix.length);
      break;
    }
  }
  return token.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
