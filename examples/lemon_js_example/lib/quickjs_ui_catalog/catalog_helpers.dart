import 'package:flutter/widgets.dart';

import '../example_page_spec.dart';

ExamplePageSpec jsUiPageSpec({
  required ExampleCategory category,
  required String title,
  required String description,
  required WidgetBuilder builder,
  ExampleKind kind = ExampleKind.demo,
  ExampleStatus status = ExampleStatus.stable,
  List<String> tags = const <String>[],
}) => ExamplePageSpec(
  title: title,
  description: description,
  builder: builder,
  category: category,
  kind: kind,
  status: status,
  tags: tags,
);

ExamplePageSpec jsUiLabSpec({
  required String title,
  required String description,
  required WidgetBuilder builder,
}) => jsUiPageSpec(
  category: ExampleCategory.lab,
  kind: ExampleKind.benchmark,
  status: ExampleStatus.experimental,
  tags: const <String>['lab'],
  title: title,
  description: description,
  builder: builder,
);
