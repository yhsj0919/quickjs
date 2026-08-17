import 'package:lemon_js/lemon_js.dart';

/// Categorizes failures reported by the JSUI runtime and renderer.
enum JsUiErrorKind {
  /// Page or bundle loading failed.
  load,

  /// JavaScript execution failed.
  runtime,

  /// An action or event could not be dispatched.
  dispatch,

  /// A lifecycle hook failed.
  lifecycle,

  /// Page state was invalid or could not be updated.
  state,

  /// Flutter rendering failed.
  render,

  /// A JSUI node or payload violated its schema.
  schema,

  /// A referenced resource could not be resolved or loaded.
  resource,

  /// A network operation failed.
  network,

  /// A requested permission was rejected or missing.
  permission,

  /// An operation targeted a disposed page or controller.
  disposed,

  /// The failure has not been classified.
  unknown,
}

/// Optional location and operation metadata attached to a [JsUiError].
final class JsUiErrorContext {
  /// Creates error context from the available diagnostic fields.
  const JsUiErrorContext({
    this.operation,
    this.action,
    this.lifecycle,
    this.route,
    this.source,
    this.resource,
    this.schemaPath,
  });

  /// Runtime or host operation being performed.
  final String? operation;

  /// JavaScript action associated with the failure.
  final String? action;

  /// Lifecycle hook associated with the failure.
  final String? lifecycle;

  /// Route associated with the failure.
  final String? route;

  /// Source module or script associated with the failure.
  final String? source;

  /// Resource URI or path associated with the failure.
  final String? resource;

  /// Path to the invalid value within a JSUI schema.
  final String? schemaPath;
}

/// A classified JSUI failure retaining its original cause and context.
final class JsUiError implements Exception {
  /// Creates an error with an explicit [kind], [message], and [cause].
  const JsUiError({
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

  /// Wraps [cause] while preserving an existing [JsUiError].
  ///
  /// Explicit context values take precedence over values from [context]. An
  /// existing error keeps its kind unless that kind is [JsUiErrorKind.unknown].
  factory JsUiError.wrap(
    Object cause, {
    required JsUiErrorKind kind,
    String? message,
    StackTrace? stackTrace,
    String? operation,
    String? action,
    String? lifecycle,
    String? route,
    String? source,
    String? resource,
    String? schemaPath,
    JsUiErrorContext context = const JsUiErrorContext(),
  }) {
    if (cause is JsUiError) {
      return cause.withContext(
        kind: cause.kind == JsUiErrorKind.unknown ? kind : null,
        operation: operation ?? context.operation,
        action: action ?? context.action,
        lifecycle: lifecycle ?? context.lifecycle,
        route: route ?? context.route,
        source: source ?? context.source,
        resource: resource ?? context.resource,
        schemaPath: schemaPath ?? context.schemaPath,
      );
    }
    return JsUiError(
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

  /// Error category.
  final JsUiErrorKind kind;

  /// Human-readable summary.
  final String message;

  /// Original exception or error object.
  final Object cause;

  /// Stack trace captured from the cause when available.
  final StackTrace? stackTrace;

  /// Runtime or host operation being performed.
  final String? operation;

  /// JavaScript action associated with the failure.
  final String? action;

  /// Lifecycle hook associated with the failure.
  final String? lifecycle;

  /// Route associated with the failure.
  final String? route;

  /// Source module or script associated with the failure.
  final String? source;

  /// Resource URI or path associated with the failure.
  final String? resource;

  /// Path to the invalid value within a JSUI schema.
  final String? schemaPath;

  /// Returns a copy enriched with any non-null context values.
  JsUiError withContext({
    JsUiErrorKind? kind,
    String? operation,
    String? action,
    String? lifecycle,
    String? route,
    String? source,
    String? resource,
    String? schemaPath,
  }) {
    return JsUiError(
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

  /// Serializes diagnostics to JSON-compatible structured data.
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
    return 'JsUiError($details)';
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
