import 'package:quickjs/quickjs.dart';

part 'quickjs_ui_helpers.g.dart';

const String quickjsUiHelperModuleSpecifier = 'quickjs_ui';
const String quickjsUiRuntimeProtocol = 'quickjs_ui.runtime.v1';
const int quickjsUiSchemaVersion = 1;
const int quickjsUiHelperVersion = 1;

const QuickjsHostModule quickjsUiHelperModule = QuickjsHostModule.esModule(
  specifier: quickjsUiHelperModuleSpecifier,
  source: quickjsUiHelperModuleSource,
);

const QuickjsHostMount quickjsUiHelperMount = QuickjsHostMount(
  name: 'quickjs_ui:helpers',
  modules: <QuickjsHostModule>[quickjsUiHelperModule],
);
