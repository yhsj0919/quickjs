import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class QuickjsUiControlStatesSlotsPage extends StatelessWidget {
  const QuickjsUiControlStatesSlotsPage({super.key});
  @override
  Widget build(BuildContext context) => const QuickjsUiAssetDemoPage(
    title: '控件状态与结构插槽',
    path: 'assets/quickjs_ui/control_states_slots_page.mjs',
  );
}
