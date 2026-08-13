import 'dart:convert';

import 'quickjs_source_map.dart';

/// QuickJS 插件对外暴露的异常基类。
sealed class JsException implements Exception {
  String get message;
}

/// 宿主可以稳定判断的框架错误分类；不解释插件自己的业务错误内容。
enum JsErrorKind {
  javascript,
  valueConversion,
  timeout,
  cancelled,
  queueFull,
  runtimeClosed,
  runtimeCrash,
  outOfMemory,
  stackOverflow,
}

extension JsExceptionKind on JsException {
  JsErrorKind get kind => switch (this) {
    JsThrownException() => JsErrorKind.javascript,
    JsValueConversionException() => JsErrorKind.valueConversion,
    JsTimeoutException() => JsErrorKind.timeout,
    JsCancelledException() => JsErrorKind.cancelled,
    JsQueueFullException() => JsErrorKind.queueFull,
    JsRuntimeClosedException() => JsErrorKind.runtimeClosed,
    JsRuntimeCrashException() => JsErrorKind.runtimeCrash,
    JsOutOfMemoryException() => JsErrorKind.outOfMemory,
    JsStackOverflowException() => JsErrorKind.stackOverflow,
  };
}

/// JavaScript 代码主动 throw 或求值异常时的错误。
final class JsThrownException implements JsException {
  const JsThrownException(
    this.message, {
    this.name,
    this.stack,
    this.fileName,
    this.line,
    this.column,
    this.sourceMap,
  });

  @override
  final String message;
  final String? name;
  final String? stack;
  final String? fileName;
  final int? line;
  final int? column;
  final JsSourceMap? sourceMap;

  JsThrownException withSourceMap(
    JsSourceMap? sourceMap, {
    String? stack,
    String? fileName,
    int? line,
    int? column,
  }) {
    if (sourceMap == null &&
        stack == null &&
        fileName == null &&
        line == null &&
        column == null) {
      return this;
    }
    return JsThrownException(
      message,
      name: name,
      stack: stack ?? this.stack,
      fileName: fileName ?? this.fileName,
      line: line ?? this.line,
      column: column ?? this.column,
      sourceMap: sourceMap ?? this.sourceMap,
    );
  }

  @override
  String toString() => message;
}

/// Parses the payload after the JS exception sentinel.
///
/// Older bridges sent plain text after the sentinel. Newer bridges send a JSON
/// object with optional structured fields. Keep both formats valid.
JsThrownException parseJsExceptionPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      final message = _readString(decoded['message']);
      return JsThrownException(
        message?.isNotEmpty == true ? message! : payload,
        name: _readString(decoded['name']),
        stack: _readString(decoded['stack']),
        fileName: _readString(decoded['fileName']),
        line: _readInt(decoded['line'] ?? decoded['lineNumber']),
        column: _readInt(decoded['column'] ?? decoded['columnNumber']),
      );
    }
  } catch (_) {
    // Legacy payload: the whole payload is the message.
  }
  return JsThrownException(payload);
}

String? _readString(Object? value) => value is String ? value : null;

int? _readInt(Object? value) {
  if (value is int) {
    return value;
  }
  if (value is double && value.isFinite) {
    return value.toInt();
  }
  return null;
}

/// `eval()` 遇到无法直接映射为 Dart 值的 JS 值。
final class JsValueConversionException implements JsException {
  const JsValueConversionException([
    this.message = 'QuickJS value cannot be converted to a Dart value',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行超过调用方指定的 timeout。
final class JsTimeoutException implements JsException {
  const JsTimeoutException([this.message = 'QuickJS evaluation timed out']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行被 `restart()` 或其他取消机制中断。
final class JsCancelledException implements JsException {
  const JsCancelledException([
    this.message = 'QuickJS evaluation was cancelled',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 的串行调用队列已经达到宿主配置的上限。
final class JsQueueFullException implements JsException {
  const JsQueueFullException([
    this.message = 'QuickJS evaluation queue is full',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 已经关闭后继续调用 API。
final class JsRuntimeClosedException implements JsException {
  const JsRuntimeClosedException([this.message = 'QuickJS runtime is closed']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime worker 崩溃或异常退出。
final class JsRuntimeCrashException implements JsException {
  const JsRuntimeCrashException([
    this.message = 'QuickJS runtime worker crashed',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 分配内存超过配置限制。
final class JsOutOfMemoryException implements JsException {
  const JsOutOfMemoryException([
    this.message = 'QuickJS runtime out of memory',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 调用栈超过配置限制。
final class JsStackOverflowException implements JsException {
  const JsStackOverflowException([
    this.message = 'QuickJS runtime stack overflow',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}
