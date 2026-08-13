import 'package:lemon_js/lemon_js.dart';

enum QuickjsUiErrorKind {
  load,
  runtime,
  dispatch,
  lifecycle,
  state,
  render,
  schema,
  resource,
  network,
  permission,
  disposed,
  unknown,
}

final class QuickjsUiErrorContext {
  const QuickjsUiErrorContext({
    this.operation,
    this.action,
    this.lifecycle,
    this.route,
    this.source,
    this.resource,
    this.schemaPath,
  });

  final String? operation;
  final String? action;
  final String? lifecycle;
  final String? route;
  final String? source;
  final String? resource;
  final String? schemaPath;
}

final class QuickjsUiError implements Exception {
  const QuickjsUiError({
    required this.kind,
    required this.message,
    required this.cause,
    this.stackTrace,
    this.operation,
    this.action,
    this.lifecycle,
    this.route,
    this.source,
    this.resource,
    this.schemaPath,
  });

  factory QuickjsUiError.wrap(
    Object cause, {
    required QuickjsUiErrorKind kind,
    String? message,
    StackTrace? stackTrace,
    String? operation,
    String? action,
    String? lifecycle,
    String? route,
    String? source,
    String? resource,
    String? schemaPath,
    QuickjsUiErrorContext context = const QuickjsUiErrorContext(),
  }) {
    if (cause is QuickjsUiError) {
      return cause.withContext(
        kind: cause.kind == QuickjsUiErrorKind.unknown ? kind : null,
        operation: operation ?? context.operation,
        action: action ?? context.action,
        lifecycle: lifecycle ?? context.lifecycle,
        route: route ?? context.route,
        source: source ?? context.source,
        resource: resource ?? context.resource,
        schemaPath: schemaPath ?? context.schemaPath,
      );
    }
    return QuickjsUiError(
      kind: kind,
      message: message ?? _messageFor(cause),
      cause: cause,
      stackTrace: stackTrace ?? _stackFor(cause),
      operation: operation ?? context.operation,
      action: action ?? context.action,
      lifecycle: lifecycle ?? context.lifecycle,
      route: route ?? context.route,
      source: source ?? context.source,
      resource: resource ?? context.resource,
      schemaPath: schemaPath ?? context.schemaPath,
    );
  }

  final QuickjsUiErrorKind kind;
  final String message;
  final Object cause;
  final StackTrace? stackTrace;
  final String? operation;
  final String? action;
  final String? lifecycle;
  final String? route;
  final String? source;
  final String? resource;
  final String? schemaPath;

  QuickjsUiError withContext({
    QuickjsUiErrorKind? kind,
    String? operation,
    String? action,
    String? lifecycle,
    String? route,
    String? source,
    String? resource,
    String? schemaPath,
  }) {
    return QuickjsUiError(
      kind: kind ?? this.kind,
      message: message,
      cause: cause,
      stackTrace: stackTrace,
      operation: operation ?? this.operation,
      action: action ?? this.action,
      lifecycle: lifecycle ?? this.lifecycle,
      route: route ?? this.route,
      source: source ?? this.source,
      resource: resource ?? this.resource,
      schemaPath: schemaPath ?? this.schemaPath,
    );
  }

  Map<String, Object?> toMap() => <String, Object?>{
    'kind': kind.name,
    'message': message,
    if (operation != null) 'operation': operation,
    if (action != null) 'action': action,
    if (lifecycle != null) 'lifecycle': lifecycle,
    if (route != null) 'route': route,
    if (source != null) 'source': source,
    if (resource != null) 'resource': resource,
    if (schemaPath != null) 'schemaPath': schemaPath,
    if (stackTrace != null) 'stackTrace': '$stackTrace',
    'causeType': cause.runtimeType.toString(),
    if (cause is FormatException && (cause as FormatException).source != null)
      'causeSource': '${(cause as FormatException).source}',
    if (cause is FormatException && (cause as FormatException).offset != null)
      'causeOffset': (cause as FormatException).offset,
  };

  @override
  String toString() {
    final details = toMap().entries
        .where((entry) => entry.key != 'stackTrace')
        .map((entry) => '${entry.key}=${entry.value}')
        .join(' ');
    return 'QuickjsUiError($details)';
  }
}

String _messageFor(Object cause) {
  if (cause is JsThrownException) {
    return cause.message;
  }
  if (cause is JsException) {
    return cause.message;
  }
  if (cause is FormatException) {
    return cause.message;
  }
  return '$cause';
}

StackTrace? _stackFor(Object cause) {
  if (cause is JsThrownException && cause.stack != null) {
    return StackTrace.fromString(cause.stack!);
  }
  if (cause is Error) {
    return cause.stackTrace;
  }
  return null;
}
