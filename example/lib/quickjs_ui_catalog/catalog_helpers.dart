import 'package:flutter/widgets.dart';

import '../example_page_spec.dart';

ExamplePageSpec quickjsUiPageSpec({
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

ExamplePageSpec quickjsUiLabSpec({
  required String title,
  required String description,
  required WidgetBuilder builder,
}) => quickjsUiPageSpec(
  category: ExampleCategory.lab,
  kind: ExampleKind.benchmark,
  status: ExampleStatus.experimental,
  tags: const <String>['lab'],
  title: title,
  description: description,
  builder: builder,
);
