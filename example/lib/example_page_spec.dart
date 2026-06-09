import 'package:flutter/widgets.dart';

/// example 首页中每个演示页面的元信息。
class ExamplePageSpec {
  const ExamplePageSpec({
    required this.title,
    required this.description,
    required this.builder,
  });

  final String title;
  final String description;
  final WidgetBuilder builder;
}
