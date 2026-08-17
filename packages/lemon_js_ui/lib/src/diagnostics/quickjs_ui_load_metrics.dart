/// Structured timing data for one quickjs_ui page load.
final class JsUiLoadMetrics {
  /// 创建一次页面加载的分阶段耗时快照。
  JsUiLoadMetrics({required this.stages, required this.totalToSchema});

  /// Ordered load stages measured before Flutter builds the resulting schema.
  final Map<String, Duration> stages;

  /// Total time from controller load start until the first schema is ready.
  final Duration totalToSchema;

  /// 返回在现有指标前增加 [name] 阶段后的新快照。
  JsUiLoadMetrics withStage(String name, Duration duration) {
    return JsUiLoadMetrics(
      stages: <String, Duration>{name: duration, ...stages},
      totalToSchema: totalToSchema + duration,
    );
  }

  /// 格式化为适合诊断日志的单行文本。
  String format() {
    final parts = stages.entries
        .map((entry) => '${entry.key}=${entry.value.inMicroseconds / 1000}ms')
        .join(', ');
    return '$parts, schemaTotal=${totalToSchema.inMicroseconds / 1000}ms';
  }
}
