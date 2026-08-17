import 'package:flutter/widgets.dart';
import '../shared/quickjs_ui_asset_demo_page.dart';

class JsUiOverlaySystemPage extends StatelessWidget {
  const JsUiOverlaySystemPage({super.key});
  @override
  Widget build(BuildContext context) => const JsUiDarkAssetDemoPage(
    title: '任意内容浮层系统',
    path: 'assets/quickjs_ui/overlay_system_page.mjs',
  );
}
