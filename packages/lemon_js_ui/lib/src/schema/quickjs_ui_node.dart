import 'dart:collection';
import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

/// Serializable UI node returned by a quickjs_ui page renderer.
///
/// The schema is intentionally small and JSON-compatible. Higher-level DSLs can
/// compile into this shape later, but this remains the runtime rendering input.
final class JsUiNode {
  /// Maximum supported nesting depth when parsing a node tree.
  static const int maxDepth = 128;

  /// Creates an immutable UI node.
  JsUiNode({
    required String type,
    Map<String, Object?> props = const <String, Object?>{},
    List<JsUiNode> children = const <JsUiNode>[],
  }) : this._prepared(
         type: type,
         props: _prepareProps(props),
         children: List<JsUiNode>.unmodifiable(children),
       );

  JsUiNode._prepared({
    required this.type,
    required _PreparedProps props,
    required this.children,
  }) : props = props.values,
       key = _readKey(props.values),
       structuralSignature = _nodeSignature(type, props.signature, children),
       duplicateSiblingKey = _findDuplicateSiblingKey(children) {
    overlayNodes = _prepareOverlayNodes(this);
  }

  /// Parses a node tree from its JSON-compatible map representation.
  factory JsUiNode.fromMap(Map<String, Object?> value) {
    return JsUiNode._fromMap(value, depth: 0);
  }

  factory JsUiNode._fromMap(Map<String, Object?> value, {required int depth}) {
    if (depth > maxDepth) {
      throw const FormatException('quickjs_ui node tree is too deep');
    }
    final type = value['type'];
    if (type is! String || type.isEmpty) {
      throw const FormatException('quickjs_ui node type must be a string');
    }
    final rawChildren = value['children'];
    final rawChild = value['child'];
    final props = _prepareProps(<String, Object?>{
      for (final entry in value.entries)
        if (entry.key != 'type' &&
            entry.key != 'children' &&
            entry.key != 'child')
          entry.key: entry.value,
    });
    final children = List<JsUiNode>.unmodifiable(
      _parseNodeChildren(
        rawChild: rawChild,
        rawChildren: rawChildren,
        depth: depth,
      ),
    );
    return JsUiNode._prepared(type: type, props: props, children: children);
  }

  /// Component type registered with the renderer.
  final String type;

  /// Immutable component properties.
  final Map<String, Object?> props;

  /// Immutable direct child nodes.
  final List<JsUiNode> children;

  /// Stable signature of this node and its complete subtree.
  ///
  /// It is calculated bottom-up while the schema is parsed. Render diffing can
  /// therefore compare a keyed subtree in O(1), instead of serializing that
  /// subtree again for every keyed ancestor on every Flutter build.
  final String structuralSignature;

  /// Stable key extracted once from [props].
  final String? key;

  /// First duplicate direct-child key, if any.
  ///
  /// Validation stays in the renderer so existing callers observe errors at
  /// build time, but detection itself is paid only once per immutable node.
  final String? duplicateSiblingKey;

  /// Overlay declarations contained by this subtree.
  ///
  /// Most schemas contain no overlays, so this is usually the shared empty
  /// list. The renderer can consume it directly without walking the complete
  /// node tree again after widget construction.
  late final List<JsUiNode> overlayNodes;

  /// Converts this node tree to a JSON-compatible map.
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

  static List<JsUiNode> _parseChildren(Object? value, {required int depth}) {
    if (value is! List) {
      throw const FormatException('quickjs_ui node children must be a list');
    }
    return <JsUiNode>[
      for (final child in value)
        if (child is Map)
          JsUiNode._fromMap(
            child.map((key, value) => MapEntry<String, Object?>('$key', value)),
            depth: depth + 1,
          )
        else
          throw const FormatException(
            'quickjs_ui child node must be an object',
          ),
    ];
  }

  static List<JsUiNode> _parseNodeChildren({
    required Object? rawChild,
    required Object? rawChildren,
    required int depth,
  }) {
    if (rawChild != null && rawChildren != null) {
      throw const FormatException(
        'quickjs_ui node cannot define both child and children',
      );
    }
    if (rawChild != null) {
      return <JsUiNode>[_parseChild(rawChild, depth: depth)];
    }
    if (rawChildren != null) {
      return _parseChildren(rawChildren, depth: depth);
    }
    return const <JsUiNode>[];
  }

  static JsUiNode _parseChild(Object? value, {required int depth}) {
    if (value is Map) {
      return JsUiNode._fromMap(
        value.map((key, value) => MapEntry<String, Object?>('$key', value)),
        depth: depth + 1,
      );
    }
    throw const FormatException('quickjs_ui child node must be an object');
  }
}

final class _PreparedProps {
  const _PreparedProps(this.values, this.signature);

  final Map<String, Object?> values;
  final String signature;
}

_PreparedProps _prepareProps(Map<String, Object?> props) {
  final values = <String, Object?>{};
  final signatures = <String, String>{};
  for (final entry in props.entries) {
    final prepared = _prepareValue(entry.value);
    values[entry.key] = prepared.value;
    signatures[entry.key] = prepared.signature;
  }
  final keys = signatures.keys.toList()..sort();
  final signature = keys
      .map((key) => '${_token('k', key)}${signatures[key]}')
      .join();
  return _PreparedProps(
    UnmodifiableMapView<String, Object?>(values),
    _token('m', signature),
  );
}

({Object? value, String signature}) _prepareValue(Object? value) {
  if (value == null) return (value: null, signature: 'n');
  if (value is String) {
    return (value: value, signature: _token('s', value));
  }
  if (value is num) {
    return (value: value, signature: _token('d', '$value'));
  }
  if (value is bool) {
    return (value: value, signature: value ? 'b1' : 'b0');
  }
  if (value is Uint8List) {
    final copy = Uint8List.fromList(value);
    return (value: copy, signature: _token('u', copy.join(',')));
  }
  if (value is Map) {
    final entries = <({String key, Object? value, String signature})>[];
    for (final entry in value.entries) {
      final prepared = _prepareValue(entry.value);
      entries.add((
        key: '${entry.key}',
        value: prepared.value,
        signature: prepared.signature,
      ));
    }
    entries.sort((left, right) => left.key.compareTo(right.key));
    final frozen = <String, Object?>{
      for (final entry in entries) entry.key: entry.value,
    };
    final signature = entries
        .map((entry) => '${_token('k', entry.key)}${entry.signature}')
        .join();
    return (
      value: UnmodifiableMapView<String, Object?>(frozen),
      signature: _token('m', signature),
    );
  }
  if (value is Iterable) {
    final values = <Object?>[];
    final signature = StringBuffer();
    for (final item in value) {
      final prepared = _prepareValue(item);
      values.add(prepared.value);
      signature.write(prepared.signature);
    }
    return (
      value: List<Object?>.unmodifiable(values),
      signature: _token('l', '$signature'),
    );
  }
  final text = '$value';
  return (value: value, signature: _token('o', text));
}

String _nodeSignature(
  String type,
  String propsSignature,
  List<JsUiNode> children,
) {
  final childSignatures = children
      .map((child) => child.structuralSignature)
      .join();
  final canonical =
      '${_token('t', type)}$propsSignature${_token('c', childSignatures)}';
  // A fixed-size digest prevents each ancestor from retaining another full
  // serialization of its subtree. SHA-256 also makes accidental equality safe
  // enough to use as a widget-reuse identity, unlike a small integer hash.
  return sha256.convert(utf8.encode(canonical)).toString();
}

String? _readKey(Map<String, Object?> props) {
  final key = props['key'];
  return key is String && key.isNotEmpty ? key : null;
}

String? _findDuplicateSiblingKey(List<JsUiNode> children) {
  final keys = <String>{};
  for (final child in children) {
    final key = child.key;
    if (key != null && !keys.add(key)) return key;
  }
  return null;
}

List<JsUiNode> _prepareOverlayNodes(JsUiNode node) {
  List<JsUiNode>? result;
  if (isJsUiRouteOverlayType(node.type)) {
    result = <JsUiNode>[node];
  }
  for (final child in node.children) {
    if (child.overlayNodes.isNotEmpty) {
      (result ??= <JsUiNode>[]).addAll(child.overlayNodes);
    }
  }
  for (final value in node.props.values) {
    final embedded = _propOverlayNodes(value);
    if (embedded != null) {
      (result ??= <JsUiNode>[]).addAll(embedded);
    }
  }
  if (result == null || result.isEmpty) {
    return const <JsUiNode>[];
  }
  return List<JsUiNode>.unmodifiable(result);
}

List<JsUiNode>? _propOverlayNodes(Object? value) {
  if (value is Map) {
    final type = value['type'];
    if (type is String && type.isNotEmpty) {
      final embedded = JsUiNode.fromMap(
        value.map((key, value) => MapEntry<String, Object?>('$key', value)),
      );
      return embedded.overlayNodes.isEmpty ? null : embedded.overlayNodes;
    }
    return null;
  }
  if (value is Iterable && value is! String && value is! Uint8List) {
    List<JsUiNode>? result;
    for (final item in value) {
      final embedded = _propOverlayNodes(item);
      if (embedded != null) {
        (result ??= <JsUiNode>[]).addAll(embedded);
      }
    }
    return result;
  }
  return null;
}

/// Whether [type] represents a route-level overlay component.
bool isJsUiRouteOverlayType(String type) {
  return type == 'Overlay' ||
      type == 'SnackBar' ||
      type == 'AlertDialog' ||
      type == 'BottomSheet';
}

String _token(String type, String value) => '$type${value.length}:$value';
