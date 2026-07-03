import 'dart:async';

import 'package:flutter/widgets.dart';

import '../diagnostics/quickjs_ui_diag.dart';

typedef QuickjsUiEventSink = Future<void> Function(Map<String, Object?> event);

/// Queues renderer UI events and flushes them after the current frame so
/// controller updates never synchronously rebuild [QuickjsUiView] during build.
final class QuickjsUiEventIngress {
  QuickjsUiEventIngress(this._sink);

  final QuickjsUiEventSink _sink;
  final List<Map<String, Object?>> _pending = <Map<String, Object?>>[];
  bool _flushScheduled = false;
  bool _flushing = false;
  bool _disposed = false;

  void submit(Map<String, Object?> event) {
    if (_disposed) {
      return;
    }
    _pending.add(Map<String, Object?>.from(event));
    if (_pending.length >= 16) {
      QuickjsUiDiag.log(
        'ingress',
        'submit queue=${_pending.length} '
        'flushing=$_flushing scheduled=$_flushScheduled '
        'method=${event['method'] ?? event['action']}',
      );
    }
    _scheduleFlush();
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _flushScheduled = false;
  }

  void _scheduleFlush() {
    if (_disposed || _flushScheduled || _flushing) {
      return;
    }
    _flushScheduled = true;
    final binding = WidgetsBinding.instance;
    binding.scheduleFrame();
    binding.addPostFrameCallback((_) {
      _flushScheduled = false;
      unawaited(_flush());
    });
  }

  Future<void> _flush() async {
    if (_disposed || _flushing || _pending.isEmpty) {
      return;
    }
    _flushing = true;
    final batchSize = _pending.length;
    QuickjsUiDiag.count('ingress.flush', detail: 'batch=$batchSize');
    if (batchSize >= 8) {
      QuickjsUiDiag.log('ingress', 'flush start batch=$batchSize');
    }
    var processed = 0;
    try {
      while (!_disposed && _pending.isNotEmpty) {
        final event = _pending.removeAt(0);
        processed += 1;
        await _sink(event);
      }
    } finally {
      _flushing = false;
      if (batchSize >= 8 || (_pending.isNotEmpty && processed > 1)) {
        QuickjsUiDiag.log(
          'ingress',
          'flush done processed=$processed remaining=${_pending.length}',
        );
      }
      if (!_disposed && _pending.isNotEmpty) {
        _scheduleFlush();
      }
    }
  }
}
