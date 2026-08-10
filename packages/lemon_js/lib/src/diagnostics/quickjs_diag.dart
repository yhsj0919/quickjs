import 'package:flutter/foundation.dart';

/// Opt-in diagnostics for the QuickJS core runtime boundary.
///
/// Disabled by default. Keep this layer independent from
/// quickjs_ui diagnostics so core logs are still available to non-UI callers.
abstract final class QuickjsDiag {
  static bool enabled = false;

  static final Map<String, _QuickjsDiagBucket> _buckets =
      <String, _QuickjsDiagBucket>{};

  static void log(String channel, String message) {
    if (!enabled) {
      return;
    }
    debugPrint('[quickjs_diag/$channel ${_timestamp()}] $message');
  }

  static void count(String channel, {String? detail}) {
    if (!enabled) {
      return;
    }
    final bucket = _buckets.putIfAbsent(channel, _QuickjsDiagBucket.new);
    bucket.count += 1;
    if (detail != null) {
      bucket.lastDetail = detail;
    }
    final now = DateTime.now();
    if (bucket.lastReportedAt == null ||
        now.difference(bucket.lastReportedAt!) >= bucket.interval) {
      final suffix = bucket.lastDetail == null
          ? ''
          : ' last=${bucket.lastDetail}';
      debugPrint(
        '[quickjs_diag/$channel ${_timestamp(now)}] '
        'count=${bucket.count}$suffix',
      );
      bucket.count = 0;
      bucket.lastDetail = null;
      bucket.lastReportedAt = now;
    }
  }

  static void reset() {
    _buckets.clear();
  }

  static String _timestamp([DateTime? value]) {
    final time = value ?? DateTime.now();
    return '${_two(time.hour)}:${_two(time.minute)}:${_two(time.second)}.'
        '${_three(time.millisecond)}';
  }

  static String _two(int value) => value.toString().padLeft(2, '0');

  static String _three(int value) => value.toString().padLeft(3, '0');
}

final class _QuickjsDiagBucket {
  int count = 0;
  String? lastDetail;
  DateTime? lastReportedAt;
  Duration interval = const Duration(seconds: 5);
}
