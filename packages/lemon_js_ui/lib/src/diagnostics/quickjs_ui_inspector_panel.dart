import 'dart:convert';

import 'package:flutter/material.dart';

import '../runtime/quickjs_ui_controller.dart';
import 'quickjs_ui_inspector.dart';
import 'quickjs_ui_network_record.dart';

/// Development panel that visualizes [JsUiInspector] data.
final class JsUiInspectorPanel extends StatelessWidget {
  /// Creates a js ui inspector panel.
  /// Creates a js ui inspector panel.
  const JsUiInspectorPanel({
    super.key,
    required this.controller,
    required this.inspector,
  });

  /// The controller value.
  /// The controller value.
  final JsUiController controller;

  /// The inspector value.
  /// The inspector value.
  final JsUiInspector inspector;

  @override
  Widget build(BuildContext context) {
    return ListenableBuilder(
      listenable: Listenable.merge(<Listenable>[controller, inspector]),
      builder: (context, _) {
        final snapshot = inspector.buildSnapshot(
          props: controller.props,
          state: controller.state,
          node: controller.node,
          plugin: controller.plugin,
          features: controller.features,
          error: controller.error,
        );
        return DefaultTabController(
          length: 7,
          child: Material(
            color: Theme.of(context).colorScheme.surfaceContainerLow,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: <Widget>[
                TabBar(
                  isScrollable: true,
                  tabs: const <Widget>[
                    Tab(text: '状态'),
                    Tab(text: 'Schema'),
                    Tab(text: '生命周期'),
                    Tab(text: 'Diff'),
                    Tab(text: '网络'),
                    Tab(text: '资源'),
                    Tab(text: '性能'),
                  ],
                ),
                Expanded(
                  child: TabBarView(
                    children: <Widget>[
                      _JsonPane(
                        data: <String, Object?>{
                          'props': snapshot.props,
                          'state': snapshot.state,
                          if (snapshot.lastAction != null)
                            'lastAction': snapshot.lastAction,
                          if (snapshot.error != null)
                            'error': '${snapshot.error}',
                        },
                      ),
                      _JsonPane(
                        data: snapshot.schema ?? const <String, Object?>{},
                      ),
                      _TimelinePane(events: snapshot.lifecycle),
                      _JsonPane(
                        data:
                            snapshot.diff?.toMap() ?? const <String, Object?>{},
                      ),
                      _NetworkPane(records: inspector.networkRecords),
                      _JsonPane(
                        data: <String, Object?>{
                          'hostApis': snapshot.hostApis,
                          'resources': snapshot.resources,
                        },
                      ),
                      _JsonPane(
                        data:
                            snapshot.performance?.toMap() ??
                            const <String, Object?>{},
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}

final class _NetworkPane extends StatelessWidget {
  const _NetworkPane({required this.records});

  final List<JsUiNetworkRecord> records;

  @override
  Widget build(BuildContext context) {
    if (records.isEmpty) {
      return const Center(child: Text('暂无网络请求'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: records.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final record = records[records.length - 1 - index];
        final status = record.statusCode?.toString() ?? record.phase.name;
        final duration = record.durationMs == null
            ? '-'
            : '${record.durationMs}ms';
        final cache = record.fromCache ? ' cache' : '';
        return ListTile(
          dense: true,
          title: Text(
            '${record.method} ${record.uri}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
          ),
          subtitle: Text(
            '${record.source.name} $status $duration$cache'
            '${record.error == null ? '' : ' error=${record.error}'}',
            style: const TextStyle(fontFamily: 'monospace', fontSize: 11),
          ),
          isThreeLine: record.error != null,
        );
      },
    );
  }
}

final class _JsonPane extends StatelessWidget {
  const _JsonPane({required this.data});

  final Map<String, Object?> data;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(12),
      child: SelectableText(
        _prettyJson(data),
        style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
      ),
    );
  }
}

final class _TimelinePane extends StatelessWidget {
  const _TimelinePane({required this.events});

  final List events;

  @override
  Widget build(BuildContext context) {
    if (events.isEmpty) {
      return const Center(child: Text('暂无生命周期事件'));
    }
    return ListView.separated(
      padding: const EdgeInsets.all(12),
      itemCount: events.length,
      separatorBuilder: (context, index) => const Divider(height: 1),
      itemBuilder: (context, index) {
        final event = events[index];
        final map = event.toMap();
        return Text(
          '${map['timestamp']} [${map['phase']}] ${map['type']}',
          style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
        );
      },
    );
  }
}

String _prettyJson(Object? value) {
  const encoder = JsonEncoder.withIndent('  ');
  return encoder.convert(_jsonSafe(value));
}

Object? _jsonSafe(Object? value) {
  if (value == null) {
    return null;
  }
  if (value is String || value is num || value is bool) {
    return value;
  }
  if (value is Map) {
    return <String, Object?>{
      for (final entry in value.entries) '${entry.key}': _jsonSafe(entry.value),
    };
  }
  if (value is Iterable) {
    return <Object?>[for (final item in value) _jsonSafe(item)];
  }
  return '$value';
}
