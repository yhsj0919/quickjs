// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart';

/// Opt-in runtime diagnostics for quickjs_ui pipeline debugging.
///
/// Enabled in debug mode by default. Set [enabled] to true in profile/release
/// builds when investigating issues such as progress event storms.
abstract final class JsUiDiag {
  static bool enabled = kDebugMode;

  static final Map<String, _JsUiDiagBucket> _buckets =
      <String, _JsUiDiagBucket>{};

  static void log(String channel, String message) {
    if (!enabled) {
      return;
    }
    debugPrint('[quickjs_ui_diag/$channel] $message');
  }

  static void count(String channel, {String? detail}) {
    if (!enabled) {
      return;
    }
    final bucket = _buckets.putIfAbsent(channel, _JsUiDiagBucket.new);
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
      debugPrint('[quickjs_ui_diag/$channel] count=${bucket.count}$suffix');
      bucket.count = 0;
      bucket.lastDetail = null;
      bucket.lastReportedAt = now;
    }
  }

  static void reset() {
    _buckets.clear();
  }
}

final class _JsUiDiagBucket {
  _JsUiDiagBucket();

  int count = 0;
  String? lastDetail;
  DateTime? lastReportedAt;
  Duration interval = const Duration(seconds: 5);
}
