// Internal implementation library; not exported as stable package API.
// ignore_for_file: public_member_api_docs

import 'package:lemon_js/lemon_js.dart';

part 'quickjs_ui_helpers.g.dart';

const String jsUiHelperModuleSpecifier = 'quickjs_ui';
const String jsUiRuntimeProtocol = 'quickjs_ui.runtime.v1';
const int jsUiSchemaVersion = 1;
const int jsUiHelperVersion = 1;

const JsModule jsUiHelperModule = JsModule(
  name: jsUiHelperModuleSpecifier,
  source: jsUiHelperModuleSource,
);

const JsFeatures jsUiHelperFeatures = JsFeatures(
  name: 'quickjs_ui:helpers',
  modules: <JsModule>[jsUiHelperModule],
);
