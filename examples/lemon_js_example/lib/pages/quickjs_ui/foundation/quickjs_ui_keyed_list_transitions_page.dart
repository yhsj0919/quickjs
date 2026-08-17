import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiKeyedListTransitionsPage extends StatelessWidget {
  const JsUiKeyedListTransitionsPage({super.key});

  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: 'Stable Key 列表过渡',
    path: 'assets/quickjs_ui/keyed_list_transitions_page.mjs',
  );
}
