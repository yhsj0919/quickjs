import 'package:flutter/widgets.dart';

enum ExampleCategory {
  core,
  gettingStarted,
  uiFoundation,
  platform,
  scenario,
  lab,
}

enum ExampleKind { demo, scenario, diagnostic, benchmark }

enum ExampleStatus { stable, experimental, development }

/// example 首页中每个演示页面的元信息。
class ExamplePageSpec {
  const ExamplePageSpec({
    required this.title,
    required this.description,
    required this.builder,
    this.category = ExampleCategory.core,
    this.kind = ExampleKind.demo,
    this.status = ExampleStatus.stable,
    this.tags = const <String>[],
    this.sourcePath,
  });

  final String title;
  final String description;
  final WidgetBuilder builder;
  final ExampleCategory category;
  final ExampleKind kind;
  final ExampleStatus status;
  final List<String> tags;
  final String? sourcePath;
}
