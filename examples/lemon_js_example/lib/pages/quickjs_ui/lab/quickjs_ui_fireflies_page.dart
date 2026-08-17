import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiFirefliesPage extends StatelessWidget {
  const JsUiFirefliesPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '粒子特效 · 萤火虫花园',
    path: 'assets/quickjs_ui/particle_fireflies_page.mjs',
  );
}
