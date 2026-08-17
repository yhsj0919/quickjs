import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiStarfieldPage extends StatelessWidget {
  const JsUiStarfieldPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '粒子特效 · 星际穿梭',
    path: 'assets/quickjs_ui/particle_starfield_page.mjs',
  );
}
