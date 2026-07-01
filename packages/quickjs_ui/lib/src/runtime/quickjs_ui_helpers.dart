import 'package:quickjs/quickjs.dart';

part 'quickjs_ui_helpers.g.dart';

const String quickjsUiHelperModuleSpecifier = 'quickjs_ui';

const QuickjsHostModule quickjsUiHelperModule = QuickjsHostModule.esModule(
  specifier: quickjsUiHelperModuleSpecifier,
  source: quickjsUiHelperModuleSource,
);

const QuickjsHostMount quickjsUiHelperMount = QuickjsHostMount(
  name: 'quickjs_ui:helpers',
  modules: <QuickjsHostModule>[quickjsUiHelperModule],
);
