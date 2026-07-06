/// One recorded lifecycle or action event for inspector timelines.
final class QuickjsUiLifecycleEvent {
  const QuickjsUiLifecycleEvent({
    required this.phase,
    required this.type,
    this.payload,
    required this.timestamp,
  });

  /// Event source: `widget`, `route`, `app`, or `action`.
  final String phase;

  /// Event name, for example `mount`, `show`, `dispatch`, `pause`.
  final String type;

  final Object? payload;
  final DateTime timestamp;

  Map<String, Object?> toMap() {
    return <String, Object?>{
      'phase': phase,
      'type': type,
      if (payload != null) 'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
