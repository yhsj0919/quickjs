import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiEnergyBurstPage extends StatelessWidget {
  const QuickjsUiEnergyBurstPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiDarkAssetDemoPage(
    title: '粒子特效 · 能量爆发',
    path: 'assets/quickjs_ui/particle_energy_burst_page.mjs',
  );
}
