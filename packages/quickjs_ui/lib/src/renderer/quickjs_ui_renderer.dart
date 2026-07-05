import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import 'quickjs_ui_component_registry.dart';
import 'quickjs_ui_render_context.dart';

final class QuickjsUiRenderer {
  static const int maxBuildDepth = 128;

  QuickjsUiRenderer({
    required this.onEvent,
    this.onUiEvent,
    QuickjsUiComponentRegistry? registry,
  }) : registry = registry ?? QuickjsUiComponentRegistry.defaults();

  final QuickjsUiEventHandler onEvent;
  final QuickjsUiEventEnvelopeHandler? onUiEvent;
  final QuickjsUiComponentRegistry registry;
  late final QuickjsUiEventDispatcher _eventDispatcher =
      QuickjsUiEventDispatcher(_dispatchEnvelope);
  final Map<String, _RenderedNode> _cache = <String, _RenderedNode>{};

  Widget build(QuickjsUiNode node, {BuildContext? buildContext}) {
    late final QuickjsUiRenderContext context;
    final nextCache = <String, _RenderedNode>{};
    var buildDepth = 0;
    Widget buildNode(QuickjsUiNode node) {
      if (buildDepth > maxBuildDepth) {
        throw const FormatException('quickjs_ui render tree is too deep');
      }
      buildDepth += 1;
      try {
        return _buildNode(context, node, nextCache, buildContext);
      } finally {
        buildDepth -= 1;
      }
    }

    context = QuickjsUiRenderContext(
      buildNode: buildNode,
      onUiEvent: _dispatchEnvelope,
      onEvent: onEvent,
      eventDispatcher: _eventDispatcher,
      buildContext: buildContext,
    );
    final widget = buildNode(node);
    _cache
      ..clear()
      ..addAll(nextCache);
    return widget;
  }

  Widget _buildNode(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    Map<String, _RenderedNode> nextCache,
    BuildContext? buildContext,
  ) {
    final key = _nodeKey(node);
    if (key == null) {
      return registry.build(context, node);
    }
    final signature = _nodeSignature(node, buildContext);
    final cached = _cache[key];
    if (cached != null && cached.signature == signature) {
      nextCache[key] = cached;
      return cached.widget;
    }
    final widget = KeyedSubtree(
      key: ValueKey<String>(key),
      child: registry.build(context, node),
    );
    nextCache[key] = _RenderedNode(signature: signature, widget: widget);
    return widget;
  }

  void dispose() {
    _eventDispatcher.dispose();
    _cache.clear();
  }

  void _dispatchEnvelope(QuickjsUiEventEnvelope envelope) {
    final handler = onUiEvent;
    if (handler != null) {
      handler(envelope);
      return;
    }
    onEvent(envelope.event);
  }
}

final class _RenderedNode {
  const _RenderedNode({required this.signature, required this.widget});

  final String signature;
  final Widget widget;
}

String? _nodeKey(QuickjsUiNode node) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return key;
  }
  return null;
}

String _nodeSignature(QuickjsUiNode node, BuildContext? buildContext) {
  final buffer = StringBuffer()
    ..write(node.type)
    ..write('|')
    ..write(_stableValue(node.props))
    ..write('|theme=')
    ..write(buildContext == null ? '' : Theme.of(buildContext).hashCode)
    ..write('|children=[');
  for (final child in node.children) {
    buffer
      ..write(_nodeSignature(child, buildContext))
      ..write(',');
  }
  buffer.write(']');
  return buffer.toString();
}

String _stableValue(Object? value) {
  if (value == null || value is num || value is bool || value is String) {
    return '$value';
  }
  if (value is Map) {
    final entries = value.entries.toList()
      ..sort((a, b) => '${a.key}'.compareTo('${b.key}'));
    return '{${entries.map((entry) {
      return '${entry.key}:${_stableValue(entry.value)}';
    }).join(',')}}';
  }
  if (value is Iterable) {
    return '[${value.map(_stableValue).join(',')}]';
  }
  return '$value';
}
