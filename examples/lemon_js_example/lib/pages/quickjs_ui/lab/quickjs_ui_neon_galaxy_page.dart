import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiNeonGalaxyPage extends StatelessWidget {
  const JsUiNeonGalaxyPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '粒子特效 · 霓虹星系',
    path: 'assets/quickjs_ui/particle_galaxy_page.mjs',
  );
}
