import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiFormControlsPage extends StatelessWidget {
  const QuickjsUiFormControlsPage({super.key});

  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '表单控件',
    path: 'assets/quickjs_ui/form_controls_page.mjs',
  );
}
