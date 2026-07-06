/// Renderer diff statistics for one build pass.
final class QuickjsUiDiffStats {
  const QuickjsUiDiffStats({
    this.rebuilt = 0,
    this.reused = 0,
    this.unkeyed = 0,
    this.rebuiltKeys = const <String>[],
    this.reusedKeys = const <String>[],
  });

  final int rebuilt;
  final int reused;
  final int unkeyed;
  final List<String> rebuiltKeys;
  final List<String> reusedKeys;

  int get total => rebuilt + reused + unkeyed;

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
