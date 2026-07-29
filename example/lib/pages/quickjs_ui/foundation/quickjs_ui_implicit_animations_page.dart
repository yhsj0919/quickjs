import 'package:flutter/widgets.dart';

import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiImplicitAnimationsPage extends StatelessWidget {
  const QuickjsUiImplicitAnimationsPage({super.key});

  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '基础隐式动画',
    path: 'assets/quickjs_ui/implicit_animations_page.mjs',
  );
}
