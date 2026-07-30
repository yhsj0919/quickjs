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

typedef QuickjsUiEventHandler = void Function(Map<String, Object?> event);
typedef QuickjsUiEventEnvelopeHandler =
    void Function(QuickjsUiEventEnvelope event);
typedef QuickjsUiNodeBuilder = Widget Function(QuickjsUiNode node);
typedef QuickjsUiPathNodeBuilder =
    Widget Function(QuickjsUiNode node, String path);

enum QuickjsUiEventKind { command, sample }

final class QuickjsUiEventEnvelope {
  QuickjsUiEventEnvelope({
    required Map<String, Object?> event,
    required this.kind,
    this.coalesceKey,
  }) : event = Map<String, Object?>.unmodifiable(event);

  factory QuickjsUiEventEnvelope.command(Map<String, Object?> event) {
    return QuickjsUiEventEnvelope(
      event: event,
      kind: QuickjsUiEventKind.command,
    );
  }

  factory QuickjsUiEventEnvelope.sample(
    Map<String, Object?> event, {
    required String coalesceKey,
  }) {
    return QuickjsUiEventEnvelope(
      event: event,
      kind: QuickjsUiEventKind.sample,
      coalesceKey: coalesceKey,
    );
  }

  final Map<String, Object?> event;
  final QuickjsUiEventKind kind;
  final String? coalesceKey;

  QuickjsUiEventEnvelope asCommand() {
    if (kind == QuickjsUiEventKind.command) {
      return this;
    }
    return QuickjsUiEventEnvelope.command(event);
  }
}

final class QuickjsUiRenderContext {
  QuickjsUiRenderContext({
    required QuickjsUiNodeBuilder buildNode,
    required QuickjsUiEventEnvelopeHandler onUiEvent,
    QuickjsUiEventHandler? onEvent,
    QuickjsUiEventDispatcher? eventDispatcher,
    QuickjsUiPathNodeBuilder? buildNodeAtPath,
    String path = '0',
    this.buildContext,
    QuickjsUiCanvasSceneRegistry? canvasSceneRegistry,
    QuickjsUiSnapshotRegistry? snapshotRegistry,
    QuickjsUiPerformanceController? performanceController,
    QuickjsUiFrameScheduler? frameScheduler,
    this.networkResourceBaseUri,
  }) : _buildNode = buildNode,
       _buildNodeAtPath = buildNodeAtPath,
       _onUiEvent = onUiEvent,
       canvasSceneRegistry =
           canvasSceneRegistry ?? QuickjsUiCanvasSceneRegistry(),
       snapshotRegistry = snapshotRegistry ?? QuickjsUiSnapshotRegistry(),
       performanceController =
           performanceController ?? QuickjsUiPerformanceController(),
       frameScheduler = frameScheduler ?? QuickjsUiFrameScheduler(),
       onEvent =
           onEvent ??
           ((event) => onUiEvent(QuickjsUiEventEnvelope.command(event))),
       _eventDispatcher = eventDispatcher,
       _path = path;

  final QuickjsUiNodeBuilder _buildNode;
  final QuickjsUiPathNodeBuilder? _buildNodeAtPath;
  final QuickjsUiEventEnvelopeHandler _onUiEvent;
  final QuickjsUiEventHandler onEvent;
  final QuickjsUiEventDispatcher? _eventDispatcher;
  final String _path;
  final BuildContext? buildContext;
  final QuickjsUiCanvasSceneRegistry canvasSceneRegistry;
  final QuickjsUiSnapshotRegistry snapshotRegistry;
  final QuickjsUiPerformanceController performanceController;
  final QuickjsUiFrameScheduler frameScheduler;
  final Uri? networkResourceBaseUri;

  QuickjsUiRenderContext withPath(String path) {
    return QuickjsUiRenderContext(
      buildNode: _buildNode,
      buildNodeAtPath: _buildNodeAtPath,
      onUiEvent: _onUiEvent,
      onEvent: onEvent,
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

  Color? color(Object? value) {
    return QuickjsUiProps.color(value, resolveColor: _themeColor);
  }

  TextStyle? textStyle(Object? value) {
    return QuickjsUiProps.textStyle(
      value,
      resolveColor: _themeColor,
      resolveTextStyle: _themeTextStyle,
      resolveNumber: _fontToken,
    );
  }

  BoxDecoration? boxDecoration(Map<String, Object?> props) {
    return QuickjsUiProps.boxDecoration(
      props,
      resolveColor: _themeColor,
      resolveRadius: _radiusToken,
      resolveBorderWidth: _spacingToken,
    );
  }

  EdgeInsetsGeometry? edgeInsets(Object? value) {
    return QuickjsUiProps.edgeInsets(value, resolveNumber: _spacingToken);
  }

  BorderRadiusGeometry? borderRadius(Object? value) {
    return QuickjsUiProps.borderRadius(value, resolveNumber: _radiusToken);
  }

  double? spacing(Object? value, {String name = 'spacing'}) {
    return QuickjsUiProps.number(
      value,
      name: name,
      resolveNumber: _spacingToken,
    );
  }

  double? radius(Object? value, {String name = 'radius'}) {
    return QuickjsUiProps.number(
      value,
      name: name,
      resolveNumber: _radiusToken,
    );
  }

  double? elevation(Object? value, {String name = 'elevation'}) {
    return QuickjsUiProps.number(
      value,
      name: name,
      resolveNumber: _elevationToken,
    );
  }

  QuickjsUiResourceReference resource(
    Object? value, {
    String name = 'resource',
  }) {
    final resource = QuickjsUiResourceReference.parse(value, name: name);
    final baseUri = networkResourceBaseUri;
    if (baseUri == null || resource.kind != QuickjsUiResourceKind.asset) {
      return resource;
    }
    return QuickjsUiResourceReference(
      location: baseUri.resolve(resource.location).toString(),
      kind: QuickjsUiResourceKind.network,
      mimeType: resource.mimeType,
      sha256: resource.sha256,
      cacheKey: resource.cacheKey,
      headers: resource.headers,
    );
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
    return _buildChild(node, 0);
  }

  List<Widget> children(QuickjsUiNode node) {
    return <Widget>[
      for (var index = 0; index < node.children.length; index += 1)
        _buildChild(node, index),
    ];
  }

  /// Builds a named structural slot stored in [node.props].
  ///
  /// Slots use the same JSON node shape as `child`, while keeping independent
  /// structural paths so retained rendering and keyed state continue to work.
  Widget? slot(QuickjsUiNode node, String name) {
    final value = node.props[name];
    if (value == null) {
      return null;
    }
    final slotNode = QuickjsUiNode.fromMap(
      QuickjsUiProps.map(value, name: '$name slot'),
    );
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
  Widget childAt(QuickjsUiNode node, int index) {
    RangeError.checkValidIndex(index, node.children, 'index');
    return _buildChild(node, index);
  }

  Widget _buildChild(QuickjsUiNode node, int index) {
    final child = node.children[index];
    final builder = _buildNodeAtPath;
    if (builder == null) {
      return build(child);
    }
    return builder(child, '$_path/$index');
  }

  void dispatch(Map<String, Object?> event) {
    _onUiEvent(QuickjsUiEventEnvelope.command(event));
  }

  void dispatchEvent(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
    QuickjsUiEventKind kind = QuickjsUiEventKind.command,
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

final class QuickjsUiEventDispatcher {
  QuickjsUiEventDispatcher(this.onEvent, {this.maxPendingEvents = 64})
    : assert(maxPendingEvents > 0, 'maxPendingEvents must be > 0');

  final QuickjsUiEventEnvelopeHandler onEvent;
  final int maxPendingEvents;
  final Map<String, _PendingUiEvent> _pendingEvents =
      <String, _PendingUiEvent>{};
  final Map<String, DateTime> _lastDispatchAt = <String, DateTime>{};
  void dispatch(
    Map<String, Object?> event, {
    Map<String, Object?>? payload,
    String? defaultCoalesceKey,
    QuickjsUiEventKind kind = QuickjsUiEventKind.command,
  }) {
    final merged = payload == null
        ? event
        : <String, Object?>{...event, ...payload};
    final policy = _QuickjsUiEventPolicy.from(merged, defaultCoalesceKey);
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

  void dispose() {
    for (final pending in _pendingEvents.values) {
      pending.timer.cancel();
    }
    _pendingEvents.clear();
    _lastDispatchAt.clear();
  }

  void _schedulePending(
    String key,
    QuickjsUiEventEnvelope event,
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
    final extension = Theme.of(context).extension<QuickjsUiDesignTokens>();
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
    final extension = Theme.of(context).extension<QuickjsUiDesignTokens>();
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
    return _designNumber(value, QuickjsUiTokenCategory.spacing);
  }

  double? _radiusToken(Object? value) {
    return _designNumber(value, QuickjsUiTokenCategory.radius);
  }

  double? _elevationToken(Object? value) {
    return _designNumber(value, QuickjsUiTokenCategory.elevation);
  }

  double? _fontToken(Object? value) {
    return _designNumber(value, QuickjsUiTokenCategory.fontSize);
  }

  double? _designNumber(Object? value, QuickjsUiTokenCategory category) {
    if (value is! String || !value.startsWith(r'$')) {
      return null;
    }
    final context = buildContext;
    final extension = context == null
        ? null
        : Theme.of(context).extension<QuickjsUiDesignTokens>();
    return extension?.number(value, category) ??
        QuickjsUiDesignTokens().number(value, category);
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

  final QuickjsUiEventEnvelope event;
  final Timer timer;
}

QuickjsUiEventEnvelope _eventEnvelope(
  Map<String, Object?> event, {
  required QuickjsUiEventKind kind,
  String? coalesceKey,
}) {
  final key = _coalesceKey(event) ?? coalesceKey;
  final payload = _eventPayload(event);
  if (kind == QuickjsUiEventKind.sample && key != null) {
    return QuickjsUiEventEnvelope.sample(payload, coalesceKey: key);
  }
  return QuickjsUiEventEnvelope.command(payload);
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
  var token = QuickjsUiDesignTokens.normalizeToken(value);
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
