import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiControlsPage extends StatelessWidget {
  const QuickjsUiControlsPage({super.key});

  static const String path = 'assets/quickjs_ui/controls_page.mjs';

  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '布局与媒体基础',
    path: path,
  );
}
