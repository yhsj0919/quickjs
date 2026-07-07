import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:quickjs_ui/quickjs_ui.dart';

/// 开发调试 Demo：Inspector 面板、页面快照导出、diff/resource 日志与保留 state 热重载。
class QuickjsUiDevPanelPage extends StatefulWidget {
  const QuickjsUiDevPanelPage({super.key});

  /// 入口 JS 页面的 Flutter asset 路径。
  static const String path = 'assets/quickjs_ui/dev_panel_page.mjs';

  @override
  State<QuickjsUiDevPanelPage> createState() => _QuickjsUiDevPanelPageState();
}

class _QuickjsUiDevPanelPageState extends State<QuickjsUiDevPanelPage> {
  late final QuickjsUiInspector _inspector;
  late final QuickjsUiController _controller;

  @override
  void initState() {
    super.initState();
    _inspector = QuickjsUiInspector();
    _controller = QuickjsUiController(
      devOptions: const QuickjsUiDevOptions(
        logDiff: true,
        logResources: true,
        preserveStateOnReload: true,
      ),
      inspector: _inspector,
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('QuickJS UI 0.4.3 开发调试'),
        actions: <Widget>[
          IconButton(
            tooltip: '导出快照',
            onPressed: _exportSnapshot,
            icon: const Icon(Icons.copy_all),
          ),
          IconButton(
            tooltip: '热重载',
            onPressed: () => _controller.reload(),
            icon: const Icon(Icons.refresh),
          ),
        ],
      ),
      body: Column(
        children: <Widget>[
          Expanded(
            flex: 3,
            child: QuickjsUiView.asset(
              path: QuickjsUiDevPanelPage.path,
              controller: _controller,
              loadingBuilder: (_) =>
                  const Center(child: CircularProgressIndicator()),
            ),
          ),
          const Divider(height: 1),
          Expanded(
            flex: 2,
            child: QuickjsUiInspectorPanel(
              controller: _controller,
              inspector: _inspector,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _exportSnapshot() async {
    final snapshot = _controller.exportPageSnapshotMap();
    final text = _prettyJson(snapshot);
    await Clipboard.setData(ClipboardData(text: text));
    if (!mounted) {
      return;
    }
    ScaffoldMessenger.of(
      context,
    ).showSnackBar(const SnackBar(content: Text('页面快照已复制到剪贴板')));
  }

  String _prettyJson(Object? value, {int indent = 0}) {
    final pad = '  ' * indent;
    if (value == null) {
      return 'null';
    }
    if (value is String) {
      return '"$value"';
    }
    if (value is num || value is bool) {
      return '$value';
    }
    if (value is Map) {
      if (value.isEmpty) {
        return '{}';
      }
      final buffer = StringBuffer('{\n');
      final entries = value.entries.toList();
      for (var i = 0; i < entries.length; i++) {
        final entry = entries[i];
        buffer
          ..write('$pad  "${entry.key}": ')
          ..write(_prettyJson(entry.value, indent: indent + 1));
        if (i < entries.length - 1) {
          buffer.write(',');
        }
        buffer.write('\n');
      }
      buffer.write('$pad}');
      return buffer.toString();
    }
    if (value is Iterable) {
      if (value.isEmpty) {
        return '[]';
      }
      final buffer = StringBuffer('[\n');
      var i = 0;
      for (final item in value) {
        buffer
          ..write('$pad  ')
          ..write(_prettyJson(item, indent: indent + 1));
        if (i < value.length - 1) {
          buffer.write(',');
        }
        buffer.write('\n');
        i += 1;
      }
      buffer.write('$pad]');
      return buffer.toString();
    }
    return '"$value"';
  }
}
