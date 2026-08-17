import 'example_page_spec.dart';
import 'quickjs_ui_catalog/foundation_catalog.dart';
import 'quickjs_ui_catalog/getting_started_catalog.dart';
import 'quickjs_ui_catalog/lab_catalog.dart';
import 'quickjs_ui_catalog/platform_catalog.dart';
import 'quickjs_ui_catalog/scenario_catalog.dart';

export 'quickjs_ui_catalog/foundation_catalog.dart'
    show jsUiFoundationExamplePages;
export 'quickjs_ui_catalog/getting_started_catalog.dart'
    show jsUiGettingStartedExamplePages;
export 'quickjs_ui_catalog/lab_catalog.dart' show jsUiLabExamplePages;
export 'quickjs_ui_catalog/platform_catalog.dart' show jsUiPlatformExamplePages;
export 'quickjs_ui_catalog/scenario_catalog.dart' show jsUiScenarioExamplePages;

final List<ExamplePageSpec> jsUiExamplePages = <ExamplePageSpec>[
  ...jsUiGettingStartedExamplePages,
  ...jsUiFoundationExamplePages,
  ...jsUiPlatformExamplePages,
  ...jsUiScenarioExamplePages,
  ...jsUiLabExamplePages,
];
