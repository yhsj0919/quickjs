import 'dart:convert';

import 'quickjs_source_map.dart';

/// QuickJS 插件对外暴露的异常基类。
sealed class QuickjsException implements Exception {
  String get message;
}

/// JavaScript 代码主动 throw 或求值异常时的错误。
final class JsException implements QuickjsException {
  const JsException(
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
  final QuickjsSourceMap? sourceMap;

  JsException withSourceMap(
    QuickjsSourceMap? sourceMap, {
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
    return JsException(
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
JsException parseJsExceptionPayload(String payload) {
  try {
    final decoded = jsonDecode(payload);
    if (decoded is Map<String, Object?>) {
      final message = _readString(decoded['message']);
      return JsException(
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
  return JsException(payload);
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

/// `evaluateValue()` 遇到无法直接映射为 Dart 值的 JS 值。
final class JsValueConversionException implements QuickjsException {
  const JsValueConversionException([
    this.message = 'QuickJS value cannot be converted to a Dart value',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行超过调用方指定的 timeout。
final class JsTimeoutException implements QuickjsException {
  const JsTimeoutException([this.message = 'QuickJS evaluation timed out']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// JS 执行被 `stop()` 或后续取消机制中断。
final class JsCancelledException implements QuickjsException {
  const JsCancelledException([
    this.message = 'QuickJS evaluation was cancelled',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 已经关闭后继续调用 API。
final class JsRuntimeClosedException implements QuickjsException {
  const JsRuntimeClosedException([this.message = 'QuickJS runtime is closed']);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime worker 崩溃或异常退出。
final class JsRuntimeCrashException implements QuickjsException {
  const JsRuntimeCrashException([
    this.message = 'QuickJS runtime worker crashed',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 分配内存超过配置限制。
final class JsOutOfMemoryException implements QuickjsException {
  const JsOutOfMemoryException([
    this.message = 'QuickJS runtime out of memory',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}

/// runtime 调用栈超过配置限制。
final class JsStackOverflowException implements QuickjsException {
  const JsStackOverflowException([
    this.message = 'QuickJS runtime stack overflow',
  ]);

  @override
  final String message;

  @override
  String toString() => message;
}
