import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiScrollTransitionPage extends StatelessWidget {
  const JsUiScrollTransitionPage({super.key});

  static const String path = 'assets/quickjs_ui/scroll_transition_page.mjs';

  @override
  Widget build(BuildContext context) =>
      const JsUiAssetDemoPage(title: '滚动控制与嵌套滚动', path: path);
}
