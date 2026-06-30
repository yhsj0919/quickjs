import 'dart:collection';

/// Serializable UI node returned by a quickjs_ui page renderer.
///
/// The schema is intentionally small and JSON-compatible. Higher-level DSLs can
/// compile into this shape later, but this remains the runtime rendering input.
final class QuickjsUiNode {
  QuickjsUiNode({
    required this.type,
    Map<String, Object?> props = const <String, Object?>{},
    List<QuickjsUiNode> children = const <QuickjsUiNode>[],
  }) : props = UnmodifiableMapView<String, Object?>(Map.of(props)),
       children = List<QuickjsUiNode>.unmodifiable(children);

  factory QuickjsUiNode.fromMap(Map<String, Object?> value) {
    final type = value['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('quickjs_ui node type must be a string');
    }
    final rawChildren = value['children'];
    final rawChild = value['child'];
    return QuickjsUiNode(
      type: type,
      props: <String, Object?>{
        for (final entry in value.entries)
          if (entry.key != 'type' &&
              entry.key != 'children' &&
              entry.key != 'child')
            entry.key: entry.value,
      },
      children: _parseNodeChildren(
        rawChild: rawChild,
        rawChildren: rawChildren,
      ),
    );
  }

  final String type;
  final Map<String, Object?> props;
  final List<QuickjsUiNode> children;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'type': type,
      ...props,
      if (children.isNotEmpty)
        'children': <Map<String, Object?>>[
          for (final child in children) child.toMap(),
        ],
    };
  }

  static List<QuickjsUiNode> _parseChildren(Object? value) {
    if (value is! List) {
      throw const FormatException('quickjs_ui node children must be a list');
    }
    return <QuickjsUiNode>[
      for (final child in value)
        if (child is Map)
          QuickjsUiNode.fromMap(
            child.map((key, value) => MapEntry<String, Object?>('$key', value)),
          )
        else
          throw const FormatException(
            'quickjs_ui child node must be an object',
          ),
    ];
  }

  static List<QuickjsUiNode> _parseNodeChildren({
    required Object? rawChild,
    required Object? rawChildren,
  }) {
    if (rawChild != null && rawChildren != null) {
      throw const FormatException(
        'quickjs_ui node cannot define both child and children',
      );
    }
    if (rawChild != null) {
      return <QuickjsUiNode>[_parseChild(rawChild)];
    }
    if (rawChildren != null) {
      return _parseChildren(rawChildren);
    }
    return const <QuickjsUiNode>[];
  }

  static QuickjsUiNode _parseChild(Object? value) {
    if (value is Map) {
      return QuickjsUiNode.fromMap(
        value.map((key, value) => MapEntry<String, Object?>('$key', value)),
      );
    }
    throw const FormatException('quickjs_ui child node must be an object');
  }
}
