import 'dart:async';

import 'package:flutter/material.dart';

import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';

// Keep the public constructor parameter named `buildNode`.
// ignore_for_file: prefer_initializing_formals

typedef QuickjsUiEventHandler = void Function(Map<String, Object?> event);
typedef QuickjsUiNodeBuilder = Widget Function(QuickjsUiNode node);

final class QuickjsUiRenderContext {
  QuickjsUiRenderContext({
    required QuickjsUiNodeBuilder buildNode,
    required this.onEvent,
    QuickjsUiEventDispatcher? eventDispatcher,
    this.buildContext,
  }) : _buildNode = buildNode,
       _eventDispatcher = eventDispatcher;

  final QuickjsUiNodeBuilder _buildNode;
  final QuickjsUiEventHandler onEvent;
  final QuickjsUiEventDispatcher? _eventDispatcher;
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

  void dispatchEvent(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
  }) {
    final dispatcher = _eventDispatcher;
    if (dispatcher != null) {
      dispatcher.dispatch(
        event,
        payload: payload,
        defaultCoalesceKey: defaultCoalesceKey,
      );
      return;
    }
    final merged = payload == null
        ? event
        : <String, Object?>{...event, ...payload};
    onEvent(merged);
  }
}

final class QuickjsUiEventDispatcher {
  QuickjsUiEventDispatcher(this.onEvent, {this.maxPendingEvents = 64})
    : assert(maxPendingEvents > 0, 'maxPendingEvents must be > 0');

  final QuickjsUiEventHandler onEvent;
  final int maxPendingEvents;
  final Map<String, _PendingUiEvent> _pendingEvents =
      <String, _PendingUiEvent>{};
  final Map<String, DateTime> _lastDispatchAt = <String, DateTime>{};

  void dispatch(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
  }) {
    final merged = payload == null
        ? event
        : <String, Object?>{...event, ...payload};
    final policy = _QuickjsUiEventPolicy.from(merged, defaultCoalesceKey);
    final key = policy.coalesceKey;
    if (key == null || (!policy.hasTiming && payload == null)) {
      onEvent(merged);
      return;
    }
    final now = DateTime.now();
    final dropMs = policy.dropMs;
    if (dropMs != null) {
      final last = _lastDispatchAt[key];
      if (last != null && now.difference(last).inMilliseconds < dropMs) {
        return;
      }
      _lastDispatchAt[key] = now;
      onEvent(merged);
      return;
    }
    final throttleMs = policy.throttleMs;
    if (throttleMs != null) {
      final last = _lastDispatchAt[key];
      if (last != null && now.difference(last).inMilliseconds < throttleMs) {
        _schedulePending(key, merged, policy.remaining(last, now));
        return;
      }
      _lastDispatchAt[key] = now;
      onEvent(merged);
      return;
    }
    final debounceMs = policy.debounceMs;
    if (debounceMs != null) {
      _schedulePending(key, merged, Duration(milliseconds: debounceMs));
      return;
    }
    onEvent(merged);
  }

  void dispose() {
    for (final pending in _pendingEvents.values) {
      pending.timer.cancel();
    }
    _pendingEvents.clear();
    _lastDispatchAt.clear();
  }

  void _schedulePending(
    String key,
    Map<String, Object?> event,
    Duration delay,
  ) {
    _pendingEvents.remove(key)?.timer.cancel();
    if (_pendingEvents.length >= maxPendingEvents) {
      final oldestKey = _pendingEvents.keys.first;
      _pendingEvents.remove(oldestKey)?.timer.cancel();
    }
    _pendingEvents[key] = _PendingUiEvent(
      event: event,
      timer: Timer(delay, () {
        final pending = _pendingEvents.remove(key);
        if (pending == null) {
          return;
        }
        _lastDispatchAt[key] = DateTime.now();
        onEvent(pending.event);
      }),
    );
  }
}

extension on QuickjsUiRenderContext {
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
      'surfacecontainerhighest' => scheme.surfaceContainerHighest,
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

final class _QuickjsUiEventPolicy {
  const _QuickjsUiEventPolicy({
    required this.throttleMs,
    required this.debounceMs,
    required this.dropMs,
    required this.coalesceKey,
  });

  factory _QuickjsUiEventPolicy.from(
    Map<String, Object?> event,
    String? defaultCoalesceKey,
  ) {
    final policy = QuickjsUiProps.map(event['policy'], name: 'event policy');
    return _QuickjsUiEventPolicy(
      throttleMs: _durationMs(event['throttleMs'] ?? policy['throttleMs']),
      debounceMs: _durationMs(event['debounceMs'] ?? policy['debounceMs']),
      dropMs: _durationMs(event['dropMs'] ?? policy['dropMs']),
      coalesceKey:
          QuickjsUiProps.string(
            event['coalesceKey'] ?? policy['coalesceKey'],
          ) ??
          defaultCoalesceKey,
    );
  }

  final int? throttleMs;
  final int? debounceMs;
  final int? dropMs;
  final String? coalesceKey;

  bool get hasTiming =>
      throttleMs != null || debounceMs != null || dropMs != null;

  Duration remaining(DateTime last, DateTime now) {
    final elapsed = now.difference(last).inMilliseconds;
    final waitMs = (throttleMs ?? 0) - elapsed;
    return Duration(milliseconds: waitMs <= 0 ? 0 : waitMs);
  }

  static int? _durationMs(Object? value) {
    if (value == null) {
      return null;
    }
    final number = QuickjsUiProps.intValue(
      value,
      name: 'event policy duration',
    );
    if (number == null || number < 0) {
      throw const FormatException(
        'quickjs_ui event policy duration must be >= 0',
      );
    }
    return number;
  }
}

final class _PendingUiEvent {
  const _PendingUiEvent({required this.event, required this.timer});

  final Map<String, Object?> event;
  final Timer timer;
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
