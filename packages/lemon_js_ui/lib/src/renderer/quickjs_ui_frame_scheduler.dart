// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:flutter/foundation.dart';
import 'package:flutter/scheduler.dart';

final class JsUiFrameScheduler {
  final Map<int, JsUiFrameClock> _clocks = <int, JsUiFrameClock>{};

  JsUiFrameClock clockFor(int intervalMs) => _clocks.putIfAbsent(
    intervalMs,
    () => JsUiFrameClock(Duration(milliseconds: intervalMs)),
  );

  void dispose() {
    for (final clock in _clocks.values) {
      clock.dispose();
    }
    _clocks.clear();
  }
}

final class JsUiFrameClock implements Listenable {
  JsUiFrameClock(this.interval);

  final Duration interval;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Ticker? _ticker;
  Duration _lastDispatch = Duration.zero;

  @override
  void addListener(VoidCallback listener) {
    if (!_listeners.add(listener)) return;
    if (_ticker == null) {
      _lastDispatch = Duration.zero;
      _ticker = Ticker(_tick)..start();
    }
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _stopTicker();
    }
  }

  void _tick(Duration elapsed) {
    // Allow a small tolerance for display-period rounding (for example,
    // 16.666ms VSync versus a requested 33ms interval). Notifications still
    // happen only on VSync boundaries, so a 30fps clock on 60Hz advances on
    // every second display frame instead of drifting against it.
    const tolerance = Duration(microseconds: 500);
    if (elapsed - _lastDispatch + tolerance < interval) return;
    _lastDispatch = elapsed;
    _notify();
  }

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _stopTicker();
    _listeners.clear();
  }

  void _stopTicker() {
    _ticker?.dispose();
    _ticker = null;
    _lastDispatch = Duration.zero;
  }
}
