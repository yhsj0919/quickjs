import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiScrollTransitionPage extends StatelessWidget {
  const QuickjsUiScrollTransitionPage({super.key});

  static const String path = 'assets/quickjs_ui/scroll_transition_page.mjs';

  @override
  Widget build(BuildContext context) =>
      const QuickjsUiAssetDemoPage(title: '滚动控制与嵌套滚动', path: path);
}
