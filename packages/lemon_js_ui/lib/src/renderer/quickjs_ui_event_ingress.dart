import 'dart:async';

import 'package:flutter/widgets.dart';

import 'quickjs_ui_render_context.dart';

typedef QuickjsUiEventSink = Future<void> Function(Map<String, Object?> event);

/// Queues renderer UI events and flushes them after the current frame so
/// controller updates never synchronously rebuild [QuickjsUiView] during build.
///
/// Events keep the order in which Flutter observed them. Samples are keyed by
/// [QuickjsUiEventEnvelope.coalesceKey] and only the latest value in the same
/// command-delimited slot is sent to JavaScript in a frame.
final class QuickjsUiEventIngress {
  QuickjsUiEventIngress(this._onEvent);

  final QuickjsUiEventSink _onEvent;
  final List<_PendingIngressEvent> _pending = <_PendingIngressEvent>[];
  final Map<String, _PendingIngressEvent> _pendingSampleSlots =
      <String, _PendingIngressEvent>{};
  bool _flushScheduled = false;
  bool _flushing = false;
  bool _disposed = false;

  void submit(Map<String, Object?> event) {
    submitEnvelope(QuickjsUiEventEnvelope.command(event));
  }

  void submitEnvelope(QuickjsUiEventEnvelope envelope) {
    if (_disposed) {
      return;
    }
    if (envelope.kind == QuickjsUiEventKind.sample &&
        envelope.coalesceKey != null) {
      final key = envelope.coalesceKey!;
      final pending = _pendingSampleSlots[key];
      if (pending != null) {
        pending.envelope = envelope;
        _scheduleFlush();
        return;
      }
      final item = _PendingIngressEvent.sample(envelope: envelope);
      _pending.add(item);
      _pendingSampleSlots[key] = item;
      _scheduleFlush();
      return;
    }

    final item = _PendingIngressEvent.command(envelope: envelope.asCommand());
    _pending.add(item);
    _pendingSampleSlots.clear();
    _scheduleFlush();
  }

  void dispose() {
    _disposed = true;
    _pending.clear();
    _pendingSampleSlots.clear();
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
    final batch = List<_PendingIngressEvent>.of(_pending);
    _pending.clear();
    _pendingSampleSlots.clear();
    try {
      for (final item in batch) {
        if (_disposed) {
          break;
        }
        await _onEvent(item.envelope.event);
      }
    } finally {
      _flushing = false;
      if (!_disposed && _pending.isNotEmpty) {
        _scheduleFlush();
      }
    }
  }
}

final class _PendingIngressEvent {
  _PendingIngressEvent.command({required this.envelope});

  _PendingIngressEvent.sample({required this.envelope});

  QuickjsUiEventEnvelope envelope;
}
