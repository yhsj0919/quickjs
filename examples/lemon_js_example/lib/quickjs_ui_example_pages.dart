import 'example_page_spec.dart';
import 'quickjs_ui_catalog/foundation_catalog.dart';
import 'quickjs_ui_catalog/getting_started_catalog.dart';
import 'quickjs_ui_catalog/lab_catalog.dart';
import 'quickjs_ui_catalog/platform_catalog.dart';
import 'quickjs_ui_catalog/scenario_catalog.dart';

export 'quickjs_ui_catalog/foundation_catalog.dart'
    show quickjsUiFoundationExamplePages;
export 'quickjs_ui_catalog/getting_started_catalog.dart'
    show quickjsUiGettingStartedExamplePages;
export 'quickjs_ui_catalog/lab_catalog.dart' show quickjsUiLabExamplePages;
export 'quickjs_ui_catalog/platform_catalog.dart'
    show quickjsUiPlatformExamplePages;
export 'quickjs_ui_catalog/scenario_catalog.dart'
    show quickjsUiScenarioExamplePages;

final List<ExamplePageSpec> quickjsUiExamplePages = <ExamplePageSpec>[
  ...quickjsUiGettingStartedExamplePages,
  ...quickjsUiFoundationExamplePages,
  ...quickjsUiPlatformExamplePages,
  ...quickjsUiScenarioExamplePages,
  ...quickjsUiLabExamplePages,
];
