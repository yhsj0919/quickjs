import 'quickjs_extension_registry.dart';

/// Core 方法调用的标准状态。
enum QuickjsExtensionCallStatus { ok, interactionRequired, error }

/// 统一解析后的 Core 方法调用结果。
final class QuickjsExtensionCallResult {
  const QuickjsExtensionCallResult._({
    required this.status,
    this.data,
    this.flow,
    this.reason,
    this.error,
    this.raw = const <String, Object?>{},
  });

  factory QuickjsExtensionCallResult.parse(Object? value) {
    if (value is! Map) {
      throw const FormatException('Extension service result must be an object');
    }
    final map = value.map((key, item) => MapEntry('$key', item));
    return switch (map['status']) {
      'ok' => QuickjsExtensionCallResult._(
        status: QuickjsExtensionCallStatus.ok,
        data: map['data'],
        raw: map,
      ),
      'interactionRequired' => _interactionResult(map),
      'error' => QuickjsExtensionCallResult._(
        status: QuickjsExtensionCallStatus.error,
        error: map['error'],
        raw: map,
      ),
      final Object? status => throw FormatException(
        'Unsupported extension service result status: $status',
      ),
    };
  }

  final QuickjsExtensionCallStatus status;
  final Object? data;
  final String? flow;
  final String? reason;
  final Object? error;
  final Map<String, Object?> raw;
}

/// UI 交互流程的结束状态。
enum QuickjsExtensionFlowStatus { completed, cancelled, failed }

/// UI 交互流程返回给宿主的结果。
final class QuickjsExtensionFlowResult {
  const QuickjsExtensionFlowResult.completed([this.data])
    : status = QuickjsExtensionFlowStatus.completed,
      error = null;

  const QuickjsExtensionFlowResult.cancelled()
    : status = QuickjsExtensionFlowStatus.cancelled,
      data = null,
      error = null;

  const QuickjsExtensionFlowResult.failed(this.error)
    : status = QuickjsExtensionFlowStatus.failed,
      data = null;

  final QuickjsExtensionFlowStatus status;
  final Object? data;
  final Object? error;
}

/// 打开扩展 UI 交互流程的回调。
typedef QuickjsExtensionFlowLauncher =
    Future<QuickjsExtensionFlowResult> Function(
      QuickjsExtensionFlowReference flow,
      Map<String, Object?> initialProps,
    );

/// 在 Core 请求交互时打开 UI，并最多重试原调用一次。
final class QuickjsExtensionFlowRunner {
  const QuickjsExtensionFlowRunner({
    required this.registry,
    required this.launch,
  });

  final QuickjsExtensionRegistry registry;
  final QuickjsExtensionFlowLauncher launch;

  Future<QuickjsExtensionCallResult> call(
    String extensionId,
    String method, {
    List<Object?> arguments = const <Object?>[],
    Map<String, Object?> flowProps = const <String, Object?>{},
    Duration? timeout,
  }) async {
    final installed = registry.find(extensionId);
    if (installed == null || !installed.enabled) {
      throw StateError('QuickJS extension is unavailable: $extensionId');
    }
    final first = QuickjsExtensionCallResult.parse(
      await installed.session.callPublic(
        method,
        arguments: arguments,
        timeout: timeout,
      ),
    );
    if (first.status != QuickjsExtensionCallStatus.interactionRequired) {
      return first;
    }
    final flowId = first.flow!;
    final flow = registry.findFlow(extensionId, flowId);
    if (flow == null) {
      throw StateError(
        'QuickJS extension "$extensionId" requested unavailable flow "$flowId"',
      );
    }
    final interaction = await launch(flow, <String, Object?>{
      ...flowProps,
      if (first.reason != null) 'reason': first.reason,
    });
    if (interaction.status != QuickjsExtensionFlowStatus.completed) {
      return first;
    }
    final retry = QuickjsExtensionCallResult.parse(
      await installed.session.callPublic(
        method,
        arguments: arguments,
        timeout: timeout,
      ),
    );
    if (retry.status == QuickjsExtensionCallStatus.interactionRequired) {
      throw StateError(
        'QuickJS extension "$extensionId" still requires interaction after '
        'flow "$flowId" completed',
      );
    }
    return retry;
  }
}

QuickjsExtensionCallResult _interactionResult(Map<String, Object?> map) {
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
  return QuickjsExtensionCallResult._(
    status: QuickjsExtensionCallStatus.interactionRequired,
    flow: flow,
    reason: reason as String?,
    raw: map,
  );
}
