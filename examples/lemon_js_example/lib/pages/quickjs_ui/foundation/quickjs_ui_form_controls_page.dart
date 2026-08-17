import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiFormControlsPage extends StatelessWidget {
  const JsUiFormControlsPage({super.key});

  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: '表单控件',
    path: 'assets/quickjs_ui/form_controls_page.mjs',
  );
}
