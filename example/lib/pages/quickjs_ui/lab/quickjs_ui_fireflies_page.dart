import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiFirefliesPage extends StatelessWidget {
  const QuickjsUiFirefliesPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: '粒子特效 · 萤火虫花园',
    path: 'assets/quickjs_ui/particle_fireflies_page.mjs',
  );
}
