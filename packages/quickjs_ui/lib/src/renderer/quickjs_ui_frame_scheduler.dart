import 'dart:async';

import 'package:flutter/foundation.dart';

final class QuickjsUiFrameScheduler {
  final Map<int, QuickjsUiFrameClock> _clocks = <int, QuickjsUiFrameClock>{};

  QuickjsUiFrameClock clockFor(int intervalMs) => _clocks.putIfAbsent(
    intervalMs,
    () => QuickjsUiFrameClock(Duration(milliseconds: intervalMs)),
  );

  void dispose() {
    for (final clock in _clocks.values) {
      clock.dispose();
    }
    _clocks.clear();
  }
}

final class QuickjsUiFrameClock implements Listenable {
  QuickjsUiFrameClock(this.interval);

  final Duration interval;
  final Set<VoidCallback> _listeners = <VoidCallback>{};
  Timer? _timer;

  @override
  void addListener(VoidCallback listener) {
    if (!_listeners.add(listener)) return;
    _timer ??= Timer.periodic(interval, (_) => _notify());
  }

  @override
  void removeListener(VoidCallback listener) {
    _listeners.remove(listener);
    if (_listeners.isEmpty) {
      _timer?.cancel();
      _timer = null;
    }
  }

  void _notify() {
    for (final listener in List<VoidCallback>.of(_listeners)) {
      listener();
    }
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
    _listeners.clear();
  }
}
