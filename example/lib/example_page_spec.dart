import 'package:flutter/widgets.dart';

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
