/// Structured timing data for one quickjs_ui page load.
final class QuickjsUiLoadMetrics {
  QuickjsUiLoadMetrics({
    required this.stages,
    required this.totalToSchema,
    this.details = const <String, Duration>{},
    DateTime? schemaReadyAt,
    this.readyNotifiedAt,
  }) : schemaReadyAt = schemaReadyAt ?? DateTime.now();

  /// Ordered load stages measured before Flutter builds the resulting schema.
  final Map<String, Duration> stages;

  /// Total time from controller load start until the first schema is ready.
  final Duration totalToSchema;

  /// Nested timings that explain a stage and are not added to the total.
  final Map<String, Duration> details;

  /// Wall-clock boundary used to split schema-to-frame Flutter work.
  final DateTime schemaReadyAt;
  final DateTime? readyNotifiedAt;

  QuickjsUiLoadMetrics withStage(String name, Duration duration) {
    return QuickjsUiLoadMetrics(
      stages: <String, Duration>{name: duration, ...stages},
      totalToSchema: totalToSchema + duration,
      details: details,
      schemaReadyAt: schemaReadyAt,
      readyNotifiedAt: readyNotifiedAt,
    );
  }

  QuickjsUiLoadMetrics withDetail(String name, Duration duration) {
    return QuickjsUiLoadMetrics(
      stages: stages,
      totalToSchema: totalToSchema,
      details: <String, Duration>{...details, name: duration},
      schemaReadyAt: schemaReadyAt,
      readyNotifiedAt: readyNotifiedAt,
    );
  }

  QuickjsUiLoadMetrics withReadyNotifiedAt(DateTime value) {
    return QuickjsUiLoadMetrics(
      stages: stages,
      totalToSchema: totalToSchema,
      details: details,
      schemaReadyAt: schemaReadyAt,
      readyNotifiedAt: value,
    );
  }

  String format() {
    final parts = stages.entries
        .map((entry) => '${entry.key}=${entry.value.inMicroseconds / 1000}ms')
        .join(', ');
    final detailParts = details.entries
        .map((entry) => '${entry.key}=${entry.value.inMicroseconds / 1000}ms')
        .join(', ');
    return '$parts, schemaTotal=${totalToSchema.inMicroseconds / 1000}ms'
        '${detailParts.isEmpty ? '' : ', details: $detailParts'}';
  }
}
