/// Renderer diff statistics for one build pass.
final class JsUiDiffStats {
  /// 创建一次渲染 Diff 的统计快照。
  const JsUiDiffStats({
    this.rebuilt = 0,
    this.reused = 0,
    this.unkeyed = 0,
    this.rebuiltKeys = const <String>[],
    this.reusedKeys = const <String>[],
  });

  /// 本轮重新构建的带 Key 节点数。
  final int rebuilt;

  /// 本轮复用的带 Key 节点数。
  final int reused;

  /// 本轮处理的无 Key 节点数。
  final int unkeyed;

  /// 被重新构建的节点 Key。
  final List<String> rebuiltKeys;

  /// 被复用的节点 Key。
  final List<String> reusedKeys;

  /// 本轮处理的节点总数。
  int get total => rebuilt + reused + unkeyed;

  /// 转换为可序列化的诊断对象。
  Map<String, Object?> toMap() {
    return <String, Object?>{
      'rebuilt': rebuilt,
      'reused': reused,
      'unkeyed': unkeyed,
      'total': total,
      if (rebuiltKeys.isNotEmpty) 'rebuiltKeys': rebuiltKeys,
      if (reusedKeys.isNotEmpty) 'reusedKeys': reusedKeys,
    };
  }
}
