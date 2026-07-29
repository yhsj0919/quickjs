import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// JSON Schema Demo：从纯 JSON UI schema asset 解析 [QuickjsUiNode]，
/// 不经过 JS 直接渲染。
class QuickjsUiSchemaPage extends StatefulWidget {
  const QuickjsUiSchemaPage({super.key});

  /// 预览用 UI schema 的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/schema_preview.json';

  /// quickjs_ui 协议 schema 文件路径（用于校验）。
  static const String schemaPath =
      'packages/quickjs_ui/js/quickjs_ui.schema.json';

  @override
  State<QuickjsUiSchemaPage> createState() => _QuickjsUiSchemaPageState();
}

class _QuickjsUiSchemaPageState extends State<QuickjsUiSchemaPage> {
  QuickjsUiNode? _node;
  Object? _error;
  Map<String, Object?>? _lastEvent;
  String? _schemaTitle;
  int? _schemaNodeCount;

  @override
  void initState() {
    super.initState();
    _loadSchema();
  }

  @override
  Widget build(BuildContext context) {
    final error = _error;
    return Scaffold(
      appBar: AppBar(title: const Text('JSON Schema 页面')),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: <Widget>[
          Material(
            color: Theme.of(context).colorScheme.surfaceContainerHighest,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
              child: Text(
                _lastEvent == null
                    ? _schemaTitle == null
                          ? 'Loaded ${QuickjsUiSchemaPage.path}'
                          : 'Loaded $_schemaTitle with $_schemaNodeCount node variants'
                    : 'Last JSON event: $_lastEvent',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          Expanded(
            child: error != null
                ? Padding(
                    padding: const EdgeInsets.all(16),
                    child: SelectableText('JSON schema render error: $error'),
                  )
                : _node == null
                ? const Center(child: CircularProgressIndicator())
                : QuickjsUiRenderer(
                    onEvent: _handleEvent,
                  ).build(_node!, buildContext: context),
          ),
        ],
      ),
    );
  }

  Future<void> _loadSchema() async {
    try {
      final source = await rootBundle.loadString(QuickjsUiSchemaPage.path);
      final schemaSource = await rootBundle.loadString(
        QuickjsUiSchemaPage.schemaPath,
      );
      final decoded = jsonDecode(source);
      final schemaDecoded = jsonDecode(schemaSource);
      if (decoded is! Map) {
        throw const FormatException('schema preview root must be an object');
      }
      if (schemaDecoded is! Map) {
        throw const FormatException('quickjs_ui schema root must be an object');
      }
      final schema = decoded.map(
        (key, value) => MapEntry<String, Object?>('$key', value),
      );
      final schemaObject = schemaDecoded.map(
        (key, value) => MapEntry<String, Object?>('$key', value),
      );
      final defs = schemaObject[r'$defs'];
      final nodeCount = defs is Map
          ? ((defs['node'] as Map?)?['oneOf'] as List?)?.length
          : null;
      setState(() {
        _node = QuickjsUiNode.fromMap(schema);
        _schemaTitle = '${schemaObject['title']}';
        _schemaNodeCount = nodeCount;
      });
    } catch (error) {
      setState(() {
        _error = error;
      });
    }
  }

  void _handleEvent(Map<String, Object?> event) {
    setState(() {
      _lastEvent = event;
    });
  }
}
