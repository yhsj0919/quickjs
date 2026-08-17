import 'extension_registry.dart';

/// Core 方法调用的标准状态。
enum JsExtensionCallStatus {
  /// The service call completed successfully.
  ok,

  /// The service requires a declared UI flow before retrying.
  interactionRequired,

  /// The service returned a business error.
  error,
}

/// 统一解析后的 Core 方法调用结果。
final class JsExtensionCallResult {
  const JsExtensionCallResult._({
    required this.status,
    this.data,
    this.flow,
    this.reason,
    this.error,
    this.raw = const <String, Object?>{},
  });

  /// Parses the standard service result envelope.
  factory JsExtensionCallResult.parse(Object? value) {
    if (value is! Map) {
      throw const FormatException('Extension service result must be an object');
    }
    final map = value.map((key, item) => MapEntry('$key', item));
    return switch (map['status']) {
      'ok' => JsExtensionCallResult._(
        status: JsExtensionCallStatus.ok,
        data: map['data'],
        raw: map,
      ),
      'interactionRequired' => _interactionResult(map),
      'error' => JsExtensionCallResult._(
        status: JsExtensionCallStatus.error,
        error: map['error'],
        raw: map,
      ),
      final Object? status => throw FormatException(
        'Unsupported extension service result status: $status',
      ),
    };
  }

  /// Standard result status.
  final JsExtensionCallStatus status;

  /// Successful business result.
  final Object? data;

  /// Requested UI flow identifier.
  final String? flow;

  /// Optional reason presented to the interaction flow.
  final String? reason;

  /// Business error returned by the service.
  final Object? error;

  /// Original normalized result envelope.
  final Map<String, Object?> raw;
}

/// UI 交互流程的结束状态。
enum JsExtensionFlowStatus {
  /// The user completed the interaction.
  completed,

  /// The user cancelled the interaction.
  cancelled,

  /// The interaction failed.
  failed,
}

/// UI 交互流程返回给宿主的结果。
final class JsExtensionFlowResult {
  /// Creates a completed interaction with optional [data].
  const JsExtensionFlowResult.completed([this.data])
    : status = JsExtensionFlowStatus.completed,
      error = null;

  /// Creates a user-cancelled interaction.
  const JsExtensionFlowResult.cancelled()
    : status = JsExtensionFlowStatus.cancelled,
      data = null,
      error = null;

  /// Creates a failed interaction carrying [error].
  const JsExtensionFlowResult.failed(this.error)
    : status = JsExtensionFlowStatus.failed,
      data = null;

  /// Interaction completion status.
  final JsExtensionFlowStatus status;

  /// Data returned by a completed interaction.
  final Object? data;

  /// Error returned by a failed interaction.
  final Object? error;
}

/// 打开扩展 UI 交互流程的回调。
typedef JsExtensionFlowLauncher =
    Future<JsExtensionFlowResult> Function(
      JsExtensionFlowReference flow,
      Map<String, Object?> initialProps,
    );

/// 在 Core 请求交互时打开 UI，并最多重试原调用一次。
final class JsExtensionFlowRunner {
  /// Creates a flow runner backed by [registry] and [launch].
  const JsExtensionFlowRunner({required this.registry, required this.launch});

  /// Registry used to resolve extensions and declared flows.
  final JsExtensionRegistry registry;

  /// Host callback that presents a flow to the user.
  final JsExtensionFlowLauncher launch;

  /// 调用 Core 方法；需要交互时打开对应 UI 流程，并在完成后重试一次。
  ///
  /// UI 流程取消或失败时不重试，返回原始的
  /// [JsExtensionCallStatus.interactionRequired] 结果，由调用方决定后续行为。
  Future<JsExtensionCallResult> call(
    String extensionId,
    String method, {
    List<Object?> arguments = const <Object?>[],
    Map<String, Object?> flowProps = const <String, Object?>{},
    Duration? timeout,
  }) async {
    final installed = registry.find(extensionId);
    if (installed == null || !installed.enabled) {
      throw StateError('JS extension is unavailable: $extensionId');
    }
    final first = JsExtensionCallResult.parse(
      await installed.session.callPublic(
        method,
        arguments: arguments,
        timeout: timeout,
      ),
    );
    if (first.status != JsExtensionCallStatus.interactionRequired) {
      return first;
    }
    final flowId = first.flow!;
    final flow = registry.findFlow(extensionId, flowId);
    if (flow == null) {
      throw StateError(
        'JS extension "$extensionId" requested unavailable flow "$flowId"',
      );
    }
    final interaction = await launch(flow, <String, Object?>{
      ...flowProps,
      if (first.reason != null) 'reason': first.reason,
    });
    if (interaction.status != JsExtensionFlowStatus.completed) {
      return first;
    }
    final retry = JsExtensionCallResult.parse(
      await installed.session.callPublic(
        method,
        arguments: arguments,
        timeout: timeout,
      ),
    );
    if (retry.status == JsExtensionCallStatus.interactionRequired) {
      throw StateError(
        'JS extension "$extensionId" still requires interaction after '
        'flow "$flowId" completed',
      );
    }
    return retry;
  }
}

JsExtensionCallResult _interactionResult(Map<String, Object?> map) {
  final interaction = map['interaction'];
  if (interaction is! Map) {
    throw const FormatException(
      'interactionRequired result must contain interaction object',
    );
  }
  final normalized = interaction.map((key, value) => MapEntry('$key', value));
  final flow = normalized['flow'];
  if (flow is! String || flow.isEmpty) {
    throw const FormatException(
      'interactionRequired result must contain interaction.flow',
    );
  }
  final reason = normalized['reason'];
  if (reason != null && reason is! String) {
    throw const FormatException('interaction.reason must be a string');
  }
  return JsExtensionCallResult._(
    status: JsExtensionCallStatus.interactionRequired,
    flow: flow,
    reason: reason as String?,
    raw: map,
  );
}
