import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiControlStateTransitionsPage extends StatelessWidget {
  const JsUiControlStateTransitionsPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiAssetDemoPage(
    title: '控件状态过渡动画',
    path: 'assets/quickjs_ui/control_state_transitions_page.mjs',
  );
}
