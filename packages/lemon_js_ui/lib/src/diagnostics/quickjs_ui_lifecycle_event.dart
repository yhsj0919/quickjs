/// One recorded lifecycle or action event for inspector timelines.
final class JsUiLifecycleEvent {
  /// 创建一个发生于 [timestamp] 的生命周期或 Action 事件。
  const JsUiLifecycleEvent({
    required this.phase,
    required this.type,
    this.payload,
    required this.timestamp,
  });

  /// Event source: `widget`, `route`, `app`, or `action`.
  final String phase;

  /// Event name, for example `mount`, `show`, `dispatch`, `pause`.
  final String type;

  /// 事件携带的可选结构化数据。
  final Object? payload;

  /// 事件发生时间。
  final DateTime timestamp;

  /// 转换为可序列化的时间线对象。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'phase': phase,
      'type': type,
      if (payload != null) 'payload': payload,
      'timestamp': timestamp.toIso8601String(),
    };
  }
}
