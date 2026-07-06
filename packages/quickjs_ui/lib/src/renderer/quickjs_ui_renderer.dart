import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
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
  final Map<String, _LifecycleComponentEntry> _lifecycleComponents =
      <String, _LifecycleComponentEntry>{};
  bool _shown = false;
  bool _paused = false;

  Widget build(QuickjsUiNode node, {BuildContext? buildContext}) {
    late final QuickjsUiRenderContext context;
    final nextCache = <String, _RenderedNode>{};
    final activeLifecycleKeys = <String>{};
    var buildDepth = 0;
    Widget buildNode(QuickjsUiNode node) {
      if (buildDepth > maxBuildDepth) {
        throw const FormatException('quickjs_ui render tree is too deep');
      }
      buildDepth += 1;
      try {
        return _buildNode(
          context,
          node,
          nextCache,
          activeLifecycleKeys,
          buildContext,
        );
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
    _disposeInactiveLifecycleComponents(activeLifecycleKeys);
    return widget;
  }

  Widget _buildNode(
    QuickjsUiRenderContext context,
    QuickjsUiNode node,
    Map<String, _RenderedNode> nextCache,
    Set<String> activeLifecycleKeys,
    BuildContext? buildContext,
  ) {
    final controller = _controllerFor(node, activeLifecycleKeys);
    final key = _nodeKey(node);
    if (key == null) {
      return _withAccessibility(
        node,
        registry.build(context, node, controller: controller),
      );
    }
    final signature = _nodeSignature(node, buildContext);
    final cached = _cache[key];
    if (cached != null && cached.signature == signature) {
      nextCache[key] = cached;
      return cached.widget;
    }
    final widget = KeyedSubtree(
      key: ValueKey<String>(key),
      child: _withAccessibility(
        node,
        registry.build(context, node, controller: controller),
      ),
    );
    nextCache[key] = _RenderedNode(signature: signature, widget: widget);
    return widget;
  }

  void show() {
    if (_shown) {
      return;
    }
    _shown = true;
    for (final entry in _lifecycleComponents.values) {
      entry.controller.show();
    }
  }

  void hide() {
    if (!_shown) {
      return;
    }
    _shown = false;
    for (final entry in _lifecycleComponents.values) {
      entry.controller.hide();
    }
  }

  void pause() {
    if (_paused) {
      return;
    }
    _paused = true;
    for (final entry in _lifecycleComponents.values) {
      entry.controller.pause();
    }
  }

  void resume() {
    if (!_paused) {
      return;
    }
    _paused = false;
    for (final entry in _lifecycleComponents.values) {
      entry.controller.resume();
    }
  }

  void dispose() {
    for (final entry in _lifecycleComponents.values) {
      if (_shown) {
        entry.controller.hide();
      }
      entry.controller.dispose();
    }
    _lifecycleComponents.clear();
    _eventDispatcher.dispose();
    _cache.clear();
    _shown = false;
    _paused = false;
  }

  void _dispatchEnvelope(QuickjsUiEventEnvelope envelope) {
    final handler = onUiEvent;
    if (handler != null) {
      handler(envelope);
      return;
    }
    onEvent(envelope.event);
  }

  QuickjsUiComponentController? _controllerFor(
    QuickjsUiNode node,
    Set<String> activeLifecycleKeys,
  ) {
    if (!registry.hasLifecycle(node.type)) {
      return null;
    }
    final lifecycleKey = _lifecycleKey(node);
    activeLifecycleKeys.add(lifecycleKey);
    final current = _lifecycleComponents[lifecycleKey];
    if (current != null) {
      current.controller.update(current.node, node);
      current.node = node;
      return current.controller;
    }
    final controller = registry.createController(node)..mount(node);
    if (_shown) {
      controller.show();
    }
    if (_paused) {
      controller.pause();
    }
    _lifecycleComponents[lifecycleKey] = _LifecycleComponentEntry(
      node: node,
      controller: controller,
    );
    return controller;
  }

  void _disposeInactiveLifecycleComponents(Set<String> activeKeys) {
    final inactiveKeys = _lifecycleComponents.keys
        .where((key) => !activeKeys.contains(key))
        .toList(growable: false);
    for (final key in inactiveKeys) {
      final entry = _lifecycleComponents.remove(key);
      if (entry == null) {
        continue;
      }
      if (_shown) {
        entry.controller.hide();
      }
      entry.controller.dispose();
    }
  }
}

Widget _withAccessibility(QuickjsUiNode node, Widget child) {
  final tooltip = QuickjsUiProps.string(node.props['tooltip']);
  final label = QuickjsUiProps.string(
    node.props['semanticLabel'] ?? node.props['semanticsLabel'],
  );
  final hint = QuickjsUiProps.string(node.props['semanticHint']);
  final role = QuickjsUiProps.string(node.props['role']);
  final enabled = QuickjsUiProps.boolValue(node.props['enabled']);
  final focusOrder = QuickjsUiProps.doubleValue(node.props['focusOrder']);
  var result = child;
  if (tooltip != null && tooltip.isNotEmpty) {
    result = Tooltip(message: tooltip, child: result);
  }
  if (label == null &&
      hint == null &&
      role == null &&
      enabled == null &&
      focusOrder == null) {
    return result;
  }
  result = Semantics(
    label: label,
    hint: hint,
    button: role == 'button',
    image: role == 'image',
    textField: role == 'textField',
    header: role == 'header',
    enabled: enabled,
    sortKey: focusOrder == null ? null : OrdinalSortKey(focusOrder),
    child: result,
  );
  return result;
}

final class _RenderedNode {
  const _RenderedNode({required this.signature, required this.widget});

  final String signature;
  final Widget widget;
}

final class _LifecycleComponentEntry {
  _LifecycleComponentEntry({required this.node, required this.controller});

  QuickjsUiNode node;
  final QuickjsUiComponentController controller;
}

String? _nodeKey(QuickjsUiNode node) {
  final key = node.props['key'];
  if (key is String && key.isNotEmpty) {
    return key;
  }
  return null;
}

String _lifecycleKey(QuickjsUiNode node) {
  final key = _nodeKey(node);
  if (key == null) {
    throw FormatException(
      'quickjs_ui lifecycle component ${node.type} requires a stable string key',
    );
  }
  return '${node.type}:$key';
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
