import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiControlMotionStressPage extends StatelessWidget {
  const JsUiControlMotionStressPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '控件动画性能压力测试',
    path: 'assets/quickjs_ui/control_motion_stress_page.mjs',
  );
}
