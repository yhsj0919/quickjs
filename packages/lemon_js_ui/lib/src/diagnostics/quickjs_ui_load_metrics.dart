/// Structured timing data for one quickjs_ui page load.
final class QuickjsUiLoadMetrics {
  QuickjsUiLoadMetrics({required this.stages, required this.totalToSchema});

  /// Ordered load stages measured before Flutter builds the resulting schema.
  final Map<String, Duration> stages;

  /// Total time from controller load start until the first schema is ready.
  final Duration totalToSchema;

  QuickjsUiLoadMetrics withStage(String name, Duration duration) {
    return QuickjsUiLoadMetrics(
      stages: <String, Duration>{name: duration, ...stages},
      totalToSchema: totalToSchema + duration,
    );
  }

  String format() {
    final parts = stages.entries
        .map((entry) => '${entry.key}=${entry.value.inMicroseconds / 1000}ms')
        .join(', ');
    return '$parts, schemaTotal=${totalToSchema.inMicroseconds / 1000}ms';
  }
}
