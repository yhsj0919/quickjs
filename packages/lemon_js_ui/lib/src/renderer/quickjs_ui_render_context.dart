import 'dart:async';

import 'package:flutter/material.dart';

import '../resource/quickjs_ui_resource.dart';
import '../performance/quickjs_ui_effect_quality.dart';
import '../schema/quickjs_ui_node.dart';
import '../schema/quickjs_ui_props.dart';
import '../theme/quickjs_ui_design_tokens.dart';
import 'quickjs_ui_canvas_scene.dart';
import 'quickjs_ui_frame_scheduler.dart';
import 'quickjs_ui_snapshot.dart';

// Keep the public constructor parameter named `buildNode`.
// ignore_for_file: prefer_initializing_formals

/// Handles a raw component event map.
typedef JsUiEventHandler = void Function(Map<String, Object?> event);

/// Handles an event with loss and coalescing semantics.
typedef JsUiEventEnvelopeHandler = void Function(JsUiEventEnvelope event);

/// Builds a Flutter widget for a schema node.
typedef JsUiNodeBuilder = Widget Function(JsUiNode node);

/// Builds a node at its stable structural [path].
typedef JsUiPathNodeBuilder = Widget Function(JsUiNode node, String path);

/// UI 事件的调度类型。
///
/// [command] 表示不可丢失的离散操作，例如点击；[sample] 表示可按
/// [JsUiEventEnvelope.coalesceKey] 合并的连续采样，例如滚动位置。
enum JsUiEventKind {
  /// A discrete event that must not be discarded.
  command,

  /// A continuous value that may replace an older sample with the same key.
  sample,
}

/// 从 Flutter 渲染层发送到 JavaScript 页面的事件。
final class JsUiEventEnvelope {
  /// Creates an event envelope with explicit delivery semantics.
  JsUiEventEnvelope({
    required Map<String, Object?> event,
    required this.kind,
    this.coalesceKey,
  }) : event = Map<String, Object?>.unmodifiable(event);

  /// Creates a non-droppable command event.
  factory JsUiEventEnvelope.command(Map<String, Object?> event) {
    return JsUiEventEnvelope(event: event, kind: JsUiEventKind.command);
  }

  /// Creates a coalescible sample event.
  factory JsUiEventEnvelope.sample(
    Map<String, Object?> event, {
    required String coalesceKey,
  }) {
    return JsUiEventEnvelope(
      event: event,
      kind: JsUiEventKind.sample,
      coalesceKey: coalesceKey,
    );
  }

  /// Immutable event payload sent to JavaScript.
  final Map<String, Object?> event;

  /// Delivery semantics for this event.
  final JsUiEventKind kind;

  /// 同一帧内可合并采样事件的稳定键；命令事件不使用该字段。
  final String? coalesceKey;

  /// Returns this payload with non-droppable command semantics.
  JsUiEventEnvelope asCommand() {
    if (kind == JsUiEventKind.command) {
      return this;
    }
    return JsUiEventEnvelope.command(event);
  }
}

/// Rendering services and protocol converters available to components.
final class JsUiRenderContext {
  /// Creates a render context for one structural node path.
  JsUiRenderContext({
    required JsUiNodeBuilder buildNode,
    required JsUiEventEnvelopeHandler onUiEvent,
    JsUiEventDispatcher? eventDispatcher,
    JsUiPathNodeBuilder? buildNodeAtPath,
    String path = '0',
    this.buildContext,
    JsUiCanvasSceneRegistry? canvasSceneRegistry,
    JsUiSnapshotRegistry? snapshotRegistry,
    JsUiPerformanceController? performanceController,
    JsUiFrameScheduler? frameScheduler,
    this.networkResourceBaseUri,
  }) : _buildNode = buildNode,
       _buildNodeAtPath = buildNodeAtPath,
       _onUiEvent = onUiEvent,
       canvasSceneRegistry = canvasSceneRegistry ?? JsUiCanvasSceneRegistry(),
       snapshotRegistry = snapshotRegistry ?? JsUiSnapshotRegistry(),
       performanceController =
           performanceController ?? JsUiPerformanceController(),
       frameScheduler = frameScheduler ?? JsUiFrameScheduler(),
       _eventDispatcher = eventDispatcher,
       _path = path;

  final JsUiNodeBuilder _buildNode;
  final JsUiPathNodeBuilder? _buildNodeAtPath;
  final JsUiEventEnvelopeHandler _onUiEvent;
  final JsUiEventDispatcher? _eventDispatcher;
  final String _path;

  /// Flutter build context used to resolve theme tokens.
  final BuildContext? buildContext;

  /// Registry for retained canvas scenes.
  final JsUiCanvasSceneRegistry canvasSceneRegistry;

  /// Registry for widgets addressable by snapshot components.
  final JsUiSnapshotRegistry snapshotRegistry;

  /// Adaptive quality and performance state.
  final JsUiPerformanceController performanceController;

  /// Scheduler shared by frame-driven components.
  final JsUiFrameScheduler frameScheduler;

  /// Base URL used to resolve package-relative network resources.
  final Uri? networkResourceBaseUri;

  /// Returns a context sharing services but using a different structural [path].
  JsUiRenderContext withPath(String path) {
    return JsUiRenderContext(
      buildNode: _buildNode,
      buildNodeAtPath: _buildNodeAtPath,
      onUiEvent: _onUiEvent,
      eventDispatcher: _eventDispatcher,
      buildContext: buildContext,
      canvasSceneRegistry: canvasSceneRegistry,
      snapshotRegistry: snapshotRegistry,
      performanceController: performanceController,
      frameScheduler: frameScheduler,
      networkResourceBaseUri: networkResourceBaseUri,
      path: path,
    );
  }

  /// Resolves a literal or themed color property.
  Color? color(Object? value) {
    return JsUiProps.color(value, resolveColor: _themeColor);
  }

  /// Resolves a literal or themed text style property.
  TextStyle? textStyle(Object? value) {
    return JsUiProps.textStyle(
      value,
      resolveColor: _themeColor,
      resolveTextStyle: _themeTextStyle,
      resolveNumber: _fontToken,
    );
  }

  /// Resolves a container decoration and its design tokens.
  BoxDecoration? boxDecoration(Map<String, Object?> props) {
    return JsUiProps.boxDecoration(
      props,
      resolveColor: _themeColor,
      resolveRadius: _radiusToken,
      resolveBorderWidth: _spacingToken,
    );
  }

  /// Resolves edge insets and spacing tokens.
  EdgeInsetsGeometry? edgeInsets(Object? value) {
    return JsUiProps.edgeInsets(value, resolveNumber: _spacingToken);
  }

  /// Resolves border radii and radius tokens.
  BorderRadiusGeometry? borderRadius(Object? value) {
    return JsUiProps.borderRadius(value, resolveNumber: _radiusToken);
  }

  /// Resolves a literal value or spacing token.
  double? spacing(Object? value, {String name = 'spacing'}) {
    return JsUiProps.number(value, name: name, resolveNumber: _spacingToken);
  }

  /// Resolves a literal value or radius token.
  double? radius(Object? value, {String name = 'radius'}) {
    return JsUiProps.number(value, name: name, resolveNumber: _radiusToken);
  }

  /// Resolves a literal value or elevation token.
  double? elevation(Object? value, {String name = 'elevation'}) {
    return JsUiProps.number(value, name: name, resolveNumber: _elevationToken);
  }

  /// Parses a resource and resolves relative network package paths.
  JsUiResourceReference resource(Object? value, {String name = 'resource'}) {
    final resource = JsUiResourceReference.parse(value, name: name);
    final baseUri = networkResourceBaseUri;
    if (baseUri == null || resource.kind != JsUiResourceKind.asset) {
      return resource;
    }
    return JsUiResourceReference(
      uri: baseUri.resolve(resource.uri).toString(),
      kind: JsUiResourceKind.network,
      mimeType: resource.mimeType,
      sha256: resource.sha256,
      cacheKey: resource.cacheKey,
      headers: resource.headers,
    );
  }

  /// Builds [node] through the owning renderer.
  Widget build(JsUiNode node) {
    return _buildNode(node);
  }

  /// Builds the sole child of [node], or returns `null` when absent.
  Widget? child(JsUiNode node) {
    if (node.children.isEmpty) {
      return null;
    }
    if (node.children.length > 1) {
      throw FormatException('${node.type} expects a single child');
    }
    return _buildChild(node, 0);
  }

  /// Builds all direct children while preserving their structural paths.
  List<Widget> children(JsUiNode node) {
    return <Widget>[
      for (var index = 0; index < node.children.length; index += 1)
        _buildChild(node, index),
    ];
  }

  /// Builds a named structural slot stored in [node.props].
  ///
  /// Slots use the same JSON node shape as `child`, while keeping independent
  /// structural paths so retained rendering and keyed state continue to work.
  Widget? slot(JsUiNode node, String name) {
    final value = node.props[name];
    if (value == null) {
      return null;
    }
    final slotNode = JsUiNode.fromMap(JsUiProps.map(value, name: '$name slot'));
    final builder = _buildNodeAtPath;
    if (builder == null) {
      return build(slotNode);
    }
    return builder(slotNode, '$_path/@$name');
  }

  /// Builds one child while preserving its structural path.
  ///
  /// Scrollable components use this from their item builders so nodes outside
  /// the viewport do not need to be converted to widgets eagerly.
  Widget childAt(JsUiNode node, int index) {
    RangeError.checkValidIndex(index, node.children, 'index');
    return _buildChild(node, index);
  }

  Widget _buildChild(JsUiNode node, int index) {
    final child = node.children[index];
    final builder = _buildNodeAtPath;
    if (builder == null) {
      return build(child);
    }
    return builder(child, '$_path/$index');
  }

  /// 将组件事件发送给页面。
  ///
  /// [event] 通常包含目标 `method`；[payload] 会覆盖其中的同名字段。
  /// 连续变化事件应传入 [kind] 为 [JsUiEventKind.sample]，并提供稳定的
  /// [defaultCoalesceKey]，使渲染层可以只保留同组中的最新采样值。
  void dispatch(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
    JsUiEventKind kind = JsUiEventKind.command,
  }) {
    final dispatcher = _eventDispatcher;
    final merged = payload == null
        ? event
        : <String, Object?>{...event, ...payload};
    if (dispatcher != null) {
      dispatcher.dispatch(
        event,
        payload: payload,
        defaultCoalesceKey: defaultCoalesceKey,
        kind: kind,
      );
      return;
    }
    _onUiEvent(
      _eventEnvelope(merged, kind: kind, coalesceKey: defaultCoalesceKey),
    );
  }
}

/// Applies throttling, debouncing, dropping, and sample coalescing to events.
final class JsUiEventDispatcher {
  /// 创建带节流、去抖和采样合并能力的事件调度器。
  ///
  /// [maxPendingEvents] 只限制正在等待定时发送的不同合并键数量；立即发送的
  /// 命令不占用该数量。达到限制时会取消并移除最早的等待事件。
  JsUiEventDispatcher(this.onEvent, {this.maxPendingEvents = 64})
    : assert(maxPendingEvents > 0, 'maxPendingEvents must be > 0');

  /// Receives events after their timing policy is applied.
  final JsUiEventEnvelopeHandler onEvent;

  /// 最多同时等待发送的合并事件数量。
  final int maxPendingEvents;
  final Map<String, _PendingUiEvent> _pendingEvents =
      <String, _PendingUiEvent>{};
  final Map<String, DateTime> _lastDispatchAt = <String, DateTime>{};

  /// Dispatches an event according to its embedded timing policy.
  void dispatch(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
    JsUiEventKind kind = JsUiEventKind.command,
  }) {
    final merged = payload == null
        ? event
        : <String, Object?>{...event, ...payload};
    final policy = _JsUiEventPolicy.from(merged, defaultCoalesceKey);
    final key = policy.coalesceKey;
    final envelope = _eventEnvelope(merged, kind: kind, coalesceKey: key);
    if (key == null || (!policy.hasTiming && payload == null)) {
      onEvent(envelope);
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
      onEvent(envelope);
      return;
    }
    final throttleMs = policy.throttleMs;
    if (throttleMs != null) {
      final last = _lastDispatchAt[key];
      if (last != null && now.difference(last).inMilliseconds < throttleMs) {
        _schedulePending(key, envelope, policy.remaining(last, now));
        return;
      }
      _lastDispatchAt[key] = now;
      onEvent(envelope);
      return;
    }
    final debounceMs = policy.debounceMs;
    if (debounceMs != null) {
      _schedulePending(key, envelope, Duration(milliseconds: debounceMs));
      return;
    }
    onEvent(envelope);
  }

  /// Cancels every pending event and releases scheduler state.
  void dispose() {
    for (final pending in _pendingEvents.values) {
      pending.timer.cancel();
    }
    _pendingEvents.clear();
    _lastDispatchAt.clear();
  }

  void _schedulePending(String key, JsUiEventEnvelope event, Duration delay) {
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

extension on JsUiRenderContext {
  Color? _themeColor(Object? value) {
    final context = buildContext;
    if (context == null || value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final extension = Theme.of(context).extension<JsUiDesignTokens>();
    final custom = extension?.color(value);
    if (custom != null) {
      return custom;
    }
    final scheme = Theme.of(context).colorScheme;
    return switch (_normalizeToken(value)) {
      'primary' => scheme.primary,
      'onprimary' => scheme.onPrimary,
      'primarycontainer' => scheme.primaryContainer,
      'onprimarycontainer' => scheme.onPrimaryContainer,
      'primaryfixed' => scheme.primaryFixed,
      'primaryfixeddim' => scheme.primaryFixedDim,
      'onprimaryfixed' => scheme.onPrimaryFixed,
      'onprimaryfixedvariant' => scheme.onPrimaryFixedVariant,
      'secondary' => scheme.secondary,
      'onsecondary' => scheme.onSecondary,
      'secondarycontainer' => scheme.secondaryContainer,
      'onsecondarycontainer' => scheme.onSecondaryContainer,
      'secondaryfixed' => scheme.secondaryFixed,
      'secondaryfixeddim' => scheme.secondaryFixedDim,
      'onsecondaryfixed' => scheme.onSecondaryFixed,
      'onsecondaryfixedvariant' => scheme.onSecondaryFixedVariant,
      'tertiary' => scheme.tertiary,
      'ontertiary' => scheme.onTertiary,
      'tertiarycontainer' => scheme.tertiaryContainer,
      'ontertiarycontainer' => scheme.onTertiaryContainer,
      'tertiaryfixed' => scheme.tertiaryFixed,
      'tertiaryfixeddim' => scheme.tertiaryFixedDim,
      'ontertiaryfixed' => scheme.onTertiaryFixed,
      'ontertiaryfixedvariant' => scheme.onTertiaryFixedVariant,
      'surface' => scheme.surface,
      'onsurface' => scheme.onSurface,
      'onsurfacevariant' => scheme.onSurfaceVariant,
      'surfacebright' => scheme.surfaceBright,
      'surfacedim' => scheme.surfaceDim,
      'surfacecontainerlowest' => scheme.surfaceContainerLowest,
      'surfacecontainerlow' => scheme.surfaceContainerLow,
      'surfacecontainer' => scheme.surfaceContainer,
      'surfacecontainerhigh' => scheme.surfaceContainerHigh,
      'surfacecontainerhighest' => scheme.surfaceContainerHighest,
      'surfacevariant' => scheme.surfaceContainerHighest,
      'background' => scheme.surface,
      'onbackground' => scheme.onSurface,
      'error' => scheme.error,
      'onerror' => scheme.onError,
      'errorcontainer' => scheme.errorContainer,
      'onerrorcontainer' => scheme.onErrorContainer,
      'outline' => scheme.outline,
      'outlinevariant' => scheme.outlineVariant,
      'shadow' => scheme.shadow,
      'scrim' => scheme.scrim,
      'inversesurface' => scheme.inverseSurface,
      'oninversesurface' => scheme.onInverseSurface,
      'inverseprimary' => scheme.inversePrimary,
      'surfacetint' => scheme.surfaceTint,
      _ => null,
    };
  }

  TextStyle? _themeTextStyle(Object? value) {
    final context = buildContext;
    if (context == null || value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final extension = Theme.of(context).extension<JsUiDesignTokens>();
    final custom = extension?.textStyle(value);
    if (custom != null) {
      return custom;
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

  double? _spacingToken(Object? value) {
    return _designNumber(value, JsUiTokenCategory.spacing);
  }

  double? _radiusToken(Object? value) {
    return _designNumber(value, JsUiTokenCategory.radius);
  }

  double? _elevationToken(Object? value) {
    return _designNumber(value, JsUiTokenCategory.elevation);
  }

  double? _fontToken(Object? value) {
    return _designNumber(value, JsUiTokenCategory.fontSize);
  }

  double? _designNumber(Object? value, JsUiTokenCategory category) {
    if (value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final context = buildContext;
    final extension = context == null
        ? null
        : Theme.of(context).extension<JsUiDesignTokens>();
    return extension?.number(value, category) ??
        JsUiDesignTokens().number(value, category);
  }
}

final class _JsUiEventPolicy {
  const _JsUiEventPolicy({
    required this.throttleMs,
    required this.debounceMs,
    required this.dropMs,
    required this.coalesceKey,
  });

  factory _JsUiEventPolicy.from(
    Map<String, Object?> event,
    String? defaultCoalesceKey,
  ) {
    final policy = JsUiProps.map(event['policy'], name: 'event policy');
    return _JsUiEventPolicy(
      throttleMs: _durationMs(event['throttleMs'] ?? policy['throttleMs']),
      debounceMs: _durationMs(event['debounceMs'] ?? policy['debounceMs']),
      dropMs: _durationMs(event['dropMs'] ?? policy['dropMs']),
      coalesceKey:
          JsUiProps.string(event['coalesceKey'] ?? policy['coalesceKey']) ??
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
    final number = JsUiProps.intValue(value, name: 'event policy duration');
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

  final JsUiEventEnvelope event;
  final Timer timer;
}

JsUiEventEnvelope _eventEnvelope(
  Map<String, Object?> event, {
  required JsUiEventKind kind,
  String? coalesceKey,
}) {
  final key = _coalesceKey(event) ?? coalesceKey;
  final payload = _eventPayload(event);
  if (kind == JsUiEventKind.sample && key != null) {
    return JsUiEventEnvelope.sample(payload, coalesceKey: key);
  }
  return JsUiEventEnvelope.command(payload);
}

String? _coalesceKey(Map<String, Object?> event) {
  final value = event['coalesceKey'];
  if (value is String && value.isNotEmpty) {
    return value;
  }
  final policy = event['policy'];
  if (policy is Map) {
    final policyKey = policy['coalesceKey'];
    if (policyKey is String && policyKey.isNotEmpty) {
      return policyKey;
    }
  }
  return null;
}

Map<String, Object?> _eventPayload(Map<String, Object?> event) {
  final copy = Map<String, Object?>.from(event);
  copy
    ..remove('policy')
    ..remove('throttleMs')
    ..remove('debounceMs')
    ..remove('dropMs')
    ..remove('coalesceKey');
  return copy;
}

String _normalizeToken(String value) {
  var token = JsUiDesignTokens.normalizeToken(value);
  for (final prefix in <String>[
    'texttheme',
    'theme',
    'colors',
    'color',
    'text',
  ]) {
    if (token.startsWith(prefix)) {
      token = token.substring(prefix.length);
      break;
    }
  }
  return token.replaceAll(RegExp(r'[^a-z0-9]'), '');
}
