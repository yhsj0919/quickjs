import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiKeyedListTransitionsPage extends StatelessWidget {
  const QuickjsUiKeyedListTransitionsPage({super.key});

  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: 'Stable Key 列表过渡',
    path: 'assets/quickjs_ui/keyed_list_transitions_page.mjs',
  );
}
