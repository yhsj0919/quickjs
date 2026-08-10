import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiNeonGalaxyPage extends StatelessWidget {
  const QuickjsUiNeonGalaxyPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: '粒子特效 · 霓虹星系',
    path: 'assets/quickjs_ui/particle_galaxy_page.mjs',
  );
}
