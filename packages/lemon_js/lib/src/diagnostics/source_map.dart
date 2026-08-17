import 'dart:convert';

/// 解析后的 JavaScript source map，用于将生成代码位置映射回原始源码。
///
/// [lookup] 接收生成代码的 1-based 行号和 0-based 列号。
final class JsSourceMap {
  /// 创建一个已验证字段并可立即查询的 source map。
  JsSourceMap({
    required this.version,
    required this.sources,
    required this.names,
    required this.mappings,
    this.file,
    this.sourceRoot,
    this.sourcesContent,
    this.raw = const <String, Object?>{},
  }) : _lines = _parseMappings(mappings, sources);

  /// 从 JSON 字符串解析 version 3 source map。
  factory JsSourceMap.fromJson(String sourceMapJson) {
    final decoded = jsonDecode(sourceMapJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('QuickJS source map must be a JSON object');
    }
    return JsSourceMap.fromMap(decoded);
  }

  /// 从解码后的对象解析 version 3 source map。
  factory JsSourceMap.fromMap(Map<String, Object?> sourceMap) {
    final version = sourceMap['version'];
    final sources = sourceMap['sources'];
    final names = sourceMap['names'];
    final mappings = sourceMap['mappings'];
    if (version is! int || version != 3) {
      throw const FormatException('QuickJS source map version must be 3');
    }
    if (sources is! List || sources.any((source) => source is! String)) {
      throw const FormatException(
        'QuickJS source map sources must be a string array',
      );
    }
    if (names is! List || names.any((name) => name is! String)) {
      throw const FormatException(
        'QuickJS source map names must be a string array',
      );
    }
    if (mappings is! String) {
      throw const FormatException(
        'QuickJS source map mappings must be a string',
      );
    }
    final rawSourcesContent = sourceMap['sourcesContent'];
    List<String?>? sourcesContent;
    if (rawSourcesContent != null) {
      if (rawSourcesContent is! List ||
          rawSourcesContent.any((content) => content is! String?)) {
        throw const FormatException(
          'QuickJS source map sourcesContent must be a string array',
        );
      }
      sourcesContent = List<String?>.unmodifiable(
        rawSourcesContent.cast<String?>(),
      );
    }
    return JsSourceMap(
      version: version,
      file: _readOptionalString(sourceMap, 'file'),
      sourceRoot: _readOptionalString(sourceMap, 'sourceRoot'),
      sources: List<String>.unmodifiable(sources.cast<String>()),
      names: List<String>.unmodifiable(names.cast<String>()),
      mappings: mappings,
      sourcesContent: sourcesContent,
      raw: Map<String, Object?>.unmodifiable(sourceMap),
    );
  }

  /// Source map 规范版本；当前仅接受 3。
  final int version;

  /// 生成文件名（若映射声明了该字段）。
  final String? file;

  /// 应用于相对源文件路径的根路径。
  final String? sourceRoot;

  /// 映射引用的原始源文件路径。
  final List<String> sources;

  /// 映射片段可引用的原始符号名称。
  final List<String> names;

  /// 采用 Base64 VLQ 编码的原始 mappings 字符串。
  final String mappings;

  /// 可选的内嵌原始源码，与 [sources] 按索引对应。
  final List<String?>? sourcesContent;

  /// 输入中完整且不可变的 source map 对象。
  final Map<String, Object?> raw;
  final List<List<_SourceMapSegment>> _lines;

  /// Returns the original source location for a generated 1-based [line] and
  /// 0-based [column], or null when the map has no matching original position.
  JsSourceLocation? lookup({required int line, required int column}) {
    if (line <= 0 || column < 0 || line > _lines.length) {
      return null;
    }
    final segments = _lines[line - 1];
    _SourceMapSegment? best;
    for (final segment in segments) {
      if (segment.generatedColumn > column) {
        break;
      }
      if (segment.sourceIndex != null) {
        best = segment;
      }
    }
    if (best == null) {
      return null;
    }
    final sourceIndex = best.sourceIndex!;
    if (sourceIndex < 0 || sourceIndex >= sources.length) {
      return null;
    }
    return JsSourceLocation(
      source: _resolveSource(sources[sourceIndex]),
      line: best.sourceLine! + 1,
      column: best.sourceColumn!,
      name:
          best.nameIndex == null ||
              best.nameIndex! < 0 ||
              best.nameIndex! >= names.length
          ? null
          : names[best.nameIndex!],
    );
  }

  String _resolveSource(String source) {
    final root = sourceRoot;
    if (root == null || root.isEmpty) {
      return source;
    }
    if (root.endsWith('/') || source.isEmpty) {
      return '$root$source';
    }
    return '$root/$source';
  }
}

/// Original source location resolved from a source map.
final class JsSourceLocation {
  /// 创建一个已解析的原始源码位置。
  const JsSourceLocation({
    required this.source,
    required this.line,
    required this.column,
    this.name,
  });

  /// 原始源文件路径。
  final String source;

  /// 原始源码中的 1-based 行号。
  final int line;

  /// 原始源码中的 0-based 列号。
  final int column;

  /// 映射提供的可选原始符号名称。
  final String? name;
}

final class _SourceMapSegment {
  const _SourceMapSegment({
    required this.generatedColumn,
    this.sourceIndex,
    this.sourceLine,
    this.sourceColumn,
    this.nameIndex,
  });

  final int generatedColumn;
  final int? sourceIndex;
  final int? sourceLine;
  final int? sourceColumn;
  final int? nameIndex;
}

List<List<_SourceMapSegment>> _parseMappings(
  String mappings,
  List<String> sources,
) {
  final lines = <List<_SourceMapSegment>>[];
  var sourceIndex = 0;
  var sourceLine = 0;
  var sourceColumn = 0;
  var nameIndex = 0;

  for (final rawLine in mappings.split(';')) {
    final segments = <_SourceMapSegment>[];
    var generatedColumn = 0;
    if (rawLine.isNotEmpty) {
      for (final rawSegment in rawLine.split(',')) {
        if (rawSegment.isEmpty) {
          continue;
        }
        final values = _decodeVlqSegment(rawSegment);
        if (values.isEmpty) {
          continue;
        }
        generatedColumn += values[0];
        if (values.length == 1) {
          segments.add(_SourceMapSegment(generatedColumn: generatedColumn));
          continue;
        }
        if (values.length < 4) {
          throw const FormatException(
            'QuickJS source map segment must have 1, 4, or 5 fields',
          );
        }
        sourceIndex += values[1];
        sourceLine += values[2];
        sourceColumn += values[3];
        int? segmentNameIndex;
        if (values.length >= 5) {
          nameIndex += values[4];
          segmentNameIndex = nameIndex;
        }
        segments.add(
          _SourceMapSegment(
            generatedColumn: generatedColumn,
            sourceIndex: sourceIndex,
            sourceLine: sourceLine,
            sourceColumn: sourceColumn,
            nameIndex: segmentNameIndex,
          ),
        );
      }
    }
    lines.add(List<_SourceMapSegment>.unmodifiable(segments));
  }
  return List<List<_SourceMapSegment>>.unmodifiable(lines);
}

List<int> _decodeVlqSegment(String segment) {
  final values = <int>[];
  var value = 0;
  var shift = 0;
  for (var i = 0; i < segment.length; i++) {
    final digit = _base64Value(segment.codeUnitAt(i));
    final continuation = (digit & 32) != 0;
    value += (digit & 31) << shift;
    if (continuation) {
      shift += 5;
      continue;
    }
    final negative = (value & 1) == 1;
    final decoded = value >> 1;
    values.add(negative ? -decoded : decoded);
    value = 0;
    shift = 0;
  }
  if (shift != 0) {
    throw const FormatException('QuickJS source map VLQ segment is truncated');
  }
  return values;
}

int _base64Value(int codeUnit) {
  if (codeUnit >= 65 && codeUnit <= 90) {
    return codeUnit - 65;
  }
  if (codeUnit >= 97 && codeUnit <= 122) {
    return codeUnit - 97 + 26;
  }
  if (codeUnit >= 48 && codeUnit <= 57) {
    return codeUnit - 48 + 52;
  }
  if (codeUnit == 43) {
    return 62;
  }
  if (codeUnit == 47) {
    return 63;
  }
  throw FormatException(
    'QuickJS source map contains invalid base64 digit: ${String.fromCharCode(codeUnit)}',
  );
}

String? _readOptionalString(Map<String, Object?> sourceMap, String key) {
  final value = sourceMap[key];
  if (value == null) {
    return null;
  }
  if (value is String) {
    return value;
  }
  throw FormatException('QuickJS source map $key must be a string');
}
