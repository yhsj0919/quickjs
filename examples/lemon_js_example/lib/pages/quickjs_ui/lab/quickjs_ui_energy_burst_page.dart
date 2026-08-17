import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiEnergyBurstPage extends StatelessWidget {
  const JsUiEnergyBurstPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '粒子特效 · 能量爆发',
    path: 'assets/quickjs_ui/particle_energy_burst_page.mjs',
  );
}
