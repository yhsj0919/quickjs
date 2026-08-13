import 'package:lemon_js/lemon_js.dart';

part 'quickjs_ui_helpers.g.dart';

const String quickjsUiHelperModuleSpecifier = 'quickjs_ui';
const String quickjsUiRuntimeProtocol = 'quickjs_ui.runtime.v1';
const int quickjsUiSchemaVersion = 1;
const int quickjsUiHelperVersion = 1;

const JsModule quickjsUiHelperModule = JsModule.esModule(
  specifier: quickjsUiHelperModuleSpecifier,
  source: quickjsUiHelperModuleSource,
);

const JsFeatures quickjsUiHelperMount = JsFeatures(
  name: 'quickjs_ui:helpers',
  modules: <JsModule>[quickjsUiHelperModule],
);
