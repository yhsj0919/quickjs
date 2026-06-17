import 'dart:convert';

/// Parsed metadata from a JavaScript source map.
///
/// This registry slice intentionally stores source map data without applying
/// mappings yet. Stack rewriting is handled by the later stack remap phase.
final class QuickjsSourceMap {
  QuickjsSourceMap({
    required this.version,
    required this.sources,
    required this.names,
    required this.mappings,
    this.file,
    this.sourceRoot,
    this.sourcesContent,
    this.raw = const <String, Object?>{},
  }) : _lines = _parseMappings(mappings, sources);

  factory QuickjsSourceMap.fromJson(String sourceMapJson) {
    final decoded = jsonDecode(sourceMapJson);
    if (decoded is! Map<String, Object?>) {
      throw const FormatException('QuickJS source map must be a JSON object');
    }
    return QuickjsSourceMap.fromMap(decoded);
  }

  factory QuickjsSourceMap.fromMap(Map<String, Object?> sourceMap) {
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
    return QuickjsSourceMap(
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

  final int version;
  final String? file;
  final String? sourceRoot;
  final List<String> sources;
  final List<String> names;
  final String mappings;
  final List<String?>? sourcesContent;
  final Map<String, Object?> raw;
  final List<List<_SourceMapSegment>> _lines;

  /// Returns the original source location for a generated 1-based [line] and
  /// 0-based [column], or null when the map has no matching original position.
  QuickjsSourceMapLocation? lookup({required int line, required int column}) {
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
    return QuickjsSourceMapLocation(
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
final class QuickjsSourceMapLocation {
  const QuickjsSourceMapLocation({
    required this.source,
    required this.line,
    required this.column,
    this.name,
  });

  final String source;
  final int line;
  final int column;
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
